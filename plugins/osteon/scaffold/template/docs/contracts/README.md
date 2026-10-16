# Contract registry (L3)

One versioned contract per module seam in {{PROJECT}}. A **seam** is any boundary where two
independently changeable units exchange data: two services, a service and a client, a service and a
job runner, a service and a third party, a service and a shared database table.

If two units talk and there is no row below, the seam is undocumented and the next change to it is a
silent break.

## Registry

The first five columns are fixed, in this order: `Seam | Contract file | Version | Sides | Status`.
Additional columns MAY be appended to the right and never inserted between these.

| Seam | Contract file | Version | Sides | Status | Transport |
|---|---|---|---|---|---|
| <A to B> | [<seam>.md](<seam>.md) | 0.1.0 | `<alias>:<module>` and `<alias>:<module>` | draft | HTTP / queue / shared DB / file |

## Rules

1. **One file per seam, semantically versioned.** MAJOR is a breaking wire change, MINOR is
   additive, PATCH is wording only. The version and the changelog live **inside** the contract file;
   the row above is a copy for navigation and the file wins on any disagreement.
2. **A contract changes in the same wave as the wire.** The contract edit and the code that changes
   the wire ship in the same merge request wave. Never after, never "we will document it later". A
   contract that lags its wire is worse than no contract, because it is believed.
3. **Both sides build against the contract, not against each other's source.** Reading the other
   service's code to learn the shape of a message re-couples the two units and defeats the seam.
4. **Exact strings are normative.** Endpoints, headers, field names, enum values, units, timezones,
   encodings, auth scheme, error codes, and fail-open versus fail-closed behaviour. "Returns an
   error" is not a contract; "returns 409 with `{code: "already_on_loan"}` and the client MUST NOT
   retry" is.
5. **Units and nullability are always stated.** A number with no unit and a field with no
   nullability are the two most common causes of a working integration that produces wrong data.
6. **Data-handling rules ride every contract.** State what may and may never appear on that wire
   (personal data, credentials, tokens, regulated content), so the seam carries its own policy.
7. **A new seam is a new row and a new file BEFORE the code lands.** The registry is the admission
   gate for integration work, not its documentation.
8. **Undocumented seams are recorded as such.** A seam discovered in the code that has no contract
   gets a row and a file with `status: undocumented-today` immediately, describing the wire as it is
   observed. An honest gap is a work item; an invisible gap is an outage.
9. **Every contract carries YAML front matter** per the template: `seam`, `version`, `sides`,
   `status`, `transport`, `fail_mode`, `owner`, `decided_by`. A `[src: contract/<seam>@X.Y.Z]` token
   resolves against that `version`, so a contract without it cannot be cited.

## Status vocabulary

`draft` (written, not yet implemented by both sides) | `active` (both sides conform) |
`undocumented-today` (the seam exists in code, the contract does not yet describe it fully) |
`deprecated` (replaced, still carrying traffic, with the successor named) | `withdrawn` (no traffic;
kept for history).

## Decay

`docs/contracts/` is a watched source (`MANIFEST.yaml: watched`).
Any change here raises the Context Decay Index until a curation pass reconciles the skills that cite
these contracts. This is deliberate: a seam contract is often the most mature artifact in a knowledge
base, and without this entry it would be one that no decay signal watches.

**Template:** [CONTRACT-TEMPLATE.md](CONTRACT-TEMPLATE.md)
