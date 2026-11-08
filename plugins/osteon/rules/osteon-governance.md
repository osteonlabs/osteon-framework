# OSTEON Autonomous Governance Rules for AI Agents

> Applied to: Google Antigravity, Claude Code, Cursor, and Autonomous AaaS Workers.

## 1. Zero Hallucinated Assumptions
- Never assume an interface, configuration parameter, or data shape without reading its authoritative definition.
- Query facts via `osteon_query_fact` or by inspecting the canonical files declared in `MANIFEST.yaml`.

## 2. Pre-Flight CDI Gate
- Before modifying files or producing complex plans, inspect repository context decay:
  - If `state: clean` (CDI = 0.0000), proceed.
  - If `state: warning` (0 < CDI <= 0.10), verify whether your planned changes depend on the drifted sources.
  - If `state: breach` (CDI > 0.10), notify the human operator or invoke `bone-curator`.

## 3. Same-Wave Contract Synchronization
- Any change to wire protocols, APIs, schemas, or RPC signatures requires co-updating the corresponding contract in `docs/contracts/` in the same commit.

## 4. Single-Owner Knowledge Rule
- Every architectural decision lives in `docs/adr/`.
- Every wire contract lives in `docs/contracts/`.
- Every current operational fact lives in `docs/state/`.
- Never duplicate; always reference by alias or relative path.

## 5. Mandatory Provenance Anchoring
- Every declarative claim or instruction written to `.claude/skills/` or markdown context files MUST carry a resolvable `[src: <path-or-alias>]` token.
