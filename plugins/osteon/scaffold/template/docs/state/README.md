# Live state (L2)

What is true about {{PROJECT}} **today**, one file per topic, every fact dated and carrying the method
by which it was verified.

`docs/adr/` records why a choice was made and is append-only. `docs/state/` records what the system
actually is and is **replaced** on re-verification. They are separated because they decay at
completely different rates: a decision from a year ago is usually still valid, a fact about running
infrastructure from a year ago usually is not.

## The rule that makes this layer work

**A fact with no verification date is not a fact.** It is an inherited belief that nobody has looked
at. Both are written the same way and only the date tells them apart, which is precisely why the date
is mandatory.

## File format

One file per topic: `docs/state/<topic>.md`, with required front matter.

```yaml
---
topic: <kebab-slug, matches the filename>
verified_at: <YYYY-MM-DD>          # when the whole file was last re-verified
verified_by: <owner id>
method: <the exact command, console path, or query used>   # reproducible by someone else
scope: <what this file covers and, explicitly, what it does not>
supersedes: <the verified_at this replaces, or `none`>
---
```

Body: tables or bulleted facts. Any fact verified on a different date than the file header carries its
own `(verified YYYY-MM-DD)` marker; a fact with no marker inherits the header date.

**Template:** [STATE-TEMPLATE.md](STATE-TEMPLATE.md)

## Rules

1. **MUST replace, MUST NOT append.** Re-verification rewrites the file. The previous version lives in
   git history. A file that accretes corrections teaches by accretion: readers pay tokens for facts
   that are no longer true, and a grep-first reader lands on the stale line, never on the correction.
2. **MUST re-verify, MUST NOT transcribe.** Updating a state record means running the check again, not
   copying the previous answer forward with a new date. A transcribed date is a lie with a timestamp.
3. **MUST record the method.** Another person MUST be able to reproduce the verification from the
   `method` field alone. "Checked the console" is not a method; the exact console path or command is.
4. **MUST update in the same turn as the change.** If an agent or a person changes the world, the
   state record is updated before the session ends, not at the next audit.
5. **MUST NOT exceed 500 lines.** A state file that outgrows this is at least two topics; split it.
   A live-state record left to grow past it tends to acquire its own maintenance protocol and its
   own retraction history, and one filed inside a skill sits where no decay signal can see it.
6. **MUST NOT contain secrets.** Reference credentials by store and name. State records are committed
   like everything else; if a record cannot be committed, it is not knowledge-repo material.
7. **SHOULD state the negative.** "There is no X" is a fact worth recording, and it is the fact most
   often assumed rather than checked.

## Suggested topics

Create only what someone actually needs. Each file needs a stated owner in
`MANIFEST.yaml: docs_registry` if it introduces a new subdirectory.

- `deployment.md` - what runs where, deployed from which branch, by which pipeline.
- `data-stores.md` - databases, queues, buckets, and who reads or writes each.
- `integrations.md` - third parties, what each is used for, auth method by name.
- `repos.md` - branch reality, unmerged work, dormancy, the last commit per repository.
- `debt.md` - known broken things, skipped tests, soft-mode enforcement, and their conditions.

## Decay

`docs/state/` is a watched provenance source. These files rot fastest, so they contribute the most to
the Context Decay Index. A high CDI concentrated in `docs/state/` means the world moved; a high CDI
concentrated in `docs/adr/` means decisions landed and the skills have not caught up.
