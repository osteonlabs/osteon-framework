import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { findManifestPath } from './manifest.js';

export const VALID_ROLES = [
  'Chondrocyte',
  'Osteocyte',
  'Osteoblast',
  'Osteoclast',
  'Periosteum'
];

export const VALID_CHECKPOINTS = [
  'start_cr',
  'shared_surface',
  'open_cr',
  'fusion',
  'curation_item'
];

/**
 * Resolves the canaliculi state storage directory for a project.
 * @param {string} projectDir
 * @returns {string}
 */
export function getCanaliculiDir(projectDir = process.cwd()) {
  const manifestPath = findManifestPath(projectDir);
  const baseDir = manifestPath ? path.dirname(manifestPath) : path.resolve(projectDir);
  const canaliculiDir = path.join(baseDir, '.osteon', 'canaliculi');
  if (!fs.existsSync(canaliculiDir)) {
    fs.mkdirSync(canaliculiDir, { recursive: true });
  }
  return canaliculiDir;
}

/**
 * Atomically writes JSON data to a destination file.
 * @param {string} filePath
 * @param {any} data
 */
function atomicWriteJson(filePath, data) {
  const tmpPath = `${filePath}.${crypto.randomBytes(4).toString('hex')}.tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2), 'utf8');
  fs.renameSync(tmpPath, filePath);
}

/**
 * Loads the current registry from disk.
 * @param {string} canaliculiDir
 * @returns {{ sessions: Record<string, any>, leases: Record<string, any> }}
 */
function loadRegistry(canaliculiDir) {
  const registryFile = path.join(canaliculiDir, 'registry.json');
  if (!fs.existsSync(registryFile)) {
    return { sessions: {}, leases: {} };
  }
  try {
    const raw = fs.readFileSync(registryFile, 'utf8');
    return JSON.parse(raw);
  } catch (_) {
    return { sessions: {}, leases: {} };
  }
}

/**
 * Saves registry state to disk.
 * @param {string} canaliculiDir
 * @param {{ sessions: Record<string, any>, leases: Record<string, any> }} registry
 */
function saveRegistry(canaliculiDir, registry) {
  const registryFile = path.join(canaliculiDir, 'registry.json');
  atomicWriteJson(registryFile, registry);
}

/**
 * Appends an entry to the append-only ledger.
 * @param {string} canaliculiDir
 * @param {any} entry
 */
function appendLedger(canaliculiDir, entry) {
  const ledgerFile = path.join(canaliculiDir, 'ledger.jsonl');
  const record = JSON.stringify({
    timestamp: new Date().toISOString(),
    ...entry
  }) + '\n';
  fs.appendFileSync(ledgerFile, record, 'utf8');
}

/**
 * Purges expired leases from registry.
 * @param {any} registry
 * @returns {boolean} Whether any lease was removed
 */
function purgeExpiredLeases(registry) {
  const now = Date.now();
  let modified = false;
  for (const [leaseId, lease] of Object.entries(registry.leases || {})) {
    if (lease.expiresAt && lease.expiresAt <= now) {
      delete registry.leases[leaseId];
      modified = true;
    }
  }
  return modified;
}

/**
 * Registers an agent session into the Canaliculi registry.
 * @param {string} projectDir
 * @param {string} sessionId
 * @param {string} role
 * @param {string} [worktree=""]
 * @param {Record<string, any>} [metadata={}]
 * @returns {{ success: boolean, session: any, error?: string }}
 */
export function registerSession(projectDir, sessionId, role, worktree = '', metadata = {}) {
  if (!sessionId || typeof sessionId !== 'string') {
    return { success: false, error: 'sessionId must be a non-empty string' };
  }
  if (!VALID_ROLES.includes(role)) {
    return {
      success: false,
      error: `Invalid role '${role}'. Valid roles are: ${VALID_ROLES.join(', ')}`
    };
  }

  const dir = getCanaliculiDir(projectDir);
  const registry = loadRegistry(dir);
  purgeExpiredLeases(registry);

  const existing = registry.sessions[sessionId];
  const now = Date.now();

  const sessionRecord = {
    id: sessionId,
    role,
    worktree: worktree || process.cwd(),
    status: 'active',
    registeredAt: existing ? existing.registeredAt : now,
    lastHeartbeat: now,
    metadata: { ...metadata }
  };

  registry.sessions[sessionId] = sessionRecord;
  saveRegistry(dir, registry);

  appendLedger(dir, {
    event: 'session_registered',
    sessionId,
    role,
    worktree: sessionRecord.worktree
  });

  return { success: true, session: sessionRecord };
}

/**
 * Retires an active session, releasing all leases it currently holds.
 * @param {string} projectDir
 * @param {string} sessionId
 * @param {string} [reason="task_completed"]
 * @returns {{ success: boolean, releasedLeases: string[], error?: string }}
 */
export function retireSession(projectDir, sessionId, reason = 'task_completed') {
  const dir = getCanaliculiDir(projectDir);
  const registry = loadRegistry(dir);

  const session = registry.sessions[sessionId];
  if (!session) {
    return { success: false, releasedLeases: [], error: `Session '${sessionId}' not found` };
  }

  session.status = 'retired';
  session.retiredAt = Date.now();
  session.retireReason = reason;

  const releasedLeases = [];
  for (const [leaseId, lease] of Object.entries(registry.leases || {})) {
    if (lease.sessionId === sessionId) {
      delete registry.leases[leaseId];
      releasedLeases.push(leaseId);
      appendLedger(dir, {
        event: 'lease_released_on_retire',
        sessionId,
        leaseId,
        surface: lease.surface
      });
    }
  }

  saveRegistry(dir, registry);

  appendLedger(dir, {
    event: 'session_retired',
    sessionId,
    reason,
    releasedLeases
  });

  return { success: true, releasedLeases };
}

/**
 * Requests or renews a distributed signal lease on a shared surface or checkpoint.
 * @param {string} projectDir
 * @param {string} sessionId
 * @param {string} surface
 * @param {string} [checkpoint="shared_surface"]
 * @param {number} [ttlMs=300000] 5 minutes default
 * @returns {{ granted: boolean, lease?: any, reason?: string }}
 */
export function acquireLease(projectDir, sessionId, surface, checkpoint = 'shared_surface', ttlMs = 300000) {
  if (!surface) {
    return { granted: false, reason: 'surface identifier is required' };
  }
  if (!VALID_CHECKPOINTS.includes(checkpoint)) {
    return {
      granted: false,
      reason: `Invalid checkpoint '${checkpoint}'. Valid checkpoints: ${VALID_CHECKPOINTS.join(', ')}`
    };
  }

  const dir = getCanaliculiDir(projectDir);
  const registry = loadRegistry(dir);
  purgeExpiredLeases(registry);

  const session = registry.sessions[sessionId];
  if (!session || session.status === 'retired') {
    return {
      granted: false,
      reason: `Session '${sessionId}' is not registered or active. Register with osteon_canaliculi_register first.`
    };
  }

  const now = Date.now();

  // Check if surface is already leased by another active session
  for (const [existingId, lease] of Object.entries(registry.leases || {})) {
    if (lease.surface === surface && lease.expiresAt > now) {
      if (lease.sessionId === sessionId) {
        // Idempotent renewal for same session
        lease.expiresAt = now + ttlMs;
        saveRegistry(dir, registry);
        appendLedger(dir, {
          event: 'lease_renewed',
          sessionId,
          leaseId: existingId,
          surface,
          expiresAt: lease.expiresAt
        });
        return { granted: true, lease };
      } else {
        appendLedger(dir, {
          event: 'lease_denied',
          sessionId,
          surface,
          heldBy: lease.sessionId,
          expiresAt: lease.expiresAt
        });
        return {
          granted: false,
          reason: `Surface '${surface}' is locked by active session '${lease.sessionId}' until ${new Date(lease.expiresAt).toISOString()}`
        };
      }
    }
  }

  // Grant new lease
  const leaseId = `lease-${crypto.randomBytes(6).toString('hex')}`;
  const lease = {
    leaseId,
    sessionId,
    role: session.role,
    surface,
    checkpoint,
    grantedAt: now,
    expiresAt: now + ttlMs
  };

  registry.leases[leaseId] = lease;
  saveRegistry(dir, registry);

  appendLedger(dir, {
    event: 'lease_granted',
    sessionId,
    leaseId,
    surface,
    checkpoint,
    expiresAt: lease.expiresAt
  });

  return { granted: true, lease };
}

/**
 * Releases a held signal lease.
 * @param {string} projectDir
 * @param {string} sessionId
 * @param {string} leaseId
 * @returns {{ released: boolean, reason?: string }}
 */
export function releaseLease(projectDir, sessionId, leaseId) {
  const dir = getCanaliculiDir(projectDir);
  const registry = loadRegistry(dir);

  const lease = registry.leases[leaseId];
  if (!lease) {
    return { released: false, reason: `Lease '${leaseId}' not found or already expired` };
  }

  if (lease.sessionId !== sessionId) {
    return {
      released: false,
      reason: `Lease '${leaseId}' belongs to session '${lease.sessionId}', not '${sessionId}'`
    };
  }

  delete registry.leases[leaseId];
  saveRegistry(dir, registry);

  appendLedger(dir, {
    event: 'lease_released',
    sessionId,
    leaseId,
    surface: lease.surface
  });

  return { released: true };
}

/**
 * Sends a Canaliculi session-to-session signal or broadcast.
 * @param {string} projectDir
 * @param {string} fromSessionId
 * @param {string} toSessionId 'broadcast' or specific sessionId
 * @param {string} topic
 * @param {any} payload
 * @returns {{ success: boolean, signalId?: string, error?: string }}
 */
export function sendSignal(projectDir, fromSessionId, toSessionId, topic, payload = {}) {
  if (!fromSessionId || !toSessionId || !topic) {
    return { success: false, error: 'fromSessionId, toSessionId, and topic are required' };
  }

  const dir = getCanaliculiDir(projectDir);
  const registry = loadRegistry(dir);

  const sender = registry.sessions[fromSessionId];
  if (!sender || sender.status === 'retired') {
    return { success: false, error: `Sender session '${fromSessionId}' is not active` };
  }

  const signalId = `sig-${crypto.randomBytes(6).toString('hex')}`;
  const signal = {
    signalId,
    from: fromSessionId,
    fromRole: sender.role,
    to: toSessionId,
    topic,
    payload,
    timestamp: new Date().toISOString(),
    status: 'delivered'
  };

  const signalsFile = path.join(dir, 'signals.jsonl');
  fs.appendFileSync(signalsFile, JSON.stringify(signal) + '\n', 'utf8');

  appendLedger(dir, {
    event: 'signal_sent',
    signalId,
    from: fromSessionId,
    to: toSessionId,
    topic
  });

  return { success: true, signalId, signal };
}

/**
 * Polls or reads signals directed to a specific session or broadcast.
 * @param {string} projectDir
 * @param {string} sessionId
 * @param {string|null} [topicFilter=null]
 * @param {number} [limit=20]
 * @returns {Array<any>}
 */
export function getSignals(projectDir, sessionId, topicFilter = null, limit = 20) {
  const dir = getCanaliculiDir(projectDir);
  const signalsFile = path.join(dir, 'signals.jsonl');
  if (!fs.existsSync(signalsFile)) {
    return [];
  }

  const raw = fs.readFileSync(signalsFile, 'utf8');
  const lines = raw.split('\n').filter(l => l.trim().length > 0);
  const matched = [];

  for (let i = lines.length - 1; i >= 0; i--) {
    try {
      const sig = JSON.parse(lines[i]);
      if (sig.to === sessionId || sig.to === 'broadcast' || sig.from === sessionId) {
        if (!topicFilter || sig.topic === topicFilter) {
          matched.push(sig);
          if (matched.length >= limit) break;
        }
      }
    } catch (_) {}
  }

  return matched;
}

/**
 * Retrieves the full ossification status, active centers, leases, and recent events.
 * @param {string} projectDir
 * @returns {{ active_sessions: any[], active_leases: any[], recent_events: any[] }}
 */
export function getOssificationStatus(projectDir = process.cwd()) {
  const dir = getCanaliculiDir(projectDir);
  const registry = loadRegistry(dir);
  purgeExpiredLeases(registry);

  const activeSessions = Object.values(registry.sessions || {}).filter(s => s.status === 'active');
  const activeLeases = Object.values(registry.leases || {});

  const ledgerFile = path.join(dir, 'ledger.jsonl');
  const recentEvents = [];
  if (fs.existsSync(ledgerFile)) {
    const raw = fs.readFileSync(ledgerFile, 'utf8');
    const lines = raw.split('\n').filter(l => l.trim().length > 0);
    for (let i = Math.max(0, lines.length - 15); i < lines.length; i++) {
      try {
        recentEvents.push(JSON.parse(lines[i]));
      } catch (_) {}
    }
  }

  return {
    growth_plates_locked: activeLeases.length > 0,
    active_sessions: activeSessions,
    active_leases: activeLeases,
    recent_events: recentEvents
  };
}
