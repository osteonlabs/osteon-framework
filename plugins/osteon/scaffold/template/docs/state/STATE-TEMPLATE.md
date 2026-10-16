---
topic: <kebab-slug, matches the filename>
verified_at: <YYYY-MM-DD>
verified_by: <owner id from MANIFEST.yaml>
method: <the exact command, console path or query; another person MUST be able to repeat it>
scope: <what this file covers, and explicitly what it does not>
supersedes: <the verified_at of the version this replaces, or `none`>
---

# <Topic> - live state

<!--
Copy to docs/state/<topic>.md. This file is REPLACED on re-verification, never appended to.
Angle-bracket fields are filled in by the author. Delete every comment before committing.
-->

**As of <YYYY-MM-DD>.** Facts below carry the header date unless they carry their own
`(verified YYYY-MM-DD)` marker. A fact with no marker and no header date does not belong here.

## <Section>

| Item | Value | Verified | Source |
|---|---|---|---|
| <what> | <exact value, no secrets> | <YYYY-MM-DD> | `<command, console path, or file:line>` |

## What is NOT true

Explicit negatives, because these are the facts most often assumed instead of checked.

- There is no <X>. Checked by `<method>` on <YYYY-MM-DD>.

## Unverified

Things believed but not confirmed in this pass. Anything listed here MUST NOT be relied on by a
skill, a contract, or an agent action.

- <claim> - inherited from <where>, not re-checked. Cost to verify: <how>.

## Method

The full procedure used for this verification, verbatim, so the next pass repeats it rather than
inventing a new one.

```sh
# <commands>
```
