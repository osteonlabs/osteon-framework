import http from 'node:http';
import { URL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
import { getCdiMetrics } from './cdi.js';
import { queryAuthoritativeFacts, maskPiiAndSecrets } from './facts.js';
import { listContracts, verifyContract } from './contracts.js';
import { loadManifest, findManifestPath } from './manifest.js';
import { recordTelemetryEvent, getTelemetrySummary } from './telemetry.js';

/**
 * Creates an HTTP/REST server for headless cloud agent clusters and CI/CD pipelines.
 * @param {string} projectDir
 * @param {number} port
 * @returns {http.Server}
 */
export function createHttpServer(projectDir = process.cwd(), port = 8080) {
  const baseDir = path.resolve(projectDir);

  const server = http.createServer(async (req, res) => {
    // Enable CORS
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Tenant-ID');

    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      res.end();
      return;
    }

    const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const pathname = parsedUrl.pathname;

    const tenantHeader = req.headers['x-tenant-id'];

    // Helper to send JSON response
    const sendJson = (status, data) => {
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(data, null, 2));
    };

    // Helper to read JSON request body
    const readBody = () => new Promise((resolve, reject) => {
      let body = '';
      req.on('data', chunk => { body += chunk; });
      req.on('end', () => {
        if (!body.trim()) return resolve({});
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          reject(new Error(`Invalid JSON body: ${e.message}`));
        }
      });
      req.on('error', reject);
    });

    const startTime = performance.now();

    try {
      // 1. Health check
      if (pathname === '/health' || pathname === '/api/v1/health') {
        let tenantId = 'tenant-default';
        try {
          const { manifest } = loadManifest(baseDir);
          if (manifest.tenant?.id) tenantId = manifest.tenant.id;
        } catch (_) {}

        return sendJson(200, {
          status: 'ok',
          service: '@osteon/mcp-server',
          version: '0.1.2',
          tenant_id: tenantId,
          timestamp: new Date().toISOString()
        });
      }

      // 2. GET /api/v1/cdi
      if (req.method === 'GET' && pathname === '/api/v1/cdi') {
        const metrics = await getCdiMetrics(baseDir);
        recordTelemetryEvent(baseDir, {
          tool: 'http_get_cdi',
          tenant_id: tenantHeader || 'tenant-default',
          latency_ms: Math.round(performance.now() - startTime),
          tokens_estimated: 80,
          status: 'success'
        });
        return sendJson(200, metrics);
      }

      // 3. POST /api/v1/facts/query
      if (req.method === 'POST' && pathname === '/api/v1/facts/query') {
        const body = await readBody();
        const effectiveTenant = tenantHeader || body.tenant_id;

        let manifest = null;
        try {
          manifest = loadManifest(baseDir).manifest;
        } catch (_) {}

        if (effectiveTenant && manifest?.tenant?.id && manifest.tenant.id !== effectiveTenant) {
          return sendJson(403, {
            error: 'Forbidden',
            message: `Tenant '${effectiveTenant}' does not match repository tenant '${manifest.tenant.id}'`
          });
        }

        let facts = queryAuthoritativeFacts(baseDir, body.query || '', body.tier || null, body.limit || 10);
        if (manifest?.tenant?.pii_masking) {
          facts = facts.map(f => ({
            ...f,
            text: maskPiiAndSecrets(f.text)
          }));
        }

        recordTelemetryEvent(baseDir, {
          tool: 'http_query_fact',
          tenant_id: effectiveTenant || 'tenant-default',
          latency_ms: Math.round(performance.now() - startTime),
          tokens_estimated: Math.ceil(JSON.stringify(facts).length / 4),
          status: 'success'
        });

        return sendJson(200, {
          tenant_id: manifest?.tenant?.id || 'tenant-default',
          count: facts.length,
          facts
        });
      }

      // 4. POST /api/v1/contracts/verify
      if (req.method === 'POST' && pathname === '/api/v1/contracts/verify') {
        const body = await readBody();
        if (!body.contract_name) {
          return sendJson(400, { error: 'Bad Request', message: 'Missing contract_name parameter' });
        }
        const verification = verifyContract(baseDir, body.contract_name, body.payload || null);
        return sendJson(200, verification);
      }

      // 5. GET /api/v1/telemetry
      if (req.method === 'GET' && pathname === '/api/v1/telemetry') {
        const filterTenant = parsedUrl.searchParams.get('tenant_id') || tenantHeader;
        const summary = getTelemetrySummary(baseDir, filterTenant);
        return sendJson(200, summary);
      }

      // 6. POST /api/v1/curation/webhook (Async escalation intake)
      if (req.method === 'POST' && (pathname === '/api/v1/curation/webhook' || pathname === '/api/v1/curation/escalations')) {
        const body = await readBody();
        const escalationLog = path.join(baseDir, 'metrics', 'curation-escalations.jsonl');
        const escalationEntry = {
          timestamp: new Date().toISOString(),
          source: 'cloud-webhook',
          tenant_id: tenantHeader || body.tenant_id || 'tenant-default',
          ...body
        };
        fs.mkdirSync(path.dirname(escalationLog), { recursive: true });
        fs.appendFileSync(escalationLog, JSON.stringify(escalationEntry) + '\n');

        return sendJson(201, {
          recorded: true,
          escalation: escalationEntry
        });
      }

      // 7. Generic POST /api/v1/tools/:name
      if (req.method === 'POST' && pathname.startsWith('/api/v1/tools/')) {
        const toolName = pathname.replace('/api/v1/tools/', '');
        const body = await readBody();

        switch (toolName) {
          case 'osteon_get_cdi': {
            const metrics = await getCdiMetrics(baseDir);
            return sendJson(200, metrics);
          }
          case 'osteon_inspect_manifest': {
            const { path: manifestPath, manifest } = loadManifest(baseDir);
            return sendJson(200, { path: manifestPath, manifest });
          }
          case 'osteon_verify_contract': {
            const verification = verifyContract(baseDir, body.contract_name, body.payload || null);
            return sendJson(200, verification);
          }
          default:
            return sendJson(404, { error: 'Not Found', message: `Unknown tool: ${toolName}` });
        }
      }

      sendJson(404, { error: 'Not Found', path: pathname });
    } catch (err) {
      sendJson(500, { error: 'Internal Server Error', message: err.message });
    }
  });

  return server;
}
