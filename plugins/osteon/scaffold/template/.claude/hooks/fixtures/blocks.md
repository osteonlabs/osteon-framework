---
name: block-fixture
description: front matter carries a token [src: adr/0001] that anchors nothing
---

# A heading is never a block

The loan period is fourteen days for every new member [src: adr/0002].

Run the audit and seal the baseline afterwards.

This paragraph introduces the fenced block below it and is one block with it.

```sh
cdi.sh --seal   # [src: docs/state/example.md]
```

- A top-level list item that carries a real claim about the system [src: adr/0001].
  a continuation line indented under that same item.
- A second top-level item with no token at all but plenty of declarative words here.
  - A nested sub item is its own block and carries its own claim [src: repo/lending-api:CLAUDE.md].

| Seam | Contract | Status |
|---|---|---|
| loans | docs/contracts/loans.md | live [src: adr/0002] |
| reservations | none | undocumented today, which is a claim about the world |

Short.

The dependency pin file is cited here and its name ends in the letter t
[src: repo/lending-api:requirements/base.txt].
