#!/usr/bin/env python3
"""Check a delivery.json and its rendered editions before anyone reads them.

  check.py SOURCE --out DIR [--edition E]... [--scanner "COMMAND {dir}"]

One verdict per check from the closed set PASS, FAIL, NEEDS-INFO. Exit 0 all PASS, 1 any FAIL, 2
NEEDS-INFO with no FAIL. NEEDS-INFO is not a pass; each one names what would decide it. Standard
library only; reads PDFs with pdfinfo and pdftotext or PyMuPDF, and images with Pillow, when present.
"""
import argparse
import collections
import hashlib
import html as htmllib
import json
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True  # a bytecode cache would carry this checkout's absolute path
sys.path.insert(0, str(HERE))
import render  # noqa: E402  the one enumeration of states, kinds, editions and file names

SECRETS = [
    ('cloud access key id', r'(?<![A-Z0-9])(?:A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z2-7]{16}(?![A-Z0-9])'),
    ('private key block', r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
    ('signed token', r'eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*'),
    ('forge token', r'\bgh[pousr]_[A-Za-z0-9]{30,}\b'),
    ('chat token', r'\bxox[abprs]-[A-Za-z0-9-]{10,}'),
    ('payment key', r'\b[sr]k_(?:live|test)_[A-Za-z0-9]{16,}\b'),
    ('assigned secret', r'(?i)\b(?:password|passwd|secret|api[_-]?key|access[_-]?token|client[_-]?secret)'
                        r'["\']?\s*[:=]\s*["\']?[A-Za-z0-9/+_.-]{12,}'),
]
APOLOGY = re.compile(r'(?i)\b(sorry|apologi[sz]e|apologies|unfortunately|my mistake|our mistake)\b')
EM_DASH = '\u2014'
MONTHS = (r'(?:January|February|March|April|May|June|July|August|September|October|November|December|'
          r'Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)')


class Verdicts:
    def __init__(self):
        self.rows = []

    def report(self, check, fails, infos, passed):
        """FAIL rows and NEEDS-INFO rows as found; PASS only when there are neither."""
        for msg in fails:
            self.rows.append(('FAIL', check, msg))
        for msg in infos:
            self.rows.append(('NEEDS-INFO', check, msg))
        if not fails and not infos:
            self.rows.append(('PASS', check, passed))

    def code(self):
        verdicts = {r[0] for r in self.rows}
        return 1 if 'FAIL' in verdicts else 2 if 'NEEDS-INFO' in verdicts else 0


def visible_text(html_text):
    t = re.sub(r'(?is)<(style|script)\b.*?</\1>', ' ', html_text)
    return htmllib.unescape(re.sub(r'(?s)<[^>]+>', ' ', t))


def pdf_text(path):
    tool = shutil.which('pdftotext')
    if tool:
        try:
            r = subprocess.run([tool, '-layout', str(path), '-'], capture_output=True, text=True, timeout=120)
            if r.returncode == 0:
                return r.stdout
        except (OSError, subprocess.TimeoutExpired):
            pass
    try:
        import fitz
        with fitz.open(str(path)) as d:
            return '\n'.join(page.get_text() for page in d)
    except Exception:
        return None


def pdf_images(path):
    try:
        import fitz
    except ImportError:
        return None
    with fitz.open(str(path)) as d:
        return len({img[0] for page in d for img in page.get_images(full=True)})


def mask(s):
    return '%s...(%d chars)' % (s[:4], len(s))


def fingerprint(s):
    return hashlib.sha256(s.encode('utf-8')).hexdigest()[:16]


def shell_fill(template, value):
    """Put value in for every {dir}, quoted for the shell context the placeholder sits in.

    A split path can point the scanner at a different directory that exists and scans clean, which
    is a false PASS on the secret gate, so the value stays one word bare, in '...' and in "...".
    """
    parts, quote, i = [], None, 0
    while i < len(template):
        if template.startswith('{dir}', i):
            if quote == "'":
                parts.append(value.replace("'", "'\\''"))
            elif quote == '"':
                parts.append(re.sub(r'(["\\$`])', r'\\\1', value))
            else:
                parts.append(shlex.quote(value))
            i += 5
            continue
        c = template[i]
        if c == '\\' and quote != "'":
            parts.append(template[i:i + 2])
            i += 2
            continue
        if c in '\'"' and quote in (None, c):
            quote = None if quote else c
        parts.append(c)
        i += 1
    return ''.join(parts)


def walk_strings(value, path=''):
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, list):
        for n, v in enumerate(value):
            yield from walk_strings(v, '%s[%d]' % (path, n))
    elif isinstance(value, dict):
        for k, v in value.items():
            yield from walk_strings(v, '%s.%s' % (path, k) if path else k)


def main(argv=None):
    ap = argparse.ArgumentParser(description='Check a delivery.json and its rendered editions.')
    ap.add_argument('source')
    ap.add_argument('--out', required=True)
    ap.add_argument('--edition', action='append', choices=render.EDITIONS)
    ap.add_argument('--scanner', help='secret scanner command run over the output directory; it must hold {dir}, which is replaced by '
                         'that directory quoted as one word; exit 0 means clean')
    args = ap.parse_args(argv)
    V = Verdicts()
    out = Path(args.out)

    try:
        raw_text = Path(args.source).read_text(encoding='utf-8')
        data = json.loads(raw_text)
    except (OSError, ValueError) as exc:
        V.report('source-parses', ['%s cannot be read as JSON: %s' % (args.source, exc)], [], '')
        return finish(V)

    # 1. Structure.
    fails, infos = [], []
    try:
        render.validate(data)
    except render.SourceError as exc:
        fails.append(str(exc))
    for field in ('standfirst', 'prepared_for'):
        if not data.get(field):
            fails.append('%s is missing' % field)
    if not (data.get('as_of') or {}).get('read_at'):
        fails.append('as_of.read_at is missing; a report with no as-of point cannot be told to be stale')
    if not data.get('editions'):
        fails.append('editions is empty')
    unknown = sorted(set(data) - render.TOP_KEYS)
    if unknown:
        infos.append('unknown top-level keys %s; a misspelt field is otherwise ignored' % unknown)
    V.report('structure', fails, infos, 'schema, kind, title, as-of point, areas, states and editions are well formed')
    if fails:
        return finish(V)

    # 2. Tokens.
    try:
        expanded = render.Tokens(data).expand(data)
        V.report('tokens', [], [], 'every token expands, and none is left unexpanded')
    except render.SourceError as exc:
        V.report('tokens', [str(exc)], [], '')
        return finish(V)

    items = data.get('items') or []

    # 3. Items: coverage exactly once, and the card each state needs.
    fails, infos = [], []
    counts = collections.Counter(i.get('id') for i in items)
    dups = sorted(str(k) for k, c in counts.items() if c > 1)
    if dups:
        fails.append('item ids appear more than once: %s' % dups[:10])
    if None in counts or '' in counts:
        fails.append('an item has no id')
    for i in items:
        if i.get('exclude'):
            if not i.get('evidence'):
                fails.append('item %s is excluded with no reason in evidence' % i.get('id'))
            continue
        state, iid = i.get('state'), i.get('id')
        if not i.get('title'):
            fails.append('item %s has no title' % iid)
        if state in render.TEST_NOW:
            missing = [f for f in ('what_changed', 'where', 'steps', 'expect', 'access') if not i.get(f)]
            if missing:
                fails.append('test-now item %s lacks %s' % (iid, ', '.join(missing)))
            if not i.get('why'):
                infos.append('test-now item %s has no "why"; the reader is told what, not why it matters' % iid)
            if str(i.get('evidence', '')).startswith('needs-human:'):
                infos.append('item %s waits on a person: %s' % (iid, i['evidence'][:120]))
        if state == 'seen-live' and not i.get('evidence'):
            fails.append('seen-live item %s carries no evidence; the state is unproven' % iid)
        if state in render.LATER and not i.get('what_changed'):
            fails.append('coming-next item %s lacks what_changed' % iid)
        for shot in i.get('screenshots') or []:
            if not (out / shot.get('file', '')).is_file():
                fails.append('item %s screenshot %s does not exist under the output directory' % (iid, shot.get('file')))
    V.report('items', fails, infos, '%d items, ids unique, every state carries the card and proof it needs' % len(items))

    # 4. Plan arithmetic.
    fails = []
    plan = data.get('plan')
    if data['kind'] in ('status', 'progress') and not plan:
        fails.append('a %s report needs a plan section' % data['kind'])
    if plan:
        done, nn, op = plan.get('done', 0), plan.get('not_needed', 0), plan.get('open', 0)
        if plan.get('total') is not None and plan['total'] != done + nn + op:
            fails.append('plan total %s is not done %s + not needed %s + open %s' % (plan['total'], done, nn, op))
        kinds = plan.get('open_by_kind') or []
        seen = collections.Counter(k.get('kind') for k in kinds)
        if any(c > 1 for c in seen.values()):
            fails.append('a kind appears twice in open_by_kind')
        if kinds and sum(k.get('count', 0) for k in kinds) != op:
            fails.append('open_by_kind sums to %d, but open is %d; every open task carries exactly one kind'
                         % (sum(k.get('count', 0) for k in kinds), op))
        for k in kinds:
            if k.get('kind') == 'decision-owed' and k.get('count') and not k.get('note'):
                fails.append('decision-owed has no note naming why no ruling, default or finished task covers it')
        if plan.get('by_area') and not plan.get('by_area_scope'):
            bd = sum(a.get('done', 0) for a in plan['by_area'])
            bo = sum(a.get('open', 0) for a in plan['by_area'])
            if (bd, bo) != (done, op):
                fails.append('by_area sums to done %d, open %d against the plan\'s %d, %d; declare by_area_scope if it counts a subset' % (bd, bo, done, op))
    V.report('plan', fails, [], 'plan figures reconcile and every open task has one kind' if plan else 'no plan section, none required')

    # 5. Figures carry a source.
    fails, infos = [], []
    for k in data.get('kpis') or []:
        if not k.get('source'):
            fails.append('figure %r has no source' % k.get('label'))
    typed = re.sub(render.TOKEN, ' ', data.get('standfirst', ''))
    typed = re.sub(r'\b\d{1,2}(?:st|nd|rd|th)?\s+%s\b|\b%s\s+\d{1,2}\b|\b(?:19|20)\d{2}\b' % (MONTHS, MONTHS), ' ', typed)
    loose = sorted(set(re.findall(r'\b\d[\d,.]*\b', typed)))
    kpi_values = ' '.join(str(k.get('value', '')) for k in expanded.get('kpis') or [])
    loose = [n for n in loose if not re.search(r'\b%s\b' % re.escape(n), kpi_values)]
    if loose:
        infos.append('standfirst figures typed by hand and matching no sourced figure: %s; make them tokens or figures' % loose)
    V.report('figures', fails, infos, 'every figure is a token or carries a source')

    # 6. Rendered outputs are current and untouched.
    fails = []
    manifest_path = out / render.manifest_name(data)
    editions = args.edition or data.get('editions') or []
    manifest = None
    if not manifest_path.is_file():
        fails.append('%s is missing; render before checking' % manifest_path.name)
    else:
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        if manifest.get('source_sha256') != hashlib.sha256(raw_text.encode('utf-8')).hexdigest():
            fails.append('the outputs were rendered from a different source; re-render')
        if data['kind'] == 'progress' and not manifest.get('previous_sha256'):
            fails.append('a progress report was rendered without --previous')
        for ed in editions:
            entry = (manifest.get('editions') or {}).get(ed)
            if not entry:
                fails.append('edition %s was not rendered' % ed)
                continue
            for kind in ('md', 'html', 'pdf'):
                name = entry.get(kind)
                if not name or not (out / name).is_file():
                    fails.append('edition %s has no %s output' % (ed, kind))
                elif render.sha256(out / name) != entry.get(kind + '_sha256'):
                    fails.append('%s was edited after rendering; correct the source and re-render' % name)
    V.report('outputs', fails, [], 'every edition has current, unedited Markdown, HTML and PDF')
    if fails:
        return finish(V)

    texts = {}
    for ed in editions:
        entry = manifest['editions'][ed]
        md = (out / entry['md']).read_text(encoding='utf-8')
        htm = (out / entry['html']).read_text(encoding='utf-8')
        texts[ed] = dict(md=md, html=htm, visible=visible_text(htm), pdf=pdf_text(out / entry['pdf']), entry=entry)

    # 7. The PDF is a readable document carrying its title and its screenshots.
    fails, infos = [], []
    squash = lambda s: re.sub(r'\s+', '', s or '')
    for ed, t in texts.items():
        if not t['entry'].get('pages'):
            infos.append('%s: page count unknown; install pdfinfo or PyMuPDF' % ed) if t['entry'].get('pages') is None else fails.append('%s: PDF has no pages' % ed)
        if t['pdf'] is None:
            infos.append('%s: PDF text not extractable here; install pdftotext or PyMuPDF' % ed)
        elif squash(data['title'])[:40] not in squash(t['pdf']):
            fails.append('%s: the PDF text does not carry the title; it may have printed blank' % ed)
        wanted = len(t['entry'].get('screenshots') or [])
        if wanted:
            got = pdf_images(out / t['entry']['pdf'])
            if got is None:
                infos.append('%s: cannot count embedded images without PyMuPDF; %d expected' % (ed, wanted))
            elif got < wanted:
                fails.append('%s: PDF embeds %d images, %d screenshots expected' % (ed, got, wanted))
    V.report('pdf', fails, infos, 'every PDF has pages, carries its title and embeds its screenshots')

    # 8. Screenshots are not blank.
    infos = []
    files = sorted({s['file'] for i in items if not i.get('exclude') for s in i.get('screenshots') or []})
    if files:
        try:
            from PIL import Image
            for f in files:
                with Image.open(out / f) as im:
                    lo, hi = im.convert('L').resize((96, 60)).getextrema()
                if hi - lo < 10:
                    infos.append('%s is blank or near-uniform; recapture or drop it' % f)
        except ImportError:
            infos.append('Pillow is absent, so %d screenshots were not judged for blankness' % len(files))
    V.report('screenshots', [], infos, '%d screenshots, none blank' % len(files))

    # 9. The client edition leaks nothing internal.
    if 'client' in texts:
        fails, infos = [], []
        t = texts['client']
        rules = data.get('rules') or {}
        body = '\n'.join(x for x in (t['md'], t['visible'], t['pdf'] or '') if x)
        if not rules.get('deny_terms'):
            infos.append('rules.deny_terms is empty; organisation names and machinery words are unchecked')
        for term in rules.get('deny_terms') or []:
            m = re.search(r'(?i)(?<![A-Za-z0-9])%s(?![A-Za-z0-9])' % re.escape(term), body)
            if m:
                fails.append('client edition names %r: ...%s...' % (term, body[max(0, m.start() - 40):m.end() + 40].replace('\n', ' ')))
        if rules.get('internal_id_pattern'):
            hits = sorted(set(re.findall(rules['internal_id_pattern'], body)))
            if hits:
                fails.append('client edition carries internal identifiers %s' % hits[:8])
        else:
            infos.append('rules.internal_id_pattern is empty; task identifiers in the client edition are unchecked')
        pats = [re.compile(p) for p in rules.get('public_link_patterns') or []]
        links = set(re.findall(r'href="([^"#][^"]*)"', t['html'])) | set(re.findall(r'(?<!!)\[[^\]]*\]\(([^)\s]+)\)', t['md']))
        for url in sorted(links):
            if re.match(r'^[a-z][a-z0-9+.-]*:', url, re.I) and not any(p.search(url) for p in pats):
                fails.append('client edition links to %s, which matches no public_link_patterns entry' % url)
        for i in items:
            ev = str(i.get('evidence') or '')
            if len(ev) >= 30 and ev[:40] in t['md']:
                fails.append('client edition carries the evidence line of %s' % i.get('id'))
            eng = i.get('engineering_title')
            if eng and eng != i.get('title') and len(eng) > 12 and eng in t['md']:
                fails.append('client edition carries the engineering title of %s' % i.get('id'))
        if APOLOGY.search(t['md']):
            infos.append('client edition apologises (%r); state what changed and what is needed' % APOLOGY.search(t['md']).group(0))
        V.report('client-edition', fails, infos, 'no denied term, internal identifier, private link, evidence line or engineering title')

    # 10. House style.
    fails = []
    for ed, t in texts.items():
        for kind in ('md', 'html'):
            n = t[kind].count(EM_DASH)
            if n:
                fails.append('%s %s carries %d em dashes' % (ed, kind, n))
    n = raw_text.count(EM_DASH)
    if n:
        fails.append('the source carries %d em dashes' % n)
    V.report('house-style', fails, [], 'no em dash in the source or any output')

    # 10b. No local filesystem path: it names the account and means nothing to a reader.
    fails = []
    local = re.compile(r'file://\S+|/Users/[^/\s]+/|/home/[^/\s]+/|[A-Za-z]:\\Users\\')
    for ed, t in texts.items():
        for kind in ('md', 'html'):
            hits = sorted(set(local.findall(t[kind])))
            if hits:
                fails.append('%s %s carries local paths %s; caption with the real address' % (ed, kind, hits[:3]))
    V.report('local-paths', fails, [], 'no local filesystem path in any output')

    # 11. Secrets, in the source and in every output.
    fails = []
    reviewed = set((data.get('rules') or {}).get('reviewed_secret_fingerprints') or [])
    corpora = [('source', raw_text)] + [('%s %s' % (ed, k), t[k]) for ed, t in texts.items() for k in ('md', 'html', 'pdf') if t.get(k)]
    for where, text in corpora:
        for label, pattern in SECRETS:
            for m in re.finditer(pattern, text):
                if fingerprint(m.group(0)) not in reviewed:
                    fails.append('%s: %s %s (fingerprint %s)' % (where, label, mask(m.group(0)), fingerprint(m.group(0))))
    V.report('secrets', sorted(set(fails)), [], 'no secret-shaped value in the source or any output')

    # 12. The project's own scanner, over a directory that holds no ignore file.
    ignores = sorted(p.name for p in out.iterdir() if p.is_file() and p.name.startswith('.') and p.name.endswith('ignore'))
    if ignores:
        V.report('ignore-files', ['the output directory holds %s; a scanner may load it whatever its flags say, so move it out' % ignores], [], '')
    if args.scanner and '{dir}' not in args.scanner:
        V.report('scanner', ['the scanner command has no {dir} placeholder, so it does not scan the output directory'], [], '')
    elif args.scanner:
        # Absolute, so a directory name that starts with "-" cannot be read as an option.
        cmd = shell_fill(args.scanner, str(out.resolve()))
        try:
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=600)
            ok = r.returncode == 0
            V.report('scanner', [] if ok else ['scanner exited %d: %s' % (r.returncode, (r.stdout + r.stderr).strip()[-300:])], [],
                     'the project scanner found nothing over the output directory')
        except subprocess.TimeoutExpired:
            V.report('scanner', ['scanner timed out after 600 s'], [], '')
    else:
        V.report('scanner', [], ['the project secret scanner was not run over the output directory; pass --scanner with its ignore file disabled'], '')

    return finish(V)


def finish(V):
    for verdict, check, msg in V.rows:
        print('%-11s %-15s %s' % (verdict, check, msg))
    code = V.code()
    print('%-11s %-15s %s' % ({0: 'PASS', 1: 'FAIL', 2: 'NEEDS-INFO'}[code], 'overall',
                              {0: 'ready for a person to read and send', 1: 'blocked; fix the source and re-render',
                               2: 'not a pass; decide each NEEDS-INFO above'}[code]))
    return code


if __name__ == '__main__':
    sys.exit(main())
