import fs from 'node:fs';
import path from 'node:path';
import { findManifestPath, loadManifest } from './manifest.js';
import { extractMarkdownBlocks } from './cdi.js';
import { rankDocumentsBM25 } from './search.js';

/**
 * Searches authoritative facts across BONE files with BM25 semantic relevance scoring.
 * @param {string} projectDir
 * @param {string} query
 * @param {string|null} [tierFilter=null]
 * @param {number} [limit=10]
 * @returns {Array<{ file: string, tier: string, blockIndex: number, text: string, provenance: string[], score?: number, matched_terms?: string[] }>}
 */
export function queryAuthoritativeFacts(projectDir = process.cwd(), query = '', tierFilter = null, limit = 10) {
  const manifestPath = findManifestPath(projectDir);
  const baseDir = manifestPath ? path.dirname(manifestPath) : path.resolve(projectDir);

  const candidateDocuments = [];
  const queryTrimmed = query.trim();

  // Search paths: docs/adr/, docs/contracts/, docs/state/, .claude/skills/
  const searchDirs = [
    { dir: path.join(baseDir, 'docs', 'adr'), defaultTier: 'T2' },
    { dir: path.join(baseDir, 'docs', 'contracts'), defaultTier: 'T1' },
    { dir: path.join(baseDir, 'docs', 'state'), defaultTier: 'T2' },
    { dir: path.join(baseDir, '.claude', 'skills'), defaultTier: 'T2' },
    { dir: path.join(baseDir, 'plugins', 'osteon', 'skills'), defaultTier: 'T0' }
  ];

  for (const { dir, defaultTier } of searchDirs) {
    if (!fs.existsSync(dir)) continue;

    const files = [];
    const scan = (d) => {
      for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
        const full = path.join(d, entry.name);
        if (entry.isDirectory()) scan(full);
        else if (entry.isFile() && entry.name.endsWith('.md')) files.push(full);
      }
    };
    scan(dir);

    for (const file of files) {
      const relPath = path.relative(baseDir, file).replace(/\\/g, '/');
      const content = fs.readFileSync(file, 'utf8');

      // Determine tier
      let tier = defaultTier;
      const tierMatch = /tier:\s*(T[0-3])/i.exec(content);
      if (tierMatch) {
        tier = tierMatch[1].toUpperCase();
      }

      if (tierFilter && tier !== tierFilter.toUpperCase()) {
        continue;
      }

      const blocks = extractMarkdownBlocks(content, relPath);
      for (const b of blocks) {
        if (!b.text || b.text.trim().length === 0) continue;
        candidateDocuments.push({
          file: relPath,
          tier,
          blockIndex: b.blockIndex,
          provenance: b.tokens,
          text: b.text.trim()
        });
      }
    }
  }

  // If query is present, rank with BM25
  if (queryTrimmed && queryTrimmed !== '*') {
    const ranked = rankDocumentsBM25(queryTrimmed, candidateDocuments);
    return ranked.slice(0, limit).map(r => ({
      file: r.document.file,
      tier: r.document.tier,
      blockIndex: r.document.blockIndex,
      provenance: r.document.provenance,
      text: r.document.text,
      score: r.score,
      matched_terms: r.matched_terms
    }));
  }

  // Fallback: return unranked up to limit
  return candidateDocuments.slice(0, limit);
}

/**
 * Masks potential API keys, secrets, and credentials from extracted fact texts.
 * @param {string} text
 * @returns {string}
 */
export function maskPiiAndSecrets(text) {
  if (!text) return text;
  return text
    .replace(/(bearer\s+)[a-zA-Z0-9_\-\.]{15,}/gi, '$1[MASKED_TOKEN]')
    .replace(/(sk_[a-zA-Z0-9_\-]{20,})/gi, '[MASKED_KEY]')
    .replace(/(ghp_[a-zA-Z0-9]{20,})/gi, '[MASKED_GITHUB_TOKEN]');
}
