import fs from 'node:fs';
import path from 'node:path';
import { findManifestPath } from './manifest.js';

/**
 * List all seam contracts available in the BONE repository.
 * @param {string} projectDir
 * @returns {Array<{ name: string, path: string, version: string, tier: string }>}
 */
export function listContracts(projectDir = process.cwd()) {
  const manifestPath = findManifestPath(projectDir);
  const baseDir = manifestPath ? path.dirname(manifestPath) : path.resolve(projectDir);
  const contractsDir = path.join(baseDir, 'docs', 'contracts');

  if (!fs.existsSync(contractsDir)) return [];

  const results = [];
  const entries = fs.readdirSync(contractsDir, { withFileTypes: true });

  for (const entry of entries) {
    if (entry.isFile() && entry.name.endsWith('.md')) {
      const fullPath = path.join(contractsDir, entry.name);
      const content = fs.readFileSync(fullPath, 'utf8');

      const name = entry.name.replace(/\.md$/, '');
      const versionMatch = /version:\s*([^\r\n]+)/.exec(content);
      const tierMatch = /tier:\s*(T[0-3])/i.exec(content);

      results.push({
        name,
        path: path.relative(baseDir, fullPath).replace(/\\/g, '/'),
        version: versionMatch ? versionMatch[1].trim() : 'unknown',
        tier: tierMatch ? tierMatch[1].toUpperCase() : 'T1'
      });
    }
  }

  return results;
}

/**
 * Verifies a payload or code interface against a named seam contract.
 * @param {string} projectDir
 * @param {string} contractName
 * @param {any} [payload]
 * @returns {{ valid: boolean, contract: string, errors: string[], invariants: string[] }}
 */
export function verifyContract(projectDir = process.cwd(), contractName, payload = null) {
  const manifestPath = findManifestPath(projectDir);
  const baseDir = manifestPath ? path.dirname(manifestPath) : path.resolve(projectDir);
  const targetFile = path.join(baseDir, 'docs', 'contracts', `${contractName}.md`);

  if (!fs.existsSync(targetFile)) {
    return {
      valid: false,
      contract: contractName,
      errors: [`Contract '${contractName}' not found in docs/contracts/`],
      invariants: []
    };
  }

  const content = fs.readFileSync(targetFile, 'utf8');
  const errors = [];
  const invariants = [];

  // Extract Invariants or Rules section
  const lines = content.split(/\r?\n/);
  let inInvariants = false;

  for (const line of lines) {
    if (line.match(/^##+\s*(Invariants|Schema|Rules|Guarantees)/i)) {
      inInvariants = true;
      continue;
    }
    if (inInvariants && line.match(/^##+\s/)) {
      inInvariants = false;
      continue;
    }
    if (inInvariants && line.trim().startsWith('- ')) {
      invariants.push(line.trim().slice(2));
    }
  }

  // If payload provided as JSON object, perform basic property checks
  if (payload && typeof payload === 'object') {
    // Check if contract specifies required fields (e.g. `REQUIRED. string`)
    const requiredFieldRegex = /`([a-zA-Z0-9_.-]+)`\s*:\s*REQUIRED/gi;
    let match;
    while ((match = requiredFieldRegex.exec(content)) !== null) {
      const field = match[1];
      if (!(field in payload) && payload[field] === undefined) {
        errors.push(`Missing mandatory payload field: '${field}'`);
      }
    }
  }

  return {
    valid: errors.length === 0,
    contract: contractName,
    errors,
    invariants
  };
}
