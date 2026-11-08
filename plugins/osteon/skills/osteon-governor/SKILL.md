---
name: osteon-governor
description: Context governance agent for Google Antigravity and autonomous AaaS runtimes. Enforces non-negotiable BONE invariants, runs pre-flight CDI decay checks before planning or coding, validates seam contracts, checks accepted ADR conformance, and ensures atomic same-wave documentation updates. Use whenever planning architectural changes, implementing cross-service features, or when an agent begins an engineering session in an OSTEON repository.
---

# OSTEON Governor — Context & Invariant Controller

The runtime context controller for autonomous AI coding agents in OSTEON-governed repositories.
It prevents agent hallucinations, context rot, unanchored assumptions, and silent seam contract drift
by injecting mathematical pre-flight checks and strict governance boundaries into the agent's workflow.

> **Governance is proactive, not retrospective.** A broken assumption or stale contract caught
> during planning costs nothing; caught after deployment, it invalidates the entire agent work wave.

---

## The 5 Core Invariants

Every agent executing tasks in an OSTEON repository **MUST** adhere to these 5 non-negotiable invariants:

### 1. Pre-Flight Context Decay Verification
Before proposing an architectural plan or editing code:
- Run `osteon_get_cdi` (via MCP or `.claude/hooks/cdi.sh`).
- If $\text{CDI} = 0.0000$ (`state: clean`): Proceed with planning.
- If $\text{CDI} \le 0.10$ (`state: warning`): Note affected drifted sources in your plan and avoid basing new logic on decayed units.
- If $\text{CDI} > 0.10$ (`state: breach`): Pause feature expansion. Execute `bone-curator` or triage decayed anchors before writing code.

### 2. Single-Owner Knowledge & Authoritative Sources
- **Do NOT duplicate knowledge:** Facts live in exactly one authoritative location ($T0 \dots T3$).
- Technical invariants and wire interfaces live in **Seam Contracts** (`docs/contracts/`).
- Architectural decisions live in **Architectural Decision Records** (`docs/adr/`).
- Lower tiers reference higher tiers via aliases and paths; they never copy content.

### 3. Binding ADR Conformance
- Accepted ADRs in `docs/adr/` are constitutional software laws.
- An agent **MUST NOT** implement a pattern, library, or architecture explicitly rejected in an accepted ADR.
- If business or technical requirements necessitate superseding an ADR, the agent must propose an amendment or new ADR *first*, never silently violate it in code.

### 4. Same-Wave Contract Synchronization
- Whenever code changes touch a network wire, API endpoint, message payload, database schema, or exported interface crossing a declared seam:
  - The corresponding seam contract in `docs/contracts/` **MUST be updated in the exact same commit wave**.
  - A commit that changes interface code without updating the seam contract is a **structural defect**.

### 5. Mandatory Provenance Attestation
- Any declarative knowledge unit or guideline written in `.claude/skills/` or documentation **MUST carry a resolvable provenance token**:
  ```markdown
  All outgoing requests must include the X-Tenant-ID header [src: docs/contracts/gateway-seam.md].
  ```
- Unanchored claims ($P3$) violate repository hygiene and increase the orphan rate.

---

## Agent Lifecycle Integration

```mermaid
flowchart TD
    Start["Agent Task Started"] --> CheckCDI["Run Pre-Flight CDI Check (osteon_get_cdi)"]
    CheckCDI --> EvalCDI{"CDI State?"}
    EvalCDI -->|Clean (0.0000)| Plan["Formulate Execution Plan"]
    EvalCDI -->|Warning (<= 0.10)| Warn["Log Drift Warning & Plan Safely"]
    EvalCDI -->|Breach (> 0.10)| Halt["Trigger bone-curator / Quarantine"]
    Warn --> Plan
    Halt --> Plan
    Plan --> CheckADR["Verify Plan Against Accepted ADRs"]
    CheckADR --> Code["Execute Code Changes"]
    Code --> CheckSeam{"Touched Seam Interface?"}
    CheckSeam -->|Yes| UpdateContract["Update docs/contracts/ in Same Wave"]
    CheckSeam -->|No| Attest["Verify Provenance Tokens [src: ...]"]
    UpdateContract --> Attest
    Attest --> Verify["Run Test Suite & Linters"]
    Verify --> Commit["Commit Clean Wave with Conventional Message"]
```

---

## Available MCP & CLI Commands

- **Check Drift Index:**
  - MCP: `osteon_get_cdi`
  - CLI: `sh .claude/hooks/cdi.sh --summary`
- **Query Authoritative Facts:**
  - MCP: `osteon_query_fact(query: "billing")`
- **Verify Contract Compliance:**
  - MCP: `osteon_verify_contract(contract_name: "payment-seam")`
- **Inspect Manifest:**
  - MCP: `osteon_inspect_manifest`
