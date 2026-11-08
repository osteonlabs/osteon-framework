import readline from 'node:readline';
import fs from 'node:fs';
import path from 'node:path';
import { loadManifest, findManifestPath } from './manifest.js';
import { getCdiMetrics } from './cdi.js';
import { queryAuthoritativeFacts, maskPiiAndSecrets } from './facts.js';
import { listContracts, verifyContract } from './contracts.js';
import { PROMPTS } from './prompts.js';

const PROTOCOL_VERSION = '2024-11-05';
const SERVER_NAME = '@osteon/mcp-server';
const SERVER_VERSION = '0.1.2';

/**
 * Standard MCP JSON-RPC Server over STDIO
 */
export class OsteonMcpServer {
  constructor(defaultProjectDir = process.cwd()) {
    this.defaultProjectDir = defaultProjectDir;
    this.rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
      terminal: false
    });
  }

  start() {
    this.rl.on('line', async (line) => {
      const trimmed = line.trim();
      if (!trimmed) return;

      try {
        const request = JSON.parse(trimmed);
        await this.handleMessage(request);
      } catch (err) {
        this.sendError(null, -32700, `Parse error: ${err.message}`);
      }
    });

    // Write diagnostic to stderr so stdout remains clean JSON-RPC
    console.error(`[osteon-mcp] Server v${SERVER_VERSION} initialized in ${this.defaultProjectDir}`);
  }

  async handleMessage(req) {
    // If it's a notification (no id)
    if (req.id === undefined || req.id === null) {
      if (req.method === 'notifications/initialized') {
        // Client confirmed initialization
      }
      return;
    }

    try {
      switch (req.method) {
        case 'initialize':
          this.sendResult(req.id, {
            protocolVersion: PROTOCOL_VERSION,
            serverInfo: {
              name: SERVER_NAME,
              version: SERVER_VERSION
            },
            capabilities: {
              tools: {},
              resources: {},
              prompts: {}
            }
          });
          break;

        case 'ping':
          this.sendResult(req.id, {});
          break;

        case 'tools/list':
          this.sendResult(req.id, {
            tools: this.getToolsList()
          });
          break;

        case 'tools/call':
          const toolResult = await this.handleToolCall(req.params.name, req.params.arguments || {});
          this.sendResult(req.id, toolResult);
          break;

        case 'resources/list':
          this.sendResult(req.id, {
            resources: this.getResourcesList()
          });
          break;

        case 'resources/read':
          const resourceResult = this.handleResourceRead(req.params.uri);
          this.sendResult(req.id, resourceResult);
          break;

        case 'prompts/list':
          this.sendResult(req.id, {
            prompts: Object.values(PROMPTS).map(p => ({
              name: p.name,
              description: p.description,
              arguments: p.arguments
            }))
          });
          break;

        case 'prompts/get':
          const prompt = PROMPTS[req.params.name];
          if (!prompt) {
            this.sendError(req.id, -32602, `Unknown prompt: ${req.params.name}`);
            return;
          }
          this.sendResult(req.id, {
            description: prompt.description,
            messages: prompt.generate(req.params.arguments || {})
          });
          break;

        default:
          this.sendError(req.id, -32601, `Method not found: ${req.method}`);
      }
    } catch (err) {
      this.sendError(req.id, -32603, `Internal error: ${err.message}`);
    }
  }

  getToolsList() {
    return [
      {
        name: 'osteon_get_cdi',
        description: 'Computes Context Decay Index (CDI), coverage, units_anchored, and lists decayed markdown blocks and drifted source files.',
        inputSchema: {
          type: 'object',
          properties: {
            project_path: {
              type: 'string',
              description: 'Target BONE project root directory (defaults to server root)'
            }
          }
        }
      },
      {
        name: 'osteon_query_fact',
        description: 'Queries authoritative single-owner facts across ADRs, Seam Contracts, and BONE skills with provenance token verification.',
        inputSchema: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'Topic, keyword, or alias to search for'
            },
            tier: {
              type: 'string',
              description: 'Optional tier filter (T0, T1, T2, T3)'
            },
            project_path: {
              type: 'string',
              description: 'Target BONE project root directory'
            }
          },
          required: ['query']
        }
      },
      {
        name: 'osteon_verify_contract',
        description: 'Validates whether a payload or interface change complies with a registered BONE Seam Contract in docs/contracts/.',
        inputSchema: {
          type: 'object',
          properties: {
            contract_name: {
              type: 'string',
              description: 'Basename of the contract (e.g. "payment service seam" or "lending-api")'
            },
            payload: {
              type: 'object',
              description: 'JSON payload to validate against contract schema invariants'
            },
            project_path: {
              type: 'string',
              description: 'Target BONE project root directory'
            }
          },
          required: ['contract_name']
        }
      },
      {
        name: 'osteon_inspect_manifest',
        description: 'Parses and returns MANIFEST.yaml structure, watched paths, repo aliases, tier hierarchy, and curation policies.',
        inputSchema: {
          type: 'object',
          properties: {
            project_path: {
              type: 'string',
              description: 'Target BONE project root directory'
            }
          }
        }
      },
      {
        name: 'osteon_reanchor',
        description: 'Authoritative re-anchoring of drifted knowledge blocks to new source git commits after verified update.',
        inputSchema: {
          type: 'object',
          properties: {
            file_path: {
              type: 'string',
              description: 'Relative path of the markdown knowledge unit (e.g. .claude/skills/my-skill.md)'
            },
            old_token: {
              type: 'string',
              description: 'Existing provenance token to replace'
            },
            new_token: {
              type: 'string',
              description: 'New provenance token'
            },
            justification: {
              type: 'string',
              description: 'Curator justification note'
            },
            project_path: {
              type: 'string',
              description: 'Target BONE project root directory'
            }
          },
          required: ['file_path', 'old_token', 'new_token', 'justification']
        }
      }
    ];
  }

  async handleToolCall(name, args) {
    const projectDir = args.project_path || this.defaultProjectDir;

    switch (name) {
      case 'osteon_get_cdi': {
        const metrics = await getCdiMetrics(projectDir);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(metrics, null, 2)
            }
          ]
        };
      }

      case 'osteon_query_fact': {
        let manifest = null;
        try {
          manifest = loadManifest(projectDir).manifest;
        } catch (_) {}

        if (args.tenant_id && manifest && manifest.tenant && manifest.tenant.id !== args.tenant_id) {
          return {
            isError: true,
            content: [{
              type: 'text',
              text: `Access denied: Tenant '${args.tenant_id}' does not match repository tenant '${manifest.tenant.id}'`
            }]
          };
        }

        let facts = queryAuthoritativeFacts(projectDir, args.query, args.tier || null);
        if (manifest?.tenant?.pii_masking) {
          facts = facts.map(f => ({
            ...f,
            text: maskPiiAndSecrets(f.text)
          }));
        }

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                tenant_id: manifest?.tenant?.id || 'tenant-default',
                count: facts.length,
                facts
              }, null, 2)
            }
          ]
        };
      }

      case 'osteon_verify_contract': {
        const verification = verifyContract(projectDir, args.contract_name, args.payload || null);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(verification, null, 2)
            }
          ]
        };
      }

      case 'osteon_inspect_manifest': {
        const { path: manifestPath, manifest } = loadManifest(projectDir);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({ path: manifestPath, manifest }, null, 2)
            }
          ]
        };
      }

      case 'osteon_reanchor': {
        const fullPath = path.resolve(projectDir, args.file_path);
        if (!fs.existsSync(fullPath)) {
          return {
            isError: true,
            content: [{ type: 'text', text: `File not found: ${args.file_path}` }]
          };
        }

        let content = fs.readFileSync(fullPath, 'utf8');
        if (!content.includes(args.old_token)) {
          return {
            isError: true,
            content: [{ type: 'text', text: `Token '${args.old_token}' not found in ${args.file_path}` }]
          };
        }

        content = content.replace(args.old_token, args.new_token);
        fs.writeFileSync(fullPath, content, 'utf8');

        // Append to curation escalations / audit stream if available
        const escalationLog = path.join(projectDir, 'metrics', 'curation-escalations.jsonl');
        const auditEntry = {
          timestamp: new Date().toISOString(),
          action: 'reanchor',
          file: args.file_path,
          old_token: args.old_token,
          new_token: args.new_token,
          justification: args.justification
        };
        try {
          fs.mkdirSync(path.dirname(escalationLog), { recursive: true });
          fs.appendFileSync(escalationLog, JSON.stringify(auditEntry) + '\n');
        } catch (_) {}

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({ success: true, audit: auditEntry }, null, 2)
            }
          ]
        };
      }

      default:
        return {
          isError: true,
          content: [{ type: 'text', text: `Unknown tool: ${name}` }]
        };
    }
  }

  getResourcesList() {
    const baseDir = this.defaultProjectDir;
    const resources = [
      {
        uri: 'bone://manifest',
        name: 'BONE Project Manifest',
        mimeType: 'text/yaml',
        description: 'Active MANIFEST.yaml defining project watch sets, tiers, and curation policies'
      },
      {
        uri: 'bone://metrics/baseline',
        name: 'Curation Baseline',
        mimeType: 'text/tab-separated-values',
        description: 'Sealed cryptographic digest baseline (metrics/curation-baseline.tsv)'
      }
    ];

    const contracts = listContracts(baseDir);
    for (const c of contracts) {
      resources.push({
        uri: `bone://contracts/${c.name}`,
        name: `Seam Contract: ${c.name}`,
        mimeType: 'text/markdown',
        description: `Seam contract ${c.name} (${c.tier}, version ${c.version})`
      });
    }

    return resources;
  }

  handleResourceRead(uri) {
    const baseDir = this.defaultProjectDir;

    if (uri === 'bone://manifest') {
      const manifestPath = findManifestPath(baseDir);
      if (!manifestPath || !fs.existsSync(manifestPath)) {
        throw new Error('MANIFEST.yaml not found');
      }
      return {
        contents: [
          {
            uri,
            mimeType: 'text/yaml',
            text: fs.readFileSync(manifestPath, 'utf8')
          }
        ]
      };
    }

    if (uri === 'bone://metrics/baseline') {
      const baselinePath = path.join(baseDir, 'metrics', 'curation-baseline.tsv');
      if (!fs.existsSync(baselinePath)) {
        throw new Error('metrics/curation-baseline.tsv not found');
      }
      return {
        contents: [
          {
            uri,
            mimeType: 'text/tab-separated-values',
            text: fs.readFileSync(baselinePath, 'utf8')
          }
        ]
      };
    }

    if (uri.startsWith('bone://contracts/')) {
      const contractName = uri.replace('bone://contracts/', '');
      const contractPath = path.join(baseDir, 'docs', 'contracts', `${contractName}.md`);
      if (!fs.existsSync(contractPath)) {
        throw new Error(`Contract '${contractName}' not found`);
      }
      return {
        contents: [
          {
            uri,
            mimeType: 'text/markdown',
            text: fs.readFileSync(contractPath, 'utf8')
          }
        ]
      };
    }

    throw new Error(`Unknown resource URI: ${uri}`);
  }

  sendResult(id, result) {
    const response = {
      jsonrpc: '2.0',
      id,
      result
    };
    process.stdout.write(JSON.stringify(response) + '\n');
  }

  sendError(id, code, message) {
    const response = {
      jsonrpc: '2.0',
      id,
      error: {
        code,
        message
      }
    };
    process.stdout.write(JSON.stringify(response) + '\n');
  }
}
