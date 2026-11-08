import fs from 'node:fs';
import path from 'node:path';
import { findManifestPath, loadManifest } from './manifest.js';

/**
 * Appends a telemetry event to .osteon/telemetry/events.jsonl.
 * @param {string} projectDir
 * @param {Record<string, any>} event
 */
export function recordTelemetryEvent(projectDir = process.cwd(), event = {}) {
  try {
    const manifestPath = findManifestPath(projectDir);
    const baseDir = manifestPath ? path.dirname(manifestPath) : path.resolve(projectDir);
    const logDir = path.join(baseDir, '.osteon', 'telemetry');
    const logFile = path.join(logDir, 'events.jsonl');

    fs.mkdirSync(logDir, { recursive: true });

    const payload = {
      timestamp: new Date().toISOString(),
      ...event
    };

    fs.appendFileSync(logFile, JSON.stringify(payload) + '\n', 'utf8');
  } catch (err) {
    // Non-fatal: telemetry logging should never crash the server
  }
}

/**
 * Reads and aggregates telemetry statistics from .osteon/telemetry/events.jsonl.
 * @param {string} projectDir
 * @param {string|null} tenantFilter
 * @returns {Record<string, any>}
 */
export function getTelemetrySummary(projectDir = process.cwd(), tenantFilter = null) {
  const manifestPath = findManifestPath(projectDir);
  const baseDir = manifestPath ? path.dirname(manifestPath) : path.resolve(projectDir);
  const logFile = path.join(baseDir, '.osteon', 'telemetry', 'events.jsonl');

  if (!fs.existsSync(logFile)) {
    return {
      total_events: 0,
      total_tokens_metered: 0,
      average_latency_ms: 0,
      tool_invocations: {},
      status_distribution: {},
      events: []
    };
  }

  const content = fs.readFileSync(logFile, 'utf8');
  const lines = content.split(/\r?\n/).filter(Boolean);

  let totalTokens = 0;
  let totalLatency = 0;
  const toolInvocations = {};
  const statusDistribution = {};
  const recentEvents = [];

  for (const line of lines) {
    try {
      const evt = JSON.parse(line);
      if (tenantFilter && evt.tenant_id && evt.tenant_id !== tenantFilter) {
        continue;
      }

      if (evt.tokens_estimated) totalTokens += Number(evt.tokens_estimated);
      if (evt.latency_ms) totalLatency += Number(evt.latency_ms);

      if (evt.tool) {
        toolInvocations[evt.tool] = (toolInvocations[evt.tool] || 0) + 1;
      }
      if (evt.status) {
        statusDistribution[evt.status] = (statusDistribution[evt.status] || 0) + 1;
      }

      recentEvents.push(evt);
    } catch (_) {}
  }

  const count = recentEvents.length;
  const avgLatency = count > 0 ? Number((totalLatency / count).toFixed(2)) : 0;

  return {
    total_events: count,
    total_tokens_metered: totalTokens,
    average_latency_ms: avgLatency,
    tool_invocations: toolInvocations,
    status_distribution: statusDistribution,
    recent_events: recentEvents.slice(-10)
  };
}
