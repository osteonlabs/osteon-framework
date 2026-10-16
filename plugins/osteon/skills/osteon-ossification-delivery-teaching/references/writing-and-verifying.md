# Writing and verifying items

## The card

A test-now card teaches one change. Each part has one job.

    title          The outcome as a plain sentence a reader would say, such as "Librarians can
                   extend a loan from the catalogue website", never the engineering title.
    what_changed   One to three sentences: what is different now, and what it replaced.
    why            What it changes for a customer, an operator or the business.
    where          The environment first, then the address, then the path through the screens.
    steps          One action per step. Start from an address. Include the sign-in step. End with
                   the check that proves it, and add a step for the refusal path when the change
                   refuses something.
    expect         What the reader sees when it works, and what they see when it rightly refuses.
    access         The account or role, or "none".
    not_yet        What it does not do yet, when a reader would otherwise expect it.

- **MUST** write steps against what the host serves, never against what the code suggests. A
  screen label is read from the host or from a capture.
- **MUST** start `evidence` with `needs-human:` rather than guess a step nobody can see, such as a
  signed-in screen with no capture. `check.py` reports each such card as NEEDS-INFO.
- **MUST** describe a credential-shaped value in `evidence` instead of quoting it, after decoding
  proves what it is: "an unsigned test token, payload {"sub":"x"}", never the token. A forged test
  token copied from a probe trips every scanner on every edition, and the only alternatives are an
  ignore list, which is the failure NK-4 names, or a reader who learns to wave findings through.
  A value that decodes to anything signed is a stop, not a description.
- **SHOULD** keep coming-next items to `title`, `what_changed` and `test_later`: the reader cannot act
  on them yet, and a full card invites a test that cannot pass.
- **SHOULD** group a surface's cards so the reader signs in once and walks through them in order.

## The batch prompt

Hand each writing agent at most 15 bank records. Inside the session's own prompt blocks, the
delivery part is:

    For each record below, return one card in the JSON shape given. Write for <reader>, who has
    never seen the plan or the code. Use only facts present in the record: its body, its diff
    summary and its probe result. Copy quoted screen text and response bodies verbatim. Never raise
    the state a record carries; you may lower it, saying why in "evidence". If a step needs a
    screen you cannot see, begin "evidence" with "needs-human:" and write no guessed step.
    Return exactly one card per record id, and no other ids.

## The refuting verifier

A read-only agent that did not write the cards, one per batch of test-now claims:

    Try to refute each claim. Re-run its probe exactly as recorded, signed out and read-only. If
    the host no longer shows the change, or you cannot run the probe, return the next lower state
    on the ladder with what you observed. When uncertain, lower it. Never raise a state.

## Mechanical post-checks, run by the session

- **MUST** assert every bank id appears in exactly one returned card, and no card carries an id
  from outside its batch.
- **MUST** assert every string a card presents as quoted is a substring of its record.
- **MUST** assert no returned state is higher than the bank's, and keep the verifier's state when it
  is lower.
- **MUST** run these before any summary is written. A step that fails partway and still writes its
  summary produces a confident paragraph about work that did not happen.
