---
seam: <kebab-slug, matches the filename>
version: 0.1.0              # semver. MAJOR breaking wire change, MINOR additive, PATCH wording.
sides: ["<alias>:<module or package>", "<alias>:<module or package>"]
status: draft               # draft | active | undocumented-today | deprecated | withdrawn
transport: "<HTTP/1.1 JSON | queue | shared table | file drop>"
fail_mode: closed           # open | closed. What A does when B is unreachable.
owner: <owner id from MANIFEST.yaml owners[]>
decided_by: null            # or a provenance ref, for example "adr/0007"
---

# Contract: <side A> to <side B> - <transport>

<!--
Copy to docs/contracts/<seam-slug>.md and add a row to docs/contracts/README.md in the same change.
The front matter above is the machine-readable record: `version` is what a `[src: contract/<seam>@X.Y.Z]`
token resolves against, so a contract with no front-matter version cannot be cited at all.
Angle-bracket fields are filled in by the author. Delete every comment before committing.
-->

## Endpoint and auth

| Property | Value |
|---|---|
| Transport | <HTTPS / queue / shared table / file drop> |
| Address | `<exact URL, queue name, or table name>` |
| Auth scheme | `<header or mechanism>`, credential referenced by name only |
| Credential location | `<secret store>: <name>` (never the value) |
| Timeout | `<n>s` |
| Retry policy | <who retries, how many times, with what backoff, and what is idempotent> |
| Rate limit | <limit and what happens when it is exceeded> |

## A to B messages

### `<message or endpoint name>`

| Field | Type | Unit | Nullable | Notes |
|---|---|---|---|---|
| `<field>` | string | n/a | no | <exact constraint> |
| `<field>` | integer | milliseconds | yes | <what null means> |

Example (normative, not illustrative):

```json
{ "<field>": "<value>" }
```

## B to A messages

<!-- Same shape. Include every response, including the error responses. -->

### Success

| Field | Type | Unit | Nullable | Notes |
|---|---|---|---|---|

### Errors

| Status | Body | Meaning | Client MUST |
|---|---|---|---|
| 4xx | `{ "code": "<code>" }` | <what happened> | <retry / do not retry / re-auth> |

## Failure semantics

State each explicitly. A seam without these is undefined under exactly the conditions that matter.

- **Fail-open or fail-closed:** when B is unreachable, A MUST <...>.
- **Timeout behaviour:** <...>
- **Partial success:** <whether it can occur and what the caller observes>
- **Ordering guarantees:** <ordered / unordered / per-key>
- **Delivery guarantees:** <at-most-once / at-least-once / exactly-once> and therefore whether the
  consumer MUST be idempotent.
- **Reconnect or replay:** <...>
- **Version skew:** what B does when A sends an older MAJOR, and vice versa.

## Data handling

- MUST NOT appear on this wire: <credentials, personal data, regulated content, raw tokens>.
- Retention: <how long either side may store what crosses this seam>.
- Logging: <which fields MUST be redacted in logs on both sides>.

## Verification

How a change to this contract is checked before merge. Name the test, the consumer-side check, or the
gate id from `MANIFEST.yaml: gates`. A contract with no verification is documentation, not a contract.

## Changelog

| Version | Date | Change | Breaking |
|---|---|---|---|
| 0.1.0 | <YYYY-MM-DD> | Initial contract. | n/a |
