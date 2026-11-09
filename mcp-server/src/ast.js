import crypto from 'node:crypto';
import path from 'node:path';

/**
 * Normalizes content by stripping comments, trailing whitespace, and collapsing runs of spaces.
 * @param {string} content
 * @param {string} ext
 * @returns {string}
 */
export function normalizeCodeContent(content, ext = '') {
  let text = content.replace(/\r\n/g, '\n');

  if (ext === '.py') {
    // Strip Python comments and multiline docstrings
    text = text.replace(/"""[\s\S]*?"""/g, '');
    text = text.replace(/'''[\s\S]*?'''/g, '');
    text = text.replace(/#.*$/gm, '');
  } else if (['.js', '.ts', '.jsx', '.tsx', '.go', '.java', '.c', '.cpp', '.rs'].includes(ext)) {
    // Strip C-style comments
    text = text.replace(/\/\*[\s\S]*?\*\//g, '');
    text = text.replace(/\/\/.*$/gm, '');
  } else if (['.yaml', '.yml', '.sh', '.bash'].includes(ext)) {
    // Strip hash comments
    text = text.replace(/#.*$/gm, '');
  } else if (ext === '.md') {
    // Strip HTML comments
    text = text.replace(/<!--[\s\S]*?-->/g, '');
  }

  // Collapse whitespace, remove blank lines, trim each line
  return text
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)
    .join('\n');
}

/**
 * Extracts exported AST signatures and class/function declarations.
 * @param {string} content
 * @param {string} ext
 * @returns {string[]} Sorted array of structural signatures
 */
export function extractAstSignatures(content, ext = '') {
  const signatures = [];
  const lines = content.replace(/\r\n/g, '\n').split('\n');

  if (['.js', '.ts', '.jsx', '.tsx'].includes(ext)) {
    for (const rawLine of lines) {
      const line = rawLine.trim();
      // Match export functions, classes, interfaces, types, consts
      if (/^export\s+(async\s+)?function\s+([a-zA-Z0-9_$]+)\s*\([^)]*\)/.test(line)) {
        const sig = line.replace(/\{.*$/, '').trim();
        signatures.push(`func:${sig.replace(/^export\s+(async\s+)?function\s+/, '')}`);
      } else if (/^export\s+class\s+([a-zA-Z0-9_$]+)/.test(line)) {
        const m = line.match(/^export\s+class\s+([a-zA-Z0-9_$]+)/);
        signatures.push(`class:${m[1]}`);
      } else if (/^export\s+interface\s+([a-zA-Z0-9_$]+)/.test(line)) {
        const m = line.match(/^export\s+interface\s+([a-zA-Z0-9_$]+)/);
        signatures.push(`interface:${m[1]}`);
      } else if (/^export\s+type\s+([a-zA-Z0-9_$]+)/.test(line)) {
        const m = line.match(/^export\s+type\s+([a-zA-Z0-9_$]+)/);
        signatures.push(`type:${m[1]}`);
      } else if (/^export\s+(const|let|var)\s+([a-zA-Z0-9_$]+)/.test(line)) {
        const m = line.match(/^export\s+(const|let|var)\s+([a-zA-Z0-9_$]+)/);
        signatures.push(`var:${m[2]}`);
      }
    }
  } else if (ext === '.py') {
    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (/^def\s+([a-zA-Z0-9_]+)\s*\(([^)]*)\)/.test(line)) {
        const sig = line.replace(/:.*$/, '').trim();
        signatures.push(`def:${sig.replace(/^def\s+/, '')}`);
      } else if (/^class\s+([a-zA-Z0-9_]+)/.test(line)) {
        const m = line.match(/^class\s+([a-zA-Z0-9_]+)/);
        signatures.push(`class:${m[1]}`);
      }
    }
  } else if (ext === '.go') {
    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (/^func\s+(\([^)]+\)\s+)?([A-Z][a-zA-Z0-9_]*)\s*\([^)]*\)/.test(line)) {
        const sig = line.replace(/\{.*$/, '').trim();
        signatures.push(`func:${sig.replace(/^func\s+/, '')}`);
      } else if (/^type\s+([A-Z][a-zA-Z0-9_]*)\s+(struct|interface)/.test(line)) {
        const m = line.match(/^type\s+([A-Z][a-zA-Z0-9_]*)\s+(struct|interface)/);
        signatures.push(`type:${m[1]}:${m[2]}`);
      }
    }
  }

  // If no language-specific AST symbols were detected, fallback to normalized lines
  if (signatures.length === 0) {
    const normalized = normalizeCodeContent(content, ext);
    return normalized ? [normalized] : [];
  }

  return signatures.sort();
}

/**
 * Computes hash based on the selected verification strategy.
 * @param {string} content
 * @param {string} filePath
 * @param {'cryptographic'|'normalized'|'ast-symbol'} strategy
 * @returns {string} Hex SHA-256 digest
 */
export function computeStrategicHash(content, filePath, strategy = 'cryptographic') {
  const ext = path.extname(filePath).toLowerCase();

  let targetText = content;

  if (strategy === 'normalized') {
    targetText = normalizeCodeContent(content, ext);
  } else if (strategy === 'ast-symbol') {
    const sigs = extractAstSignatures(content, ext);
    targetText = sigs.join('\n');
  }

  return crypto.createHash('sha256').update(targetText, 'utf8').digest('hex');
}

/**
 * Analyzes whether drift between original and current content is functional or non-functional.
 * @param {string} originalContent
 * @param {string} currentContent
 * @param {string} filePath
 * @returns {{ isDecayed: boolean, driftType: 'none'|'non-functional'|'functional', astChanged: boolean }}
 */
export function analyzeSemanticDrift(originalContent, currentContent, filePath) {
  const ext = path.extname(filePath).toLowerCase();

  const cryptoBefore = computeStrategicHash(originalContent, filePath, 'cryptographic');
  const cryptoAfter = computeStrategicHash(currentContent, filePath, 'cryptographic');

  if (cryptoBefore === cryptoAfter) {
    return { isDecayed: false, driftType: 'none', astChanged: false };
  }

  const astBefore = computeStrategicHash(originalContent, filePath, 'ast-symbol');
  const astAfter = computeStrategicHash(currentContent, filePath, 'ast-symbol');

  if (astBefore === astAfter) {
    return { isDecayed: true, driftType: 'non-functional', astChanged: false };
  }

  return { isDecayed: true, driftType: 'functional', astChanged: true };
}
