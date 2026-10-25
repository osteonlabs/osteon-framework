# Two key conventions, one skill

Looked up when `tracker.system_of_record` is read. `SKILL.md` points here from its References and
from the section of the same name, which its keys table cites.

A BONE project keys its work units one of two ways; the manifest declares which. **Both are equally supported and this skill MUST NOT prefer one.**

| | `tracker.system_of_record: forge` | `tracker.system_of_record: external` |
|---|---|---|
| Work-unit key | the forge's own issue identifier | the external tracker's key |
| Branch and commit subject | `branching.branch_pattern` / `commits.subject_pattern` rendered with the key | identical templates, external key |
| Trailer | usually redundant; the forge links natively | REQUIRED; the forge cannot link it |
| Closing | `close_keyword` in the body closes the issue on merge | the tracker transitions separately; the body MUST NOT claim to close it |

**MUST: exactly one system is the system of record.** Where both a forge issue and an external key exist, the manifest names which one branches and commits are keyed to; the other MAY appear once in the body as a cross-reference. Two keys in one subject is a drift hazard.

**MUST NOT infer the convention from commit history**, which is evidence of past practice including past mistakes. A `tracker.system_of_record` of `UNDECIDED` is an undecided delivery model: stop, say so, route it to `bone-adr`. Working around a missing decision silently makes one.
