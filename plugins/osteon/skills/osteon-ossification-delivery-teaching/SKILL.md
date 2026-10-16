---
name: osteon-ossification-delivery-teaching
description: Teach people outside the session what an ossification cycle delivered and where it stands, as a delivery, status or progress report rendered from one source into Markdown and PDF per audience, with headless screenshots and every claim graded by what proves it. Use when asked for a "delivery report", "status report", "progress report", "what changed and where to test", "what do we tell the client", or to announce a batch. NOT the session brief or journal (bone-standup), NOT the plan itself (osteon-ossification-planner-project-daily). Load the project context unit first.
---

# Ossification delivery teaching

A cycle has taught nobody anything until a person who was not in the session can say what changed,
where to see it, what is still open and what is asked of them. The session that owns the merge owns
the report; this unit owns how it is read from the world, graded, written for its reader and
rendered.

> **A report is a claim about the world at one moment, so it is read from the world at that moment
> and never from memory.** Every figure and state is re-read when the report is made, and every
> item carries what proves it. Yesterday's figures in a professional layout are a stale claim that
> looks verified.

## One source, three editions, three kinds

- **MUST** keep one source file, `delivery.json`, and render every output from it with
  `scripts/render.py`. **MUST** correct the source and re-render, never a rendered file: an edit in
  one PDF is absent from the other editions and lost at the next render, and `check.py` fails it.
- **MUST** render the editions the readers need, from `client`, `colleague` and `owner`, each as
  `.md`, `.html` and `.pdf`.
- **CONTEXT** the kind follows the reader's words. "What changed", "where to test" or "announce" is
  `delivery`. "Where are we" or "status" is `status`. "Since last time", "this week" or "progress" is
  `progress`, rendered with `--previous <earlier delivery.json>` so movement is computed, not recalled.
- **SHOULD** render `delivery` with its plan section when the ask is ambiguous: it answers all three.

## Requirements and verdicts

- Install Python 3.9+ and a Chromium-family browser (`PATH`, `DELIVERY_BROWSER` or `--browser`), or
  no PDF prints and `check.py` fails. Set `DELIVERY_BROWSER_NO_SANDBOX=1` in a container or nested
  sandbox. Install Pillow and PyMuPDF for a PASS; poppler reads PDF pages and text, not images.
- `check.py` and `capture.py` report each check as `PASS`, `FAIL` or `NEEDS-INFO` and exit 0, 1 or 2.
  NEEDS-INFO names what would decide it.

## Procedure

1. **Fix the as-of point.** **MUST** record the read time and the plan reference before the first
   read; the cover prints both.
2. **Read the sources fresh**: the plan (task states, open-work kinds), the forge (every change
   request merged since the baseline, with its merge commit), the hosts (the build each surface
   runs). **MUST** page every listing to its end and state the count it returned. **MUST NOT**
   assert a total or an absence from a truncated read.
3. **Build the bank mechanically**, one record per merged change request. **MUST** decide merged
   against deployed by an ancestry test of the merge commit against the deployed commit, never by
   date. **MUST** parse records one by one and assert the parsed count equals the listed count.
4. **Grade every item** on the evidence ladder. **MUST** grade by the lowest state whose proof is in
   hand.
5. **Write the teaching text** in agent batches of 15 items or fewer, each item as the card.
   **MUST** assert mechanically that every bank id returns exactly once and every quoted string is a
   verbatim substring of its source, before any summary prose.
6. **Refute every test-now claim** (`seen-live`, `deployed`) with a separate read-only agent that
   re-runs the probe. **MUST** keep the lower state when writer and verifier disagree.
7. **Split open work by kind.** **MUST** count each open task in exactly one kind of the closed set.
   **MUST** report a question the start gate settled as the default in force, never as pending.
8. **Capture screenshots** with `scripts/capture.py`, under the rules below.
9. **Render, then check** with `scripts/check.py`. **MUST** treat FAIL as blocking and NEEDS-INFO as
   not a pass. **MUST** pass the project's secret scanner to `--scanner` with every ignore file
   disabled, over a directory holding none: a scanner that loads an old one reports a filtered
   clean, and `check.py` fails an output directory that carries one.
10. **Store and log; never send.** **MUST** write outputs outside every code checkout, in the
    project's delivery directory under the report date, and log each report as drafted, not sent.
    **MUST NOT** send, post or publish a report; a person does. **SHOULD** hand back the PDF paths,
    the check verdicts and a five-line summary.

## Screenshots

- **MUST** capture headless in a fresh throwaway browser profile, which `capture.py` forces.
  **MUST NOT** drive, read or reuse a person's own browser, profile, cookies or keychain.
- **MUST** capture signed-out views only, unless a person supplies a session for it.
  **MUST NOT** type a credential into any page; `capture.py` refuses an address that carries one.
- **SHOULD** capture a machine response (JSON or plain text) at a width near 900 and scale 2, so
  its text stays legible in print; `capture.py` trims empty space below short content.
- **MUST** caption a capture of a saved copy with the real address, and **MUST NOT** hand anyone
  `shots/captures.json`: it is a working record, not part of the report.
- **MUST** treat a blank capture as no capture. **SHOULD** capture every `seen-live` item with a
  reachable address, and give a signed-in view a `screen_note`, which renders as a labelled
  placeholder instead of an invented image.

## Writing to teach

- **MUST** write every test-now item as the card: what changed, why it matters, where, numbered
  steps, what you should see, and the access it needs. The bar is that a reader who never saw the
  plan can test it without asking anyone.
- **MUST** say the narrow true thing once. A sentence that needs a later qualification is rewritten
  or its item graded down, never qualified.
- **MUST** write neutrally: what changed and what is needed. **MUST NOT** apologise, blame or narrate
  the session's own process in a `client` edition.
- **MUST** put what a reader needs before starting (a host on an older build, an account
  prerequisite) in `read_first`, once, and define every term a reader meets in `glossary`.
- **MUST** write every figure derived from items or the plan as a token, such as
  `{{count state=seen-live}}`, so prose, tables and charts cannot disagree.

## Boundary

This unit never changes a task state, merges or sends. Peer relations are declared once, in
`meta.yaml`.

## References

- `references/evidence-and-kinds.md`: the evidence ladder, the proof each state needs and the closed
  set of open-work kinds. Skipping it reports merged work as live and lumps approvals, account acts
  and pipeline outages into one alarming count of "decisions".
- `references/editions.md`: what each audience sees and its wording rules. Skipping it puts task
  identifiers, private links and process narrative into a client's PDF.
- `references/delivery-schema.md`: every field of `delivery.json`, the tokens and the worked
  example. A source written from memory drops fields `check.py` relies on, so it passes on less than
  it should.
- `references/writing-and-verifying.md`: the card, the batch prompt, the refuting verifier and the
  mechanical post-checks. Skipping it yields steps a first-time reader cannot follow and claims
  nobody re-ran.
- `scripts/capture.py`, `scripts/render.py`, `scripts/check.py`: each takes `--help`.
  `scripts/example/delivery.json` renders end to end with no network.
