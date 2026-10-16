---
name: bone-standup
description: The operating rhythm of a BONE-governed project, kept per declared track. Use at the start of a session (brief), the end (debrief), for a weekly rollup or an on-demand status, and when asked "where were we", "what did we do today", "what is the status", or when picking a project back up after a gap. Owns the continuity journal that makes a dormant project restartable, drafts audience-aware updates, and routes blind spots to the owning role instead of guessing. NOT for deciding (bone-adr) or editing the knowledge base (bone-curator). Load the project's T1 context skill first.
---

# BONE Operating Rhythm

Turn each working session into continuity plus the communication the role owes others, without re-deriving project state from chat. Load the project's T1 context skill first, then read `rhythm` and `roles` from `MANIFEST.yaml`.

> **The journal is a knowledge artifact, not a diary.** It MUST be committed and MUST be sensitive-free by construction (people by role, systems by name, secrets by reference only). A journal that has to be gitignored is not knowledge: a teammate cloning the repo inherits skills that cite state they cannot see, and the decay hook cannot watch it.

> **The plan of record is whatever `tracker.system_of_record` names.** The journal is continuity and supporting detail; it never becomes the plan. Every mode reconciles against the tracker first.

## When to use

- Start of a session (`brief`), end of a session (`debrief`, the default), end of an ISO week (`weekly`), or any request for a snapshot (`status`).
- A project is being restarted after dormancy, or handed to a different person or agent.
- A blind spot has appeared and someone is about to guess.

## MANIFEST keys this skill reads

| Key | Decides |
|---|---|
| `rhythm.tracks[]` (`tag`, `name`, `scope`) | the axis the rhythm is kept along. **Tracks are project-declared; this skill MUST NOT invent or hardcode a set.** |
| `rhythm.journal_dir` · `rhythm.timezone` | where entries live and what "today" means |
| `rhythm.cadences[]` (`name`, `when`, `audience`, `approver`) | recurring obligations, if the project has any |
| `roles[]` (`role`, `owns[]`, `route_via`) | who owns which class of unknown (see *Blind-spot routing*) |
| `tracker.system_of_record` | the plan every mode reconciles against first |
| `paths.*` · `watched` | what `brief` and `status` read for decisions, state and decay. `watched` is the one watch-set key; `decay.watch` is a retired name |

## Modes

| Mode | Trigger | Reads, in order | Writes | Output |
|---|---|---|---|---|
| `brief` | session start | tracker (open and in-flight per track) · repo history since the last entry · last journal entry, especially each track's **Next** · newest L2 records **by modification time, not by number** (an amendment lands on an old number) · the decay signal | nothing | at most 6 lines: one per active track, carry-over blockers, the single next-best move |
| `debrief` | session end (default) | this session's work · the tracker | the journal entry | the entry path, the rendered drafts, the routed list |
| `weekly` | end of ISO week | the week's entries · the tracker | the weekly rollup | per-track momentum, decisions locked (each with its `[src: adr/NNNN]`), blockers cleared vs still open, next week's focus, the single biggest risk |
| `status` | on demand | tracker · open decisions · gates and decay state | nothing | the critical path, what blocks what, knowledge health, the next-best move |

**Every mode MUST name a track that has gone silent** rather than omitting it. Omission reads as "fine"; naming it is how a dropped responsibility becomes visible. A track with no activity collapses to one line (`quiet`), never to four empty headings.

## Tracks and the three questions

Each track answers the same three questions: **Done** (what shipped or changed) · **In progress and challenges** (what is mid-flight, what blocks it, who owns the block) · **Next** (the plan for the next session).

- **MUST** tag every line with at least one track tag. Untagged is a smell: it means the work has no owner-axis.
- **MAY** dual-tag when one action genuinely spans two tracks. **SHOULD** reserve *Cross-cutting* for decisions, risks and dependencies that belong to no single track.
- A track is *what work*, not *who hears about it*. Audience is a separate axis (see *Audience-aware drafts*).

## Blind-spot routing

Run once per session, in `debrief`. **MUST NOT guess.** An agent that answers a question outside its evidence produces a confident claim with no provenance, and the next session will treat it as fact.

| Class of unknown | Route to | Artifact produced |
|---|---|---|
| "Is this still true?" about the system | re-verify against the live system this turn | a proposed `docs/state/` replacement routed to `bone-curator`, dated, method stated |
| Technical or architectural choice | `bone-adr` | a decision candidate, with the drivers named |
| Interface behaviour across a seam | `bone-contract` | a contract question against the registered seam |
| Product, business or scope | the owning role in `roles[]`, via its `route_via` | a drafted question, held for approval |
| A claim in the knowledge base that now looks wrong | `bone-curator` | a proposed changeset, never a direct edit |

**Any blind spot that resolves to a question owed to a named person MUST be persisted with full context** (what is blocked, what was already tried, what the answer unblocks, when it is needed), not routed and forgotten. `brief` and `status` MUST surface the persisted questions that are due.

## The continuity journal

- One file per day: `<rhythm.journal_dir>/YYYY-MM-DD.md`. Weekly rollups: `<rhythm.journal_dir>/weekly/YYYY-Www.md`. Multiple sessions in a day append timestamped blocks.
- **Committed, always.** Sensitive-free by construction is the price of admission; an entry class that cannot be committed is not journal material.
- Sub-bullets stay phrase-length; the journal is read at speed by someone reconstructing state.

Entry template (indented, with heading levels named, so the template does not pollute this file's structure):

    H1   <YYYY-MM-DD>
    H2   Session <n> - <theme>
    H3   [<TAG>] <track name>
         - Done: ...  ·  In progress + blockers (-> owner): ...  ·  Next: ...
    H3   [<TAG>] <track name>
         - quiet
    H3   Cross-cutting
         - decisions, risks, dependencies spanning more than one track
    H3   Routed
         - <class> -> <role or skill> : <artifact or "held">
    H3   Restart block
         - Stopped at: <one line per active track>
         - Next action: <the single action> because <fact> [src: adr/NNNN]
         - Verify first: <facts whose records are past the staleness horizon>
         - Owed: <open questions, who owes them, since when>

## Restarting a dormant project

The **Restart block is mandatory in the last entry of every session** and is the whole reason the journal exists. A project picked up after months does not need a narrative; it needs four things, and they are exactly the four lines above.

On restart, the order is: `bone-onboard` (establish what is currently true) **before** `brief` (reconstruct where the work stopped). Running `brief` first produces a confident summary built on facts that expired during the gap. **MUST** treat every Restart-block claim older than the project's staleness horizon as a hypothesis to re-verify, not as state.

## Audience-aware drafts

Render only the audiences that apply. Seed each from the tracks, then finalize by what that audience needs.

- **MUST NOT** auto-send anything outward. Every external draft is held for the approver named in `rhythm.cadences[].approver`.
- **MUST** strip internal jargon, record identifiers and infrastructure detail from outward drafts, and MUST NOT carry sensitive values in any of them.
- **MUST** be able to trace every outward claim to a journal line from the period covered. An outward claim with no internal record is an invented status.
- **SHOULD** let a quiet track stay journal-only rather than manufacturing progress for it.

## Output

`brief`: at most 6 lines, writes nothing. `debrief`: the entry path, the drafts rendered by audience, and the routed list. `weekly`: the rollup path plus the drafts it feeds. `status`: a snapshot, no writes.

Draft state vocabulary (closed set): `DRAFT` · `HELD (awaiting <approver>)` · `APPROVED` · `SENT`. A draft never moves from `DRAFT` to `SENT` inside this skill.

## Critical gotchas

- **Chat is not continuity.** A session's context window is discarded, compacted or lost; what survives is what was written to a file. A debrief skipped because "it is all fresh in my head" is a decision to lose it. *General rule: state that exists only in a running session does not exist.*
- **A journal that is gitignored is invisible knowledge.** It cannot be watched for decay, cloned by a teammate, or cited as provenance, and the skills that reference it point at nothing. *General rule: if an artifact is a declared input to a skill, it must be in the repository.*
- **Silence reads as health.** A track that produces no line for three weeks looks identical to a track with nothing to report, which is how an unowned responsibility survives a whole quarter. *General rule: absence of signal MUST be reported as a signal.*
- **A brief built from the newest record number misses the newest decision.** Amendments land on old numbers, so ordering by identifier hides the most recent change. *General rule: sort by when it changed, never by what it is called.*
- **Routing without persisting is forgetting with extra steps.** A question raised and not written down is asked again next month while the blocked work stays blocked. *General rule: an unanswered question is state, and state belongs in a file.*

## Boundary

Peer relations are declared once, in `meta.yaml` under `chains_with`, never here.

This skill owns the **rhythm and the journal**. It never decides (`bone-adr`), never edits the knowledge base (`bone-curator`), and never sends outward communication on its own.
