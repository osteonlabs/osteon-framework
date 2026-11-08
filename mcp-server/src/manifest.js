import fs from 'node:fs';
import path from 'node:path';

/**
 * Locate MANIFEST.yaml in project path or parent directories.
 * @param {string} startDir
 * @returns {string|null}
 */
export function findManifestPath(startDir = process.cwd()) {
  let curr = path.resolve(startDir);
  while (true) {
    const candidate = path.join(curr, 'MANIFEST.yaml');
    if (fs.existsSync(candidate)) {
      return candidate;
    }
    const tmplCandidate = path.join(curr, 'MANIFEST.yaml.tmpl');
    if (fs.existsSync(tmplCandidate)) {
      return tmplCandidate;
    }
    const parent = path.dirname(curr);
    if (parent === curr) break;
    curr = parent;
  }
  return null;
}

/**
 * Cleanly strips comments and trailing whitespace.
 * @param {string} line
 * @returns {string}
 */
function cleanLine(line) {
  // Strip comments outside quotes
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === "'" && !inDouble) inSingle = !inSingle;
    else if (ch === '"' && !inSingle) inDouble = !inDouble;
    else if (ch === '#' && !inSingle && !inDouble) {
      return line.slice(0, i).trimEnd();
    }
  }
  return line.trimEnd();
}

/**
 * Lightweight, zero-dependency YAML parser tailored for BONE manifests.
 * @param {string} text
 * @returns {Record<string, any>}
 */
export function parseManifestYaml(text) {
  const lines = text.split(/\r?\n/);
  const root = {};
  const stack = [{ indent: -1, obj: root, isList: false }];

  for (let rawLine of lines) {
    const line = cleanLine(rawLine);
    if (!line.trim()) continue;

    const indent = line.search(/\S/);
    const content = line.trim();

    while (stack.length > 1 && indent <= stack[stack.length - 1].indent) {
      stack.pop();
    }

    const currentContext = stack[stack.length - 1];

    if (content.startsWith('- ')) {
      const itemContent = content.slice(2).trim();
      if (!Array.isArray(currentContext.obj)) {
        // If currentContext expected a list
        continue;
      }

      if (itemContent.includes(':')) {
        const colonIdx = itemContent.indexOf(':');
        const k = itemContent.slice(0, colonIdx).trim();
        const v = itemContent.slice(colonIdx + 1).trim();
        const newObj = { [k]: parseValue(v) };
        currentContext.obj.push(newObj);
        stack.push({ indent, obj: newObj, isList: false });
      } else {
        currentContext.obj.push(parseValue(itemContent));
      }
      continue;
    }

    const colonIdx = content.indexOf(':');
    if (colonIdx !== -1) {
      const key = content.slice(0, colonIdx).trim();
      const valStr = content.slice(colonIdx + 1).trim();

      if (valStr === '') {
        // Look ahead to check if next line is a list item or nested object
        const newObj = {};
        if (typeof currentContext.obj === 'object' && !Array.isArray(currentContext.obj)) {
          currentContext.obj[key] = newObj;
        }
        stack.push({ indent, obj: newObj, key, isList: false });
      } else if (valStr.startsWith('[') && valStr.endsWith(']')) {
        // Inline array e.g. [a, b, c]
        const items = valStr.slice(1, -1).split(',').map(s => parseValue(s.trim())).filter(s => s !== '');
        currentContext.obj[key] = items;
      } else {
        currentContext.obj[key] = parseValue(valStr);
      }
    }
  }

  // Post-process any empty object whose children were pushed as numeric keys into arrays
  return normalizeParsedManifest(root);
}

function parseValue(val) {
  if (val === '' || val === '~' || val === 'null') return null;
  if (val === 'true' || val === 'yes') return true;
  if (val === 'false' || val === 'no') return false;
  if (/^-?\d+$/.test(val)) return parseInt(val, 10);
  if (/^-?\d+\.\d+$/.test(val)) return parseFloat(val);
  if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
    return val.slice(1, -1);
  }
  return val;
}

function normalizeParsedManifest(obj) {
  if (!obj || typeof obj !== 'object') return obj;

  // Convert objects with only numeric keys or structured lists
  for (const [k, v] of Object.entries(obj)) {
    if (v && typeof v === 'object') {
      normalizeParsedManifest(v);
    }
  }

  // Ensure standard defaults
  if (!obj.decay) obj.decay = { ceiling: 0.15, floor: 0.05 };
  if (!obj.curation) obj.curation = { cdi_threshold: 0.10, mode: 'interactive' };
  if (!obj.tenant) {
    obj.tenant = {
      id: 'tenant-default',
      organization: 'Default Organization',
      isolation_tier: 'strict',
      pii_masking: true
    };
  }
  return obj;
}

/**
 * Loads and parses the project MANIFEST.yaml.
 * @param {string} projectDir
 * @returns {{ path: string, manifest: Record<string, any> }}
 */
export function loadManifest(projectDir) {
  const manifestPath = findManifestPath(projectDir);
  if (!manifestPath) {
    throw new Error(`MANIFEST.yaml not found in ${projectDir} or any ancestor directory`);
  }
  const content = fs.readFileSync(manifestPath, 'utf8');
  const manifest = parseManifestYaml(content);
  return { path: manifestPath, manifest };
}
