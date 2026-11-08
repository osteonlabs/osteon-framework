import fs from 'node:fs';
import path from 'node:path';
import { findManifestPath, loadManifest } from './manifest.js';
import { extractMarkdownBlocks } from './cdi.js';

/**
 * Searches authoritative facts across BONE files.
 * @param {string} projectDir
 * @param {string} query
 * @param {string|null} tierFilter
 * @returns {Array<{ source: string, tier: string, blockIndex: number, text: string, provenance: string[] }>}
 */
export function queryAuthoritativeFacts(projectDir = process.cwd(), query = '', tierFilter = null) {
  const manifestPath = findManifestPath(projectDir);
  const baseDir = manifestPath ? path.dirname(manifestPath) : path.resolve(projectDir);

  const results = [];
  const queryLower = query.toLowerCase();

  // Search paths: docs/adr/, docs/contracts/, docs/state/, .claude/skills/
  const searchDirs = [
    { dir: path.join(baseDir, 'docs', 'adr'), defaultTier: 'T2' },
    { dir: path.join(baseDir, 'docs', 'contracts'), defaultTier: 'T1' },
    { dir: path.join(baseDir, 'docs', 'state'), defaultTier: 'T2' },
    { dir: path.join(baseDir, '.claude', 'skills'), defaultTier: 'T2' }
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
        if (b.text.toLowerCase().includes(queryLower)) {
          results.push({
            file: relPath,
            tier,
            blockIndex: b.blockIndex,
            provenance: b.tokens,
            text: b.text.trim()
          });
        }
      }
    }
  }

  return results;
}
