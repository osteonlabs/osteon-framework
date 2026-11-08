import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { findManifestPath, loadManifest } from './manifest.js';

/**
 * Computes sha256 hex digest of a file.
 * @param {string} filePath
 * @returns {string|null}
 */
export function hashFileSha256(filePath) {
  if (!fs.existsSync(filePath)) return null;
  const content = fs.readFileSync(filePath);
  return crypto.createHash('sha256').update(content).digest('hex');
}

/**
 * Read the baseline TSV file (format: "<digest>\t<source-id>").
 * @param {string} baselinePath
 * @returns {Map<string, string>} Map from sourceId to expectedDigest
 */
export function readBaseline(baselinePath) {
  const map = new Map();
  if (!fs.existsSync(baselinePath)) return map;

  const content = fs.readFileSync(baselinePath, 'utf8');
  for (const line of content.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const parts = trimmed.split('\t');
    if (parts.length >= 2) {
      map.set(parts[1].trim(), parts[0].trim());
    }
  }
  return map;
}

/**
 * Extract candidate blocks from markdown content according to BONE rules.
 * @param {string} markdown
 * @param {string} relativeFilePath
 * @returns {Array<{ blockIndex: number, text: string, tokens: string[], isCandidate: boolean }>}
 */
export function extractMarkdownBlocks(markdown, relativeFilePath) {
  const blocks = [];
  const lines = markdown.split(/\r?\n/);
  let currentBlockLines = [];
  let blockIndex = 0;
  let inFrontMatter = false;
  let inFence = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Frontmatter block 0
    if (i === 0 && line.trim() === '---') {
      inFrontMatter = true;
      currentBlockLines.push(line);
      continue;
    }
    if (inFrontMatter) {
      currentBlockLines.push(line);
      if (line.trim() === '---') {
        inFrontMatter = false;
        blocks.push(createBlockRecord(blockIndex++, currentBlockLines.join('\n'), relativeFilePath));
        currentBlockLines = [];
      }
      continue;
    }

    if (line.trim().startsWith('```')) {
      inFence = !inFence;
      currentBlockLines.push(line);
      if (!inFence) {
        // End of fence
        blocks.push(createBlockRecord(blockIndex++, currentBlockLines.join('\n'), relativeFilePath));
        currentBlockLines = [];
      }
      continue;
    }

    if (inFence) {
      currentBlockLines.push(line);
      continue;
    }

    // Blank line indicates paragraph boundary
    if (line.trim() === '') {
      if (currentBlockLines.length > 0) {
        blocks.push(createBlockRecord(blockIndex++, currentBlockLines.join('\n'), relativeFilePath));
        currentBlockLines = [];
      }
      continue;
    }

    // Headings
    if (line.trim().startsWith('#')) {
      if (currentBlockLines.length > 0) {
        blocks.push(createBlockRecord(blockIndex++, currentBlockLines.join('\n'), relativeFilePath));
        currentBlockLines = [];
      }
      blocks.push(createBlockRecord(blockIndex++, line, relativeFilePath, false));
      continue;
    }

    // List item or table row or text
    currentBlockLines.push(line);
  }

  if (currentBlockLines.length > 0) {
    blocks.push(createBlockRecord(blockIndex++, currentBlockLines.join('\n'), relativeFilePath));
  }

  return blocks;
}

function createBlockRecord(blockIndex, text, relativeFilePath, forceCandidate = null) {
  const tokenRegex = /\[src:\s*([^\]]+)\]/g;
  const tokens = [];
  let match;
  while ((match = tokenRegex.exec(text)) !== null) {
    tokens.push(match[1].trim());
  }

  const cleanText = text.replace(/```[\s\S]*?```/g, '').trim();
  const hasDeclarative = cleanText.length > 20 && /[a-zA-Z0-9]/.test(cleanText);
  const isCandidate = forceCandidate !== null ? forceCandidate : (blockIndex > 0 && hasDeclarative);

  return {
    blockIndex,
    file: relativeFilePath,
    text,
    tokens,
    isCandidate
  };
}

/**
 * Executes cdi.sh hook if available, otherwise runs internal mathematical engine.
 * @param {string} projectDir
 * @returns {Promise<Record<string, any>>}
 */
export async function getCdiMetrics(projectDir = process.cwd()) {
  const manifestPath = findManifestPath(projectDir);
  const baseDir = manifestPath ? path.dirname(manifestPath) : path.resolve(projectDir);

  const cdiHookPaths = [
    path.join(baseDir, '.claude', 'hooks', 'cdi.sh'),
    path.join(baseDir, 'plugins', 'osteon', 'scaffold', 'template', '.claude', 'hooks', 'cdi.sh'),
    path.join(baseDir, 'bin', 'cdi.sh')
  ];

  for (const hookPath of cdiHookPaths) {
    if (fs.existsSync(hookPath)) {
      try {
        const output = execFileSync('sh', [hookPath, '--json'], {
          cwd: baseDir,
          encoding: 'utf8',
          timeout: 10000
        });
        const parsed = JSON.parse(output.trim());
        return {
          source: 'cdi.sh',
          ...parsed
        };
      } catch (err) {
        // Fall back to native Node.js calculation
      }
    }
  }

  return computeNativeCdi(baseDir);
}

/**
 * Pure Node.js implementation of CDI calculation.
 * @param {string} baseDir
 * @returns {Record<string, any>}
 */
export function computeNativeCdi(baseDir) {
  const baselinePath = path.join(baseDir, 'metrics', 'curation-baseline.tsv');
  if (!fs.existsSync(baselinePath)) {
    return {
      state: 'uninitialised',
      cdi: null,
      coverage: null,
      units_total: 0,
      units_anchored: 0,
      units_decayed: 0,
      sources_changed: 0,
      sources_unavailable: 0,
      message: 'No curation-baseline.tsv found. Run osteon_reanchor or cdi.sh --seal.'
    };
  }

  const baseline = readBaseline(baselinePath);
  const changedSources = new Set();
  const unavailableSources = new Set();

  for (const [sourceId, baselineHash] of baseline.entries()) {
    let sourceFilePath = null;
    if (sourceId.startsWith('adr/')) {
      sourceFilePath = path.join(baseDir, 'docs', 'adr', `${sourceId.replace('adr/', '')}.md`);
    } else if (sourceId.startsWith('contracts/')) {
      sourceFilePath = path.join(baseDir, 'docs', 'contracts', `${sourceId.replace('contracts/', '')}.md`);
    } else {
      sourceFilePath = path.join(baseDir, sourceId);
    }

    if (!fs.existsSync(sourceFilePath)) {
      if (sourceId.includes(':')) {
        unavailableSources.add(sourceId);
      } else {
        changedSources.add(sourceId); // Deleted
      }
    } else {
      const currentHash = hashFileSha256(sourceFilePath);
      if (currentHash !== baselineHash) {
        changedSources.add(sourceId); // Modified
      }
    }
  }

  // Find candidate knowledge files (.claude/skills/**/*.md)
  const skillsDir = path.join(baseDir, '.claude', 'skills');
  const candidateFiles = [];
  if (fs.existsSync(skillsDir)) {
    const scanDir = (dir) => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) scanDir(full);
        else if (entry.isFile() && entry.name.endsWith('.md')) candidateFiles.push(full);
      }
    };
    scanDir(skillsDir);
  }

  let unitsTotal = 0;
  let unitsAnchored = 0;
  let unitsDecayed = 0;
  const decayedBlocks = [];

  for (const filePath of candidateFiles) {
    const rel = path.relative(baseDir, filePath).replace(/\\/g, '/');
    const content = fs.readFileSync(filePath, 'utf8');
    const blocks = extractMarkdownBlocks(content, rel);

    for (const block of blocks) {
      if (!block.isCandidate) continue;
      unitsTotal++;

      if (block.tokens.length > 0) {
        unitsAnchored++;
        const decayedBy = block.tokens.filter(t => changedSources.has(t));
        if (decayedBy.length > 0) {
          unitsDecayed++;
          decayedBlocks.push({
            file: block.file,
            blockIndex: block.blockIndex,
            decayedBy
          });
        }
      }
    }
  }

  const cdi = unitsAnchored > 0 ? Number((unitsDecayed / unitsAnchored).toFixed(4)) : null;
  const coverage = unitsTotal > 0 ? Number((unitsAnchored / unitsTotal).toFixed(4)) : null;
  const orphanRate = unitsTotal > 0 ? Number(((unitsTotal - unitsAnchored) / unitsTotal).toFixed(4)) : null;

  let state = 'clean';
  if (cdi !== null) {
    if (cdi > 0.10) state = 'breach';
    else if (cdi > 0) state = 'warning';
  }

  return {
    state,
    cdi,
    coverage,
    orphan_rate: orphanRate,
    units_total: unitsTotal,
    units_anchored: unitsAnchored,
    units_decayed: unitsDecayed,
    sources_changed: changedSources.size,
    sources_unavailable: unavailableSources.size,
    changed_sources: Array.from(changedSources),
    decayed_blocks: decayedBlocks
  };
}
