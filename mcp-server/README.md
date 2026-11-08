# @osteon/mcp-server

Official **Model Context Protocol (MCP)** server for the **OSTEON Context Governance Framework**.

This server exposes the BONE knowledge architecture, mathematical Context Decay Index ($\text{CDI}$), single-owner facts, seam contracts, and autonomous curation actions to any AI agent runtime over standard JSON-RPC (STDIO).

---

## 🚀 Features

- **Universal Protocol Compatibility:** Fully compliant with MCP `2024-11-05`. Zero external dependencies — runs directly on Node.js 18+.
- **Mathematical Drift Governance (`osteon_get_cdi`):** Real-time measurement of context decay, candidate coverage, and orphan rates without spawning external bash processes.
- **Authoritative Fact Lookup (`osteon_query_fact`):** Query single-owner facts by keyword, alias, or tier ($T0 \dots T3$) with provenance tokens (`[src: ...]`).
- **Seam Contract Verification (`osteon_verify_contract`):** Validate payload invariants against normative contracts declared in `docs/contracts/`.
- **Authoritative Re-anchoring (`osteon_reanchor`):** Enables autonomous AaaS agents to update knowledge anchor pins and record audit trails.
- **Pre-execution Gate Prompts:** Inject non-negotiable BONE governance invariants before agents generate code or architectural plans.

---

## 📦 Usage & Configuration

### 1. Antigravity Configuration (`mcp.json`)
Add to your Antigravity MCP settings:
```json
{
  "mcpServers": {
    "osteon": {
      "command": "node",
      "args": [
        "c:/path/to/osteon-framework/mcp-server/bin/osteon-mcp.js",
        "--dir",
        "${workspaceFolder}"
      ]
    }
  }
}
```

### 2. Claude Desktop Configuration
Add to `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "osteon": {
      "command": "node",
      "args": [
        "/path/to/osteon-framework/mcp-server/bin/osteon-mcp.js",
        "--dir",
        "/path/to/your/repo"
      ]
    }
  }
}
```

### 3. Direct CLI Execution
```bash
node ./mcp-server/bin/osteon-mcp.js /path/to/target/repo
```

---

## 🛠️ MCP Tools Reference

| Tool | Parameters | Description |
| :--- | :--- | :--- |
| `osteon_get_cdi` | `project_path?` | Computes Context Decay Index, coverage, and lists decayed blocks. |
| `osteon_query_fact` | `query`, `tier?`, `project_path?` | Searches authoritative single-owner facts with provenance. |
| `osteon_verify_contract` | `contract_name`, `payload?`, `project_path?` | Verifies interface payloads against seam contracts. |
| `osteon_inspect_manifest` | `project_path?` | Returns parsed MANIFEST.yaml structure and curation policy. |
| `osteon_reanchor` | `file_path`, `old_token`, `new_token`, `justification` | Atomically replaces token and appends to audit log. |

---

## 📚 MCP Resources

- `bone://manifest`: Content of `MANIFEST.yaml`.
- `bone://metrics/baseline`: Content of `metrics/curation-baseline.tsv`.
- `bone://contracts/{name}`: Full content of a named seam contract in `docs/contracts/`.

---

## 🛡️ License
Apache-2.0
