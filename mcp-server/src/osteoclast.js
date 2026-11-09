import fs from 'node:fs';
import path from 'node:path';
import { listContracts } from './contracts.js';
import { extractMarkdownBlocks } from './cdi.js';
import { queryAuthoritativeFacts } from './facts.js';
import { findManifestPath, loadManifest } from './manifest.js';

/**
 * Extracts governed surfaces / file patterns from a seam contract file.
 * @param {string} contractContent
 * @param {string} contractName
 * @returns {string[]}
 */
export function extractGovernedSurfaces(contractContent, contractName) {
  const surfaces = [];

  // 1. Check YAML frontmatter: governs / surfaces / paths
  const frontmatterMatch = /^---\r?\n([\s\S]*?)\r?\n---/.exec(contractContent);
  if (frontmatterMatch) {
    const lines = frontmatterMatch[1].split(/\r?\n/);
    let inGoverns = false;
    for (const line of lines) {
      if (line.match(/^(governs|surfaces|paths):\s*$/i)) {
        inGoverns = true;
        continue;
      }
      if (inGoverns) {
        const itemMatch = /^\s*-\s*([^\r\n]+)/.exec(line);
        if (itemMatch) {
          surfaces.push(itemMatch[1].trim().replace(/^["']|["']$/g, ''));
        } else if (line.match(/^[a-zA-Z0-9_-]+:/)) {
          inGoverns = false;
        }
      }
    }
  }

  // 2. Check markdown body for surface lists or wire lines
  const lines = contractContent.split(/\r?\n/);
  for (const line of lines) {
    const surfaceMatch = /^\s*-\s*(?:Surface|Wire|Governs|Path):\s*`?([a-zA-Z0-9_./*-]+)`?/i.exec(line);
    if (surfaceMatch) {
      surfaces.push(surfaceMatch[1].trim());
    }
  }

  // Default fallback heuristic: contract named "auth" governs paths containing "auth"
  if (surfaces.length === 0) {
    surfaces.push(`*${contractName}*`);
  }

  return Array.from(new Set(surfaces));
}

/**
 * Checks if a relative file path matches a governed surface pattern.
 * @param {string} filePath
 * @param {string} surfacePattern
 * @returns {boolean}
 */
export function matchesSurface(filePath, surfacePattern) {
  const normFile = filePath.replace(/\\/g, '/');
  const normPattern = surfacePattern.replace(/\\/g, '/');

  if (normPattern.endsWith('**')) {
    const prefix = normPattern.slice(0, -2);
    return normFile.startsWith(prefix);
  }
  if (normPattern.endsWith('*')) {
    const prefix = normPattern.slice(0, -1);
    return normFile.startsWith(prefix);
  }
  if (normPattern.startsWith('*') && normPattern.endsWith('*')) {
    const sub = normPattern.slice(1, -1);
    return normFile.includes(sub);
  }
  return normFile === normPattern || normFile.includes(normPattern);
}

/**
 * Verifies Contract Co-Change: If wire moved, contract version must be bumped.
 * @param {string} projectDir
 * @param {string[]} changedFiles
 * @param {string} [diffText=""]
 * @returns {{ passed: boolean, violations: string[] }}
 */
export function verifyContractCoChange(projectDir, changedFiles, diffText = '') {
  const contracts = listContracts(projectDir);
  const violations = [];
  const baseDir = path.resolve(projectDir);

  const normChangedFiles = changedFiles.map(f => f.replace(/\\/g, '/'));

  for (const c of contracts) {
    const fullContractPath = path.join(baseDir, c.path);
    if (!fs.existsSync(fullContractPath)) continue;

    const content = fs.readFileSync(fullContractPath, 'utf8');
    const governedSurfaces = extractGovernedSurfaces(content, c.name);

    // Check which changed files affect this contract's wire surfaces
    const affectedFiles = normChangedFiles.filter(f => {
      if (f === c.path) return false; // The contract itself
      return governedSurfaces.some(s => matchesSurface(f, s));
    });

    if (affectedFiles.length > 0) {
      const contractWasChanged = normChangedFiles.includes(c.path);
      if (!contractWasChanged) {
        violations.push(
          `Contract co-change missing: Wire moved in [${affectedFiles.join(', ')}] affecting seam contract '${c.name}', but contract file '${c.path}' was not updated.`
        );
      } else if (diffText) {
        // If contract was changed, verify version line was modified in diff
        const hasVersionBump = new RegExp(`[+]\\s*version:\\s*([0-9.]+)`, 'i').test(diffText);
        if (!hasVersionBump && !diffText.includes(`docs/contracts/${c.name}.md`)) {
          // Warning or violation if diff provided but version was not modified
          violations.push(
            `Contract version bump missing: Contract '${c.name}' was modified but version string was not incremented.`
          );
        }
      }
    }
  }

  return {
    passed: violations.length === 0,
    violations
  };
}

/**
 * Verifies Single-Owner Fact Integrity: No duplicate fact claims in downstream files.
 * @param {string} projectDir
 * @param {string[]} changedFiles
 * @param {Array<{ file: string, text: string }>} [customContents=[]]
 * @returns {{ passed: boolean, violations: string[] }}
 */
export function verifySingleOwnerIntegrity(projectDir, changedFiles, customContents = []) {
  const violations = [];
  const baseDir = path.resolve(projectDir);

  for (const filePath of changedFiles) {
    const normPath = filePath.replace(/\\/g, '/');
    if (!normPath.endsWith('.md')) continue;

    let content = '';
    const custom = customContents.find(c => c.file.replace(/\\/g, '/') === normPath);
    if (custom) {
      content = custom.text;
    } else {
      const fullPath = path.join(baseDir, filePath);
      if (fs.existsSync(fullPath)) {
        content = fs.readFileSync(fullPath, 'utf8');
      }
    }

    if (!content) continue;

    // Check each block against authoritative facts
    const blocks = extractMarkdownBlocks(content, normPath);
    for (const b of blocks) {
      if (!b.text || b.text.length < 40) continue;
      if (b.text.startsWith('---') || b.text.trim().startsWith('#') || b.text.trim().startsWith('|')) continue;

      const blockWords = b.text.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(/\s+/).filter(w => w.length > 3);
      if (blockWords.length < 5) continue;
      const blockTokens = new Set(blockWords);

      const query = blockWords.slice(0, 10).join(' ');
      const existingFacts = queryAuthoritativeFacts(projectDir, query, null, 10);

      for (const ef of existingFacts) {
        if (ef.file === normPath) continue;

        const efWords = ef.text.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(/\s+/).filter(w => w.length > 3);
        const efTokens = new Set(efWords);
        let uniqueOverlap = 0;
        for (const w of blockTokens) {
          if (efTokens.has(w)) uniqueOverlap++;
        }

        const overlapRatio = uniqueOverlap / blockTokens.size;
        if (overlapRatio >= 0.75 && uniqueOverlap >= 6) {
          const hasCitation = b.tokens.some(t => t.includes(ef.file)) || b.text.includes(ef.file);
          if (!hasCitation) {
            violations.push(
              `Single-owner fact collision in '${normPath}': Block duplicates authoritative fact from '${ef.file}' without explicit [src: ${ef.file}] citation or supersede attestation.`
            );
            break;
          }
        }
      }
    }
  }

  return {
    passed: violations.length === 0,
    violations
  };
}

/**
 * Verifies Attestation Provenance Chain Completeness for new knowledge blocks.
 * @param {string} projectDir
 * @param {string[]} changedFiles
 * @param {Array<{ file: string, text: string }>} [customContents=[]]
 * @returns {{ passed: boolean, violations: string[] }}
 */
export function verifyAttestationChain(projectDir, changedFiles, customContents = []) {
  const violations = [];
  const baseDir = path.resolve(projectDir);

  for (const filePath of changedFiles) {
    const normPath = filePath.replace(/\\/g, '/');

    // Focus on governed BONE knowledge units (skills, contracts, adrs)
    const isGovernedDoc =
      normPath.startsWith('plugins/osteon/skills/') ||
      normPath.startsWith('.claude/skills/') ||
      normPath.startsWith('docs/contracts/') ||
      normPath.startsWith('docs/state/');

    if (!isGovernedDoc || !normPath.endsWith('.md')) continue;

    let content = '';
    const custom = customContents.find(c => c.file.replace(/\\/g, '/') === normPath);
    if (custom) {
      content = custom.text;
    } else {
      const fullPath = path.join(baseDir, filePath);
      if (fs.existsSync(fullPath)) {
        content = fs.readFileSync(fullPath, 'utf8');
      }
    }

    if (!content) continue;

    const blocks = extractMarkdownBlocks(content, normPath);
    for (const b of blocks) {
      if (!b.text || b.text.length < 30) continue;
      // Frontmatter, headings, and table formatting are document structure, not substantive knowledge assertions
      if (b.text.startsWith('---') || b.text.trim().startsWith('#') || b.text.trim().startsWith('|')) continue;

      // In T1/T2 knowledge, blocks must have at least one provenance token or explicit citation
      const hasProvenance = b.tokens && b.tokens.length > 0;
      const hasAttestationComment = /<!--\s*attestation:/i.test(b.text);
      const hasSrcCitation = /\[src:\s*[^\]]+\]/i.test(b.text);

      if (!hasProvenance && !hasAttestationComment && !hasSrcCitation) {
        violations.push(
          `Broken attestation provenance in '${normPath}' (block ${b.blockIndex}): Knowledge assertion lacks verified provenance token [src: ...] or attestation comment.`
        );
      }
    }
  }

  return {
    passed: violations.length === 0,
    violations
  };
}

/**
 * Executes a full adversarial Osteoclast pre-merge audit.
 * @param {object} params
 * @param {string} [params.projectDir]
 * @param {string[]} params.changedFiles
 * @param {string} [params.diffText=""]
 * @param {string} [params.prTitle="Change Request"]
 * @param {string} [params.commitSha="HEAD"]
 * @param {Array<{ file: string, text: string }>} [params.customContents=[]]
 * @returns {{
 *   allowedToMerge: boolean,
 *   verdict: 'APPROVED' | 'REFUTED',
 *   refutations: string[],
 *   checks: {
 *     contractCoChange: { passed: boolean, violations: string[] },
 *     singleOwnerIntegrity: { passed: boolean, violations: string[] },
 *     attestationChain: { passed: boolean, violations: string[] }
 *   },
 *   comment: string
 * }}
 */
export function auditChangeRequest({
  projectDir = process.cwd(),
  changedFiles = [],
  diffText = '',
  prTitle = 'Change Request',
  commitSha = 'HEAD',
  customContents = []
}) {
  const contractCheck = verifyContractCoChange(projectDir, changedFiles, diffText);
  const integrityCheck = verifySingleOwnerIntegrity(projectDir, changedFiles, customContents);
  const attestationCheck = verifyAttestationChain(projectDir, changedFiles, customContents);

  const refutations = [
    ...contractCheck.violations,
    ...integrityCheck.violations,
    ...attestationCheck.violations
  ];

  const allowedToMerge = refutations.length === 0;
  const verdict = allowedToMerge ? 'APPROVED' : 'REFUTED';

  let comment = `## 🦴 OSTEON Osteoclast Pre-Merge Quality Audit\n\n`;
  comment += `**Verdict:** ${allowedToMerge ? '✅ **APPROVED**' : '❌ **REFUTED**'}\n`;
  comment += `**Target:** ${prTitle} (\`${commitSha.slice(0, 8)}\`)\n\n`;

  comment += `### 🔬 Adversarial Refutation Checks\n`;
  comment += `- ${contractCheck.passed ? '✅' : '❌'} **Contract Co-Change:** ${contractCheck.passed ? 'All modified wire surfaces have corresponding contract updates.' : `${contractCheck.violations.length} violation(s) detected.`}\n`;
  comment += `- ${integrityCheck.passed ? '✅' : '❌'} **Single-Owner Fact Integrity:** ${integrityCheck.passed ? 'No duplicate or shadow fact claims found.' : `${integrityCheck.violations.length} duplication collision(s) detected.`}\n`;
  comment += `- ${attestationCheck.passed ? '✅' : '❌'} **Attestation Provenance:** ${attestationCheck.passed ? 'All knowledge assertions carry verified provenance chains.' : `${attestationCheck.violations.length} unanchored assertion(s) detected.`}\n\n`;

  if (!allowedToMerge) {
    comment += `### ⚠️ Refutation Details & Required Remediation\n`;
    for (const r of refutations) {
      comment += `- 🚫 ${r}\n`;
    }
    comment += `\n> *Osteoclast Principle:* "An agent that reports its own work marks it done. The Osteoclast refutes fresh claims to prevent phantom progress and broken contracts."\n`;
  } else {
    comment += `> *Audit Passed:* Fusion lease granted for merge.\n`;
  }

  return {
    allowedToMerge,
    verdict,
    refutations,
    checks: {
      contractCoChange: contractCheck,
      singleOwnerIntegrity: integrityCheck,
      attestationChain: attestationCheck
    },
    comment
  };
}
