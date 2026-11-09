---
name: osteon-ossification-osteoclast
description: Autonomous adversarial auditor for the Ossification methodology. Intercepts Change Requests and Pull Requests before merge (fusion), refuting claims that violate contract co-change, duplicate single-owner facts, or break attestation provenance chains. Use before granting a fusion lease or approving any branch merge into main.
---

# Osteoclast: Autonomous Pre-Merge Quality Auditor

In the Ossification methodology, the **Osteoclast** is the cellular agent whose biological duty is resorption of defective bone before fusion.

> **Standing Instruction:** An agent whose only instruction is to **refute** fresh claims, defaulting to refuted when uncertain. Measured: roughly one in five DONE claims do not survive refutation.

---

## 1. The Three Pre-Merge Refutation Gates

Every Change Request (CR) or Pull Request (PR) must clear all three gates before a `fusion` signal lease is granted:

| Gate | Name | Rule | Refutation Condition |
|---|---|---|---|
| **OC1** | **Contract Co-Change** | *Wire moved $\implies$ Contract version bumped.* | A modified code file matches a governed seam contract surface, but the corresponding contract in `docs/contracts/*.md` was not updated in the same change request. |
| **OC2** | **Single-Owner Fact Integrity** | *No shadow claims or duplicate authorities.* | A documentation block duplicates facts owned by existing ADRs or Seam Contracts without explicit cross-repository provenance or supersede attestation. |
| **OC3** | **Attestation Provenance Chain** | *No unanchored knowledge assertions.* | A knowledge unit or skill file adds claims lacking verified provenance tokens `[src: ...]` or attestation anchors `<!-- attestation: ... -->`. |

---

## 2. Invocation via MCP & Headless API

### Running via MCP Tool
```json
{
  "name": "osteon_osteoclast_audit",
  "arguments": {
    "changed_files": [
      "src/auth/jwt.ts",
      "docs/contracts/user-auth-contract.md"
    ],
    "pr_title": "feat(auth): add asymmetric JWT verification",
    "commit_sha": "d5e6f7a"
  }
}
```

### Running via Headless HTTP/REST
```http
POST /api/v1/osteoclast/audit
Content-Type: application/json

{
  "changed_files": ["src/api/routes.js"],
  "pr_title": "fix(api): modify route response"
}
```

---

## 3. Canaliculi Fusion Lease Enforcement

When an **Osteoblast** requests a fusion lease to merge into `main`:
1. The Osteoblast calls `osteon_canaliculi_lease` with `checkpoint: "fusion"`.
2. The Canaliculi protocol checks whether an Osteoclast audit has yielded `verdict: "APPROVED"`.
3. If unaudited or refuted, Canaliculi returns:
   `granted: false, reason: "Fusion lease blocked: Pre-merge Osteoclast quality audit required with verdict 'APPROVED' before merging into main line."`

---

## 4. Remediation Directives

When the Osteoclast issues a `REFUTED` verdict:
- **Contract Co-Change Violation:** The author must inspect the affected Seam Contract in `docs/contracts/`, align the interface definition with the code changes, increment `version:`, and commit the contract co-change.
- **Single-Owner Fact Collision:** Remove the duplicate claim and replace it with a citation to the authoritative owner: `See [src: docs/adr/001.md#L15]`.
- **Broken Attestation Chain:** Attach the exact source file and line-range locator to the block: `[src: path/to/source.ts#L10-L25]`.
