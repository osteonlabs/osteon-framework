#!/usr/bin/env node

import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');
const serverBin = path.join(rootDir, 'mcp-server', 'bin', 'osteon-mcp.js');

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    console.log(`ok   ${message}`);
    passed++;
  } else {
    console.error(`FAIL ${message}`);
    failed++;
  }
}

async function runMcpTests() {
  console.log('------------------------------------------------------------------------');
  console.log('Running Suite: Model Context Protocol (MCP) Server Interoperability');
  console.log('------------------------------------------------------------------------');

  const serverProc = spawn('node', [serverBin, rootDir], {
    stdio: ['pipe', 'pipe', 'pipe']
  });

  serverProc.stderr.on('data', (d) => {
    // console.error(`[server-stderr] ${d.toString().trim()}`);
  });

  let messageQueue = [];
  let pendingResolvers = [];
  let buffer = '';

  serverProc.stdout.on('data', (chunk) => {
    buffer += chunk.toString();
    const lines = buffer.split('\n');
    buffer = lines.pop(); // Keep trailing incomplete line

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try {
        const msg = JSON.parse(trimmed);
        if (pendingResolvers.length > 0) {
          const resolve = pendingResolvers.shift();
          resolve(msg);
        } else {
          messageQueue.push(msg);
        }
      } catch (e) {
        console.error('Malformed JSON from MCP server:', trimmed);
      }
    }
  });

  function sendRpc(req) {
    return new Promise((resolve) => {
      pendingResolvers.push(resolve);
      serverProc.stdin.write(JSON.stringify(req) + '\n');
    });
  }

  try {
    // 1. Initialize
    const initRes = await sendRpc({
      jsonrpc: '2.0',
      id: 1,
      method: 'initialize',
      params: {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'osteon-test-runner', version: '1.0.0' }
      }
    });

    assert(initRes.id === 1, 'MCP response matches request id 1');
    assert(initRes.result.protocolVersion === '2024-11-05', 'MCP protocolVersion is 2024-11-05');
    assert(initRes.result.serverInfo.name === '@osteon/mcp-server', 'serverInfo.name is @osteon/mcp-server');
    assert(initRes.result.serverInfo.version === '0.1.2', 'serverInfo.version matches 0.1.2');
    assert(typeof initRes.result.capabilities.tools === 'object', 'tools capability declared');

    // 2. Client initialized notification
    serverProc.stdin.write(JSON.stringify({
      jsonrpc: '2.0',
      method: 'notifications/initialized'
    }) + '\n');

    // 3. Tools list
    const toolsRes = await sendRpc({
      jsonrpc: '2.0',
      id: 2,
      method: 'tools/list',
      params: {}
    });

    const toolNames = toolsRes.result.tools.map((t) => t.name);
    assert(toolNames.includes('osteon_get_cdi'), 'Tool osteon_get_cdi is exposed');
    assert(toolNames.includes('osteon_query_fact'), 'Tool osteon_query_fact is exposed');
    assert(toolNames.includes('osteon_verify_contract'), 'Tool osteon_verify_contract is exposed');
    assert(toolNames.includes('osteon_inspect_manifest'), 'Tool osteon_inspect_manifest is exposed');
    assert(toolNames.includes('osteon_reanchor'), 'Tool osteon_reanchor is exposed');

    // 4. Prompts list
    const promptsRes = await sendRpc({
      jsonrpc: '2.0',
      id: 3,
      method: 'prompts/list',
      params: {}
    });

    const promptNames = promptsRes.result.prompts.map((p) => p.name);
    assert(promptNames.includes('bone_pre_execution_gate'), 'Prompt bone_pre_execution_gate is exposed');
    assert(promptNames.includes('bone_curation_triage'), 'Prompt bone_curation_triage is exposed');

    // 5. Prompts get
    const promptGetRes = await sendRpc({
      jsonrpc: '2.0',
      id: 4,
      method: 'prompts/get',
      params: {
        name: 'bone_pre_execution_gate',
        arguments: { task_description: 'Implement auth token caching' }
      }
    });

    assert(promptGetRes.result.messages.length > 0, 'Prompt returns structured messages');
    const promptText = promptGetRes.result.messages[0].content.text;
    assert(promptText.includes('OSTEON BONE PRE-EXECUTION GATE ACTIVE'), 'Prompt contains pre-execution header');
    assert(promptText.includes('Implement auth token caching'), 'Prompt incorporates task arguments');

    // 6. Resources list
    const resourcesRes = await sendRpc({
      jsonrpc: '2.0',
      id: 5,
      method: 'resources/list',
      params: {}
    });

    const uris = resourcesRes.result.resources.map((r) => r.uri);
    assert(uris.includes('bone://manifest'), 'Resource bone://manifest is registered');
    assert(uris.includes('bone://metrics/baseline'), 'Resource bone://metrics/baseline is registered');

    // 7. Tool call: osteon_verify_contract
    const verifyRes = await sendRpc({
      jsonrpc: '2.0',
      id: 6,
      method: 'tools/call',
      params: {
        name: 'osteon_verify_contract',
        arguments: {
          contract_name: 'non-existent-contract',
          project_path: rootDir
        }
      }
    });

    const parsedVerify = JSON.parse(verifyRes.result.content[0].text);
    assert(parsedVerify.valid === false, 'Contract verification catches missing contract');
    assert(parsedVerify.errors.length > 0, 'Verification returns descriptive error message');

    // 8. Tool call: osteon_get_cdi
    const cdiRes = await sendRpc({
      jsonrpc: '2.0',
      id: 7,
      method: 'tools/call',
      params: {
        name: 'osteon_get_cdi',
        arguments: {
          project_path: rootDir
        }
      }
    });

    const parsedCdi = JSON.parse(cdiRes.result.content[0].text);
    assert('state' in parsedCdi, 'CDI tool returns state property');
    assert('units_anchored' in parsedCdi, 'CDI tool returns units_anchored property');

  } finally {
    serverProc.kill();
  }

  console.log(`\n${passed} passed, ${failed} failed`);
  if (failed === 0) {
    console.log('[+] SUITE PASSED: Model Context Protocol (MCP) Server Interoperability\n');
  } else {
    console.log('[-] SUITE FAILED: Model Context Protocol (MCP) Server Interoperability\n');
    process.exit(1);
  }
}

runMcpTests().catch((err) => {
  console.error('Test execution error:', err);
  process.exit(1);
});
