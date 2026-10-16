#!/usr/bin/env python3
"""Render delivery.json into Markdown, HTML and PDF, one set per edition.

  render.py SOURCE --out DIR [--edition E]... [--previous EARLIER.json] [--no-pdf] [--browser PATH]

Standard library only. Every figure in prose is a token computed here from the items and the plan,
so text, tables and charts cannot disagree. The PDF is printed by a headless browser in a throwaway
profile (_browser.py). Writes <slug>-<edition>.md/.html/.pdf and <slug>.render.json.

Exit 0: every requested output written. 1: the source is wrong, or a PDF failed to print.
2: Markdown and HTML written but no PDF, because no browser was found or --no-pdf was given.
"""
import argparse
import hashlib
import html
import json
import math
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
# A bytecode cache embeds this checkout's absolute path. This line stops new caches for the imports below
# and removes none that exist. An importer writes this file's own cache before the line runs, so import
# this module only under `python3 -B`, and never stage a __pycache__ directory.
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
import _browser  # noqa: E402

SCHEMA = 'osteon.delivery/1'
CSS_PATH = HERE.parent / 'assets' / 'report.css'

LADDER = ['seen-live', 'deployed', 'merged', 'needs-build', 'needs-apply', 'internal']
TEST_NOW = ('seen-live', 'deployed')
LATER = ('merged', 'needs-build', 'needs-apply')
STATE = {
    'seen-live': dict(label='Seen live', short='Seen live', fg='#17663a', bg='#e3f4e8', bar='#2e9e5b',
                      meaning='The change itself was observed on the host, by a check anyone can repeat.'),
    'deployed': dict(label='Deployed, please confirm', short='Deployed', fg='#1a55a6', bg='#e3eefc', bar='#2f6fd0',
                     meaning='The build carrying the change is live; seeing it needs a sign-in or a device, so please confirm it there.'),
    'merged': dict(label='Merged, not yet seen', short='Merged', fg='#8a5300', bg='#fdf0da', bar='#d98e04',
                   meaning='Finished and merged, and not yet seen on the host; it becomes testable once a deploy carrying it is confirmed.'),
    'needs-build': dict(label='Needs a build', short='Needs build', fg='#5a379c', bg='#efe8fb', bar='#7c55c7',
                        meaning='Visible only in an application build that does not exist yet.'),
    'needs-apply': dict(label='Needs applying', short='Needs apply', fg='#384556', bg='#e9edf3', bar='#607089',
                        meaning='Defined and merged; nothing changes until it is applied.'),
    'internal': dict(label='Internal', short='Internal', fg='#5f5f5f', bg='#efefef', bar='#b3b3b3',
                     meaning='Tests, tooling or documentation; nothing to see.'),
}
LATER_HEADING = {'merged': 'Merged, not yet on the host', 'needs-build': 'After the next application build',
                 'needs-apply': 'When it is applied'}
KINDS = ['workable-now', 'needs-a-go', 'account-act', 'person-check', 'held-by-ruling', 'decision-owed']
KIND = {
    'workable-now': dict(label='Ours to finish now', bar='#2f6fd0'),
    'needs-a-go': dict(label='Ours, one step awaiting approval', bar='#6f9be8'),
    'account-act': dict(label='Needs an account holder', bar='#d98e04'),
    'person-check': dict(label='Built, needs someone to check it', bar='#2e9e5b'),
    'held-by-ruling': dict(label='Held on purpose', bar='#98a2b3'),
    'decision-owed': dict(label='A decision we need', bar='#c2413b'),
}
EDITIONS = ('client', 'colleague', 'owner')
KIND_TITLE = {'delivery': 'Delivery report', 'status': 'Status report', 'progress': 'Progress report'}
EDITION_LABEL = {'client': 'Client edition', 'colleague': 'Colleague edition', 'owner': 'Owner edition'}
TOP_KEYS = {'schema', 'kind', 'title', 'subtitle', 'slug', 'locale', 'prepared_for', 'prepared_by',
            'signature', 'as_of', 'editions', 'standfirst', 'kpis', 'read_first', 'areas', 'items',
            'internal_counts', 'plan', 'defaults', 'asks', 'acts_needing_go', 'risks', 'next',
            'glossary', 'rules'}
ORDER = {
    'delivery': ['read_first', 'glance', 'checklist', 'test_now', 'coming', 'internal', 'plan', 'asks', 'acts',
                 'risks', 'next', 'glossary', 'index', 'about'],
    'status': ['read_first', 'plan', 'glance', 'landed', 'asks', 'acts', 'risks', 'next', 'glossary',
               'index', 'about'],
    'progress': ['read_first', 'moved', 'test_now', 'plan', 'landed', 'asks', 'acts', 'risks', 'next', 'glossary',
                 'index', 'about'],
}
KEEP = '<!--keep-with-heading-->'
TOKEN = re.compile(r'\{\{\s*([a-z_][a-z_.-]*)((?:\s+[a-z_]+=[A-Za-z0-9_,.-]+)*)\s*\}\}')
URL = re.compile(r'https?://[^\s<>"\'`)\]]+[^\s<>"\'`)\].,;:!?]')


class SourceError(Exception):
    pass


# ---------------------------------------------------------------- source

def load(path):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError, ValueError) as exc:
        raise SourceError('%s cannot be read as JSON: %s' % (path, exc))


def validate(data):
    """The structural minimum rendering needs. check.py owns the full verdict."""
    errs = []
    if data.get('schema') != SCHEMA:
        errs.append('schema must be %s' % SCHEMA)
    if data.get('kind') not in KIND_TITLE:
        errs.append('kind must be one of %s' % ', '.join(KIND_TITLE))
    if not data.get('title'):
        errs.append('title is missing')
    areas = [a.get('id') for a in data.get('areas') or []]
    if not areas:
        errs.append('areas is empty')
    for item in data.get('items') or []:
        if item.get('state') not in STATE:
            errs.append('item %s: state %r is not on the ladder' % (item.get('id'), item.get('state')))
        if item.get('area') not in areas:
            errs.append('item %s: area %r is not declared' % (item.get('id'), item.get('area')))
    for key in data.get('internal_counts') or {}:
        if key not in areas:
            errs.append('internal_counts names undeclared area %r' % key)
    for k in (data.get('plan') or {}).get('open_by_kind') or []:
        if k.get('kind') not in KIND:
            errs.append('plan kind %r is not in the closed set' % k.get('kind'))
    for ed in data.get('editions') or []:
        if ed not in EDITIONS:
            errs.append('edition %r is not one of %s' % (ed, ', '.join(EDITIONS)))
    if errs:
        raise SourceError('; '.join(errs))


class Tokens:
    def __init__(self, data):
        self.items = [i for i in data.get('items') or [] if not i.get('exclude')]
        self.areas = {a.get('id') for a in data.get('areas') or []}
        self.plan = data.get('plan') or {}
        self.kinds = {k.get('kind'): k.get('count', 0) for k in self.plan.get('open_by_kind') or []}
        counted = sum((data.get('internal_counts') or {}).values())
        self.internal = counted + sum(1 for i in self.items if i.get('state') == 'internal')
        self.changes = self.internal + sum(1 for i in self.items if i.get('state') != 'internal')

    def _one(self, m):
        name = m.group(1)
        args = dict(a.split('=', 1) for a in m.group(2).split())
        if name == 'count':
            sel = self.items
            for key, allowed in (('state', set(LADDER)), ('area', self.areas)):
                if key in args:
                    want = args.pop(key).split(',')
                    bad = [w for w in want if w not in allowed]
                    if bad:
                        raise SourceError('token %s names unknown %s %s' % (m.group(0), key, bad))
                    sel = [i for i in sel if i.get(key) in want]
            if args:
                raise SourceError('token %s has unknown arguments %s' % (m.group(0), sorted(args)))
            return str(len(sel))
        if args:
            raise SourceError('token %s takes no arguments' % m.group(0))
        if name == 'changes':
            return str(self.changes)
        if name == 'internal':
            return str(self.internal)
        if name.startswith('plan.') and name[5:] in ('total', 'done', 'not_needed', 'open'):
            if name[5:] not in self.plan:
                raise SourceError('token %s: the plan has no %s' % (m.group(0), name[5:]))
            return str(self.plan[name[5:]])
        if name.startswith('kind.') and name[5:] in KINDS:
            return str(self.kinds.get(name[5:], 0))
        raise SourceError('unknown token %s' % m.group(0))

    def expand(self, value, top=True):
        if isinstance(value, str):
            if '{{' not in value:
                return value
            out = TOKEN.sub(self._one, value)
            if '{{' in out:
                raise SourceError('unrecognised token syntax in %r' % value[:80])
            return out
        if isinstance(value, list):
            return [self.expand(v, False) for v in value]
        if isinstance(value, dict):
            return {k: (v if (top and k == 'rules') else self.expand(v, False)) for k, v in value.items()}
        return value


def prepare(path):
    data = load(path)
    validate(data)
    return data, Tokens(data).expand(data)


def slug(data):
    return data.get('slug') or re.sub(r'[^a-z0-9]+', '-', data.get('title', 'report').lower()).strip('-')[:60]


def manifest_name(data):
    return '%s.render.json' % slug(data)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pdf_pages(path):
    tool = shutil.which('pdfinfo')
    if tool:
        try:
            r = subprocess.run([tool, str(path)], capture_output=True, text=True, timeout=60)
            m = re.search(r'^Pages:\s+(\d+)', r.stdout, re.M)
            if m:
                return int(m.group(1))
        except (OSError, subprocess.TimeoutExpired):
            pass
    try:
        import fitz  # optional
        with fitz.open(str(path)) as d:
            return d.page_count
    except Exception:
        return None


# ---------------------------------------------------------------- text helpers

def esc(s):
    return html.escape('' if s is None else str(s), quote=True)


def _bold(t):
    return re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', t)


def inline(s):
    """Escape, then render `code`, **bold** and bare addresses as links."""
    out = []
    for part in re.split(r'(`[^`\n]+`)', '' if s is None else str(s)):
        if len(part) > 1 and part[0] == '`' and part[-1] == '`':
            out.append('<code>%s</code>' % esc(part[1:-1]))
            continue
        pos = 0
        for m in URL.finditer(part):
            out.append(_bold(esc(part[pos:m.start()])))
            out.append('<a href="%s">%s</a>' % (esc(m.group(0)), esc(m.group(0))))
            pos = m.end()
        out.append(_bold(esc(part[pos:])))
    return ''.join(out)


def plural(n, one, many):
    return '%d %s' % (n, one if n == 1 else many)


def cell(s):
    return ('' if s is None else str(s)).replace('|', '\\|').replace('\n', ' ')


def gfm_anchor(title):
    return re.sub(r'[^\w\- ]', '', title.lower()).strip().replace(' ', '-')


def when(value, with_time=True):
    if not value:
        return ''
    text = str(value)
    try:
        dt = datetime.fromisoformat(text.replace('Z', '+00:00'))
    except ValueError:
        return text
    if dt.tzinfo:
        dt = dt.astimezone(timezone.utc)
    day = '%d %s %d' % (dt.day, dt.strftime('%B'), dt.year)
    if with_time and 'T' in text:
        return '%s, %s UTC' % (day, dt.strftime('%H:%M'))
    return day


def per_edition(value, edition):
    if isinstance(value, dict):
        return value.get(edition) or value.get('default') or ''
    return value or ''


def chip(state):
    s = STATE[state]
    return '<span class="chip" style="color:%s;background:%s">%s</span>' % (s['fg'], s['bg'], esc(s['label']))


def md_chip(state):
    return '`%s`' % STATE[state]['label'].upper()


# ---------------------------------------------------------------- charts (inline SVG, no dependency)

def bar_svg(value, peak, colour, width=240, height=11):
    w = 0 if not peak else max(2.0 if value else 0.0, width * value / float(peak))
    return ('<svg width="%d" height="%d" viewBox="0 0 %d %d" role="img" aria-label="%s">'
            '<rect width="%d" height="%d" rx="3" fill="#eef1f5"/>'
            '<rect width="%.1f" height="%d" rx="3" fill="%s"/></svg>'
            % (width, height, width, height, value, width, height, w, height, colour))


def stack_svg(segments, total, peak, width=150, height=10):
    span = 0 if not peak else width * total / float(peak)
    x, rects = 0.0, []
    for value, colour in segments:
        if not value or not total:
            continue
        w = span * value / float(total)
        rects.append('<rect x="%.1f" width="%.1f" height="%d" fill="%s"/>' % (x, w, height, colour))
        x += w
    return ('<svg width="%d" height="%d" viewBox="0 0 %d %d" role="img">'
            '<rect width="%d" height="%d" rx="2" fill="#f1f3f7"/>%s</svg>'
            % (width, height, width, height, width, height, ''.join(rects)))


def donut_svg(parts, label, sub, size=138, stroke=19):
    total = float(sum(v for v, _ in parts)) or 1.0
    r = (size - stroke) / 2.0
    c = 2 * math.pi * r
    mid = size / 2.0
    segs, offset = [], 0.0
    for value, colour in parts:
        if value <= 0:
            continue
        length = c * value / total
        segs.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="%s" stroke-width="%d" '
                    'stroke-dasharray="%.2f %.2f" stroke-dashoffset="%.2f" transform="rotate(-90 %.1f %.1f)"/>'
                    % (mid, mid, r, colour, stroke, length, c - length, -offset, mid, mid))
        offset += length
    return ('<svg width="%d" height="%d" viewBox="0 0 %d %d" role="img">'
            '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="#eef1f5" stroke-width="%d"/>%s'
            '<text x="50%%" y="50%%" text-anchor="middle" font-size="25" font-weight="750" fill="#141a24" '
            'font-family="Helvetica, Arial, sans-serif">%s</text>'
            '<text x="50%%" y="64%%" text-anchor="middle" font-size="10" fill="#6b7585" '
            'font-family="Helvetica, Arial, sans-serif">%s</text></svg>'
            % (size, size, size, size, mid, mid, r, stroke, ''.join(segs), esc(label), esc(sub)))


# ---------------------------------------------------------------- the document for one edition

class Doc:
    def __init__(self, data, edition, prev=None):
        self.d = data
        self.ed = edition
        self.prev = prev
        self.client = edition == 'client'
        self.areas = {a['id']: a for a in data.get('areas') or []}
        self.order = [a['id'] for a in data.get('areas') or []]
        self.items = [i for i in data.get('items') or [] if self.visible(i)]
        rules = data.get('rules') or {}
        self.public = [re.compile(p) for p in rules.get('public_link_patterns') or []]
        self.shots = set()  # screenshot files actually placed in this edition, for check.py to count

    def visible(self, item):
        if item.get('exclude'):
            return False
        return item.get('state') != 'internal' or self.ed == 'owner'

    def links(self, item):
        links = item.get('links') or []
        if not self.client:
            return links
        return [l for l in links if any(p.search(l.get('url', '')) for p in self.public)]

    def grouped(self, items):
        rank = {s: n for n, s in enumerate(LADDER)}
        out = []
        for aid in self.order:
            group = [i for i in items if i.get('area') == aid]
            if group:
                out.append((aid, sorted(group, key=lambda i: rank[i['state']])))
        return out

    def internal_by_area(self):
        counts = dict(self.d.get('internal_counts') or {})
        for i in self.d.get('items') or []:
            if not i.get('exclude') and i.get('state') == 'internal':
                counts[i['area']] = counts.get(i['area'], 0) + 1
        return counts


def sec(title, html_text, md_text, anchor=None):
    return dict(title=title, html=html_text, md=md_text, anchor=anchor)


def area_label(doc, aid):
    return doc.areas[aid].get('name', aid)


def item_sub(doc, item):
    """The line under a card title: engineering title and ids for insiders, readable links for all."""
    html_parts, md_parts = [], []
    if not doc.client:
        if item.get('engineering_title') and item['engineering_title'] != item['title']:
            html_parts.append(esc(item['engineering_title']))
            md_parts.append(item['engineering_title'])
        if item.get('task_ids'):
            html_parts.append(esc(', '.join(item['task_ids'])))
            md_parts.append(', '.join(item['task_ids']))
    links = doc.links(item)
    if links:
        html_parts.append(' '.join('<a href="%s">%s</a>' % (esc(l['url']), esc(l['label'])) for l in links))
        md_parts.append(' '.join('[%s](%s)' % (l['label'], l['url']) for l in links))
    return ' &middot; '.join(html_parts), ' · '.join(md_parts)


def figure(doc, shot):
    doc.shots.add(shot['file'])
    return ('<figure class="shot"><div class="frame"><div class="bar"><span class="dot"></span><span class="dot">'
            '</span><span class="dot"></span><span class="url">%s</span></div><img src="%s" alt="%s"></div>'
            '<figcaption>%s</figcaption></figure>'
            % (esc(shot.get('url', '')), esc(shot['file']), esc(shot.get('caption', '')), inline(shot.get('caption', ''))))


def labelled(label, body_html):
    return '<div class="label">%s</div><div>%s</div>' % (esc(label), body_html)


def card(doc, item):
    sub_html, sub_md = item_sub(doc, item)
    h = ['<article class="card" id="item-%s">' % esc(re.sub(r'[^A-Za-z0-9_-]', '-', item['id'])),
         '<div class="card-head"><div><h4>%s</h4>%s</div>%s</div>'
         % (inline(item['title']), '<div class="eng">%s</div>' % sub_html if sub_html else '', chip(item['state']))]
    left, right = [], []
    if item.get('what_changed'):
        left.append(labelled('What changed', inline(item['what_changed'])))
    if item.get('why'):
        left.append(labelled('Why it matters', inline(item['why'])))
    if item.get('where'):
        left.append(labelled('Where', inline(item['where'])))
    if item.get('access'):
        left.append(labelled('Access', inline(item['access'])))
    if item.get('not_yet'):
        left.append(labelled('Not yet', inline(item['not_yet'])))
    if item.get('steps'):
        right.append('<div class="label">How to see it</div><ol class="steps">%s</ol>'
                     % ''.join('<li>%s</li>' % inline(s) for s in item['steps']))
    if item.get('expect'):
        right.append('<div class="label">You should see</div><div class="expect">%s</div>' % inline(item['expect']))
    h.append('<div class="cols"><div>%s</div><div>%s</div></div>' % (''.join(left), ''.join(right)))
    for shot in item.get('screenshots') or []:
        h.append(figure(doc, shot))
    if item.get('screen_note') and not item.get('screenshots'):
        h.append('<div class="placeholder"><strong>Screen not captured.</strong> %s</div>' % inline(item['screen_note']))
    if not doc.client and item.get('evidence'):
        h.append(labelled('Evidence', '<div class="evidence">%s</div>' % esc(item['evidence'])))
    h.append('</article>')

    m = ['#### %s %s' % (item['title'], md_chip(item['state'])), '']
    if sub_md:
        m += ['_%s_' % sub_md, '']
    for label, key in (('What changed', 'what_changed'), ('Why it matters', 'why'), ('Where', 'where')):
        if item.get(key):
            m += ['**%s.** %s' % (label, item[key]), '']
    if item.get('steps'):
        m += ['**How to see it.**', ''] + ['%d. %s' % (n + 1, s) for n, s in enumerate(item['steps'])] + ['']
    if item.get('expect'):
        m += ['**You should see.** %s' % item['expect'], '']
    for label, key in (('Access', 'access'), ('Not yet', 'not_yet')):
        if item.get(key):
            m += ['**%s.** %s' % (label, item[key]), '']
    for shot in item.get('screenshots') or []:
        m += ['![%s](%s)' % (shot.get('caption', ''), shot['file']), '']
        if shot.get('caption'):
            m += ['_%s_' % shot['caption'], '']
    if item.get('screen_note') and not item.get('screenshots'):
        m += ['> Screen not captured. %s' % item['screen_note'], '']
    if not doc.client and item.get('evidence'):
        m += ['<sub>Evidence: %s</sub>' % item['evidence'].replace('\n', ' '), '']
    return '\n'.join(h), m


def compact(doc, item, show_area=False):
    sub_html, sub_md = item_sub(doc, item)
    if show_area:
        sub_html = esc(area_label(doc, item['area'])) + (' &middot; ' + sub_html if sub_html else '')
        sub_md = area_label(doc, item['area']) + (' · ' + sub_md if sub_md else '')
    h = ['<article class="card compact"><div class="card-head"><div><h4>%s</h4>%s</div>%s</div>'
         % (inline(item['title']), '<div class="eng">%s</div>' % sub_html if sub_html else '', chip(item['state']))]
    if item.get('what_changed'):
        h.append('<p style="margin-top:4px">%s</p>' % inline(item['what_changed']))
    if item.get('test_later'):
        h.append('<div class="eng"><strong>Test then at:</strong> %s</div>' % inline(item['test_later']))
    if not doc.client and item.get('evidence'):
        h.append('<div class="evidence" style="margin-top:4px">%s</div>' % esc(item['evidence']))
    h.append('</article>')
    m = ['- **%s** %s%s' % (item['title'], md_chip(item['state']), ' (%s)' % sub_md if sub_md else '')]
    if item.get('what_changed'):
        m.append('  %s' % item['what_changed'])
    if item.get('test_later'):
        m.append('  Test then at: %s' % item['test_later'])
    return ''.join(h), m


def table(headers, rows, numeric=(), cls=''):
    head = ''.join('<th%s>%s</th>' % (' class="n"' if n in numeric else '', esc(h)) for n, h in enumerate(headers))
    body = ''.join('<tr>%s</tr>' % ''.join('<td%s>%s</td>' % (' class="n"' if n in numeric else '', c)
                                            for n, c in enumerate(r)) for r in rows)
    return '<div class="scroll"><table%s><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>' % (' class="%s"' % cls if cls else '', head, body)


def md_table(headers, rows):
    out = ['| %s |' % ' | '.join(cell(h) for h in headers), '|%s|' % '|'.join('---' for _ in headers)]
    out += ['| %s |' % ' | '.join(cell(c) for c in r) for r in rows]
    return out


# ---------------------------------------------------------------- sections

def s_read_first(doc):
    notes = doc.d.get('read_first') or []
    if not notes:
        return None
    return sec('Read this first', ''.join('<div class="notice">%s</div>' % inline(n) for n in notes),
               '\n\n'.join('> %s' % n for n in notes))


def s_glance(doc):
    items = [i for i in doc.items if i['state'] != 'internal']
    internal = doc.internal_by_area()
    states = [s for s in LADDER[:-1] if any(i['state'] == s for i in items)]
    show_internal = sum(internal.values()) > 0
    rows = []
    for aid in doc.order:
        counts = [sum(1 for i in items if i['area'] == aid and i['state'] == s) for s in states]
        n_int = internal.get(aid, 0)
        total = sum(counts) + n_int
        if total:
            rows.append((aid, counts, n_int, total))
    if not rows:
        return None
    peak = max(r[3] for r in rows)
    headers = ['Area'] + [STATE[s]['short'] for s in states] + (['Internal'] if show_internal else []) + ['Total', '']
    numeric = tuple(range(1, len(headers) - 1))
    body, md_rows = [], []
    for aid, counts, n_int, total in rows:
        segs = [(c, STATE[s]['bar']) for c, s in zip(counts, states)] + [(n_int, STATE['internal']['bar'])]
        body.append([esc(area_label(doc, aid))] + [str(c) if c else '&middot;' for c in counts]
                    + ([str(n_int) if n_int else '&middot;'] if show_internal else [])
                    + ['<strong>%d</strong>' % total, stack_svg(segs, total, peak)])
        md_rows.append([area_label(doc, aid)] + [str(c) for c in counts] + ([str(n_int)] if show_internal else []) + [str(total), ''])
    sums = [sum(r[1][n] for r in rows) for n in range(len(states))]
    grand = sum(r[3] for r in rows)
    total_row = ['Total'] + [str(s) for s in sums] + ([str(sum(r[2] for r in rows))] if show_internal else []) + [str(grand), '']
    body_html = table(headers, body, numeric).replace('</tbody>', '<tr class="total">%s</tr></tbody>'
                                                      % ''.join('<td%s>%s</td>' % (' class="n"' if 0 < n < len(total_row) - 1 else '', c)
                                                                for n, c in enumerate(total_row)))
    since = when((doc.d.get('as_of') or {}).get('since'), False)
    lede = 'Every change%s, by area and by what proves it.' % (' since %s' % since if since else '')
    md = [lede, ''] + md_table(headers[:-1], [r[:-1] for r in md_rows] + [total_row[:-1]])
    return sec('At a glance', '<p class="lede">%s</p>%s' % (esc(lede), body_html), '\n'.join(md))


def s_test_now(doc):
    items = [i for i in doc.items if i['state'] in TEST_NOW]
    if doc.prev is not None:
        rank = {s: n for n, s in enumerate(LADDER)}
        before = {i['id']: i['state'] for i in doc.prev.get('items') or [] if not i.get('exclude')}
        items = [i for i in items if i['id'] not in before or rank[i['state']] < rank[before[i['id']]]]
    if not items:
        return None
    n_seen = sum(1 for i in items if i['state'] == 'seen-live')
    lede = '%s you can check today: %d seen live on the host, and %d in the running build that need a sign-in or a device to see.' % (
        plural(len(items), 'change', 'changes'), n_seen, len(items) - n_seen)
    h, m = ['<p class="lede">%s</p>' % esc(lede)], [lede, '']
    for aid, group in doc.grouped(items):
        a = doc.areas[aid]
        env = ' &middot; '.join(x for x in (esc(a.get('env', '')), inline(a.get('url', ''))) if x)
        h.append('<div class="area-head"><h3>%s</h3><div class="env">%s%s%d to test</div></div>'
                 % (esc(a.get('name', aid)), env, ' &middot; ' if env else '', len(group)))
        m += ['### %s%s' % (a.get('name', aid), ', %s' % a['url'] if a.get('url') else ''), '']
        if a.get('note'):
            h.append('<p class="area-note">%s</p>' % inline(a['note']))
            m += [a['note'], '']
        for item in group:
            ch, cm = card(doc, item)
            h.append(ch)
            if KEEP not in h:
                h.append(KEEP)
            m += cm
    return sec('Test now', '\n'.join(h), '\n'.join(m))


def s_checklist(doc):
    items = [i for i in doc.items if i['state'] in TEST_NOW]
    if len(items) < 2:
        return None
    rows, md = [], []
    for aid, group in doc.grouped(items):
        for item in group:
            where = item.get('where', '')
            found = URL.search(where)
            address = found.group(0) if found else where
            rows.append(['<span class="box"></span>',
                         '<strong>%s</strong><div class="sub">%s</div>' % (inline(item['title']), esc(area_label(doc, aid))),
                         inline(address), inline(item.get('access', '')), chip(item['state'])])
            md.append('- [ ] **%s** (%s): %s. Access: %s' % (item['title'], area_label(doc, aid), address, item.get('access', '')))
    lede = 'One line per change you can test today, in the order the cards follow. Tick each as you go.'
    return sec('Testing checklist', '<p class="lede">%s</p>%s' % (esc(lede), table(['', 'Change', 'Where', 'Access', 'State'], rows, cls='checklist')),
               '\n'.join([lede, ''] + md))


def s_coming(doc):
    items = [i for i in doc.items if i['state'] in LATER]
    if not items:
        return None
    h = ['<p class="lede">Finished work that a reader cannot see yet, and what makes it visible.</p>']
    m = ['Finished work that a reader cannot see yet, and what makes it visible.', '']
    for state in LATER:
        group = [i for i in items if i['state'] == state]
        if not group:
            continue
        h.append('<h3 class="sub">%s %s</h3><p class="lede">%s</p>'
                 % (esc(LATER_HEADING[state]), chip(state), esc(STATE[state]['meaning'])))
        m += ['### %s (%d)' % (LATER_HEADING[state], len(group)), '', STATE[state]['meaning'], '']
        for aid, g in doc.grouped(group):
            for item in g:
                ch, cm = compact(doc, item, show_area=True)
                h.append(ch)
                if KEEP not in h:
                    h.append(KEEP)
                m += cm
        m.append('')
    return sec('Coming next', '\n'.join(h), '\n'.join(m))


def s_internal(doc):
    counts = doc.internal_by_area()
    total = sum(counts.values())
    if not total:
        return None
    parts = ['%s %d' % (area_label(doc, a), counts[a]) for a in doc.order if counts.get(a)]
    text = ('%s with nothing to see: tests, build checks, documentation and tooling. By area: %s.'
            % (plural(total, 'change', 'changes'), ', '.join(parts)))
    if doc.ed == 'owner':
        text += ' Each listed one appears in the item index.'
    return sec('Internal changes', '<p>%s</p>' % esc(text), text)


def s_landed(doc):
    items = [i for i in doc.items if i['state'] != 'internal']
    if not items:
        return None
    h, m = [], []
    for aid, group in doc.grouped(items):
        h.append('<div class="area-head"><h3>%s</h3><div class="env">%s</div></div>' % (esc(area_label(doc, aid)), plural(len(group), 'change', 'changes')))
        rows = []
        m += ['### %s' % area_label(doc, aid), '']
        for item in group:
            sub_html, sub_md = item_sub(doc, item)
            proof = '' if doc.client or not item.get('evidence') else '<div class="evidence" style="margin-top:3px">%s</div>' % esc(
                item['evidence'] if len(item['evidence']) <= 220 else item['evidence'][:217] + '...')
            rows.append(['<strong>%s</strong>%s%s%s' % (inline(item['title']),
                                                      '<div class="sub">%s</div>' % inline(item.get('what_changed', '')) if item.get('what_changed') else '',
                                                      '<div class="eng">%s</div>' % sub_html if sub_html else '', proof),
                         chip(item['state'])])
            m.append('- **%s** %s%s' % (item['title'], md_chip(item['state']), ' (%s)' % sub_md if sub_md else ''))
        h.append(table(['Change', 'State'], rows))
        m.append('')
    return sec('What landed', '\n'.join(h), '\n'.join(m))


def s_plan(doc):
    p = doc.d.get('plan')
    if not p:
        return None
    done, nn, op = p.get('done', 0), p.get('not_needed', 0), p.get('open', 0)
    total = p.get('total', done + nn + op)
    pct = '%d%%' % round(100.0 * done / total) if total else '0%'
    legend = ''.join('<span class="swatch" style="background:%s"></span><span>%s</span><strong>%d</strong>' % (c, esc(l), v)
                     for l, v, c in (('Done', done, '#2e9e5b'), ('Not needed', nn, '#c9ced6'), ('Open', op, '#2f6fd0')))
    legend += '<span></span><span style="color:#6b7585">Total tasks</span><strong>%d</strong>' % total
    h = ['<div class="plan-top">%s<div class="plan-legend">%s</div></div>'
         % (donut_svg([(done, '#2e9e5b'), (nn, '#c9ced6'), (op, '#2f6fd0')], pct, 'done'), legend)]
    h.append(KEEP)
    m = ['**%d of %d tasks done** (%s), %d not needed, %d open.' % (done, total, pct, nn, op), '']
    kinds = {k['kind']: k for k in p.get('open_by_kind') or []}
    present = [k for k in KINDS if kinds.get(k, {}).get('count')]
    if present:
        peak = max(kinds[k]['count'] for k in present)
        rows = []
        h.append('<h3 class="sub">Why the %d open tasks are open</h3><div class="kinds">' % op)
        m += ['### Why the %d open tasks are open' % op, '']
        for k in present:
            entry = kinds[k]
            label = entry.get('label') or KIND[k]['label']
            h.append('<div class="kind-row"><div>%s</div><div>%s</div><div class="kn">%d</div></div>'
                     % (esc(label), bar_svg(entry['count'], peak, KIND[k]['bar']), entry['count']))
            if entry.get('note'):
                h.append('<div class="kind-note">%s</div>' % inline(entry['note']))
            rows.append([label, str(entry['count']), entry.get('note', '')])
        h.append('</div>')
        m += md_table(['Kind', 'Tasks', 'Note'], rows) + ['']
    if p.get('by_area'):
        areas = p['by_area']
        peak = max((a.get('done', 0) + a.get('open', 0)) for a in areas) or 1
        title = 'By area' + (', %s' % p['by_area_scope'] if p.get('by_area_scope') else '')
        rows = [[esc(a['name']), str(a.get('done', 0)), str(a.get('open', 0)),
                 stack_svg([(a.get('done', 0), '#2e9e5b'), (a.get('open', 0), '#2f6fd0')],
                           a.get('done', 0) + a.get('open', 0), peak, width=190)] for a in areas]
        h.append('<h3 class="sub">%s</h3>%s' % (esc(title), table(['Area', 'Done', 'Open', ''], rows, (1, 2))))
        m += ['### %s' % title, ''] + md_table(['Area', 'Done', 'Open'], [[a['name'], a.get('done', 0), a.get('open', 0)] for a in areas]) + ['']
    if doc.d.get('defaults'):
        h.append('<h3 class="sub">Decided, and in force</h3><ul class="defaults">%s</ul>'
                 % ''.join('<li>%s</li>' % inline(x) for x in doc.d['defaults']))
        m += ['### Decided, and in force', ''] + ['- %s' % x for x in doc.d['defaults']] + ['']
    return sec('Where the plan stands', '\n'.join(h), '\n'.join(m))


def s_moved(doc):
    prev = doc.prev
    if prev is None:
        return None
    rank = {s: n for n, s in enumerate(LADDER)}
    before = {i['id']: i for i in prev.get('items') or [] if not i.get('exclude')}
    cur = [i for i in doc.items if i['state'] != 'internal']
    new = [i for i in cur if i['id'] not in before]
    up = [i for i in cur if i['id'] in before and rank[i['state']] < rank[before[i['id']]['state']]]
    down = [i for i in cur if i['id'] in before and rank[i['state']] > rank[before[i['id']]['state']]]
    then = when((prev.get('as_of') or {}).get('read_at'))
    lede = 'Since the report read at %s: %s, %d moved closer to a reader, %d graded down.' % (
        then, plural(len(new), 'new change', 'new changes'), len(up), len(down))
    h, m = ['<p class="lede">%s</p>' % esc(lede)], [lede, '']
    pp, cp = prev.get('plan') or {}, doc.d.get('plan') or {}
    if pp and cp:
        pk = {k['kind']: k.get('count', 0) for k in pp.get('open_by_kind') or []}
        ck = {k['kind']: k.get('count', 0) for k in cp.get('open_by_kind') or []}
        rows = [(label, pp.get(key, 0), cp.get(key, 0)) for label, key in (('Done', 'done'), ('Open', 'open'), ('Not needed', 'not_needed'))]
        rows += [(KIND[k]['label'], pk.get(k, 0), ck.get(k, 0)) for k in KINDS if pk.get(k) or ck.get(k)]
        fmt = [[esc(l), str(a), str(b), ('+%d' % (b - a)) if b > a else str(b - a)] for l, a, b in rows]
        h.append(table(['Measure', 'Then', 'Now', 'Change'], fmt, (1, 2, 3)))
        m += md_table(['Measure', 'Then', 'Now', 'Change'], [[l, a, b, b - a] for l, a, b in rows]) + ['']
    for heading, group, note in (('New since then', new, None), ('Moved closer to a reader', up, 'was'), ('Graded down', down, 'was')):
        if not group:
            continue
        h.append('<h3 class="sub">%s</h3>' % esc(heading))
        m += ['### %s' % heading, '']
        for item in group:
            ch, cm = compact(doc, item, show_area=True)
            if note:
                ch = ch.replace('</article>', '<div class="eng">Previously: %s</div></article>' % esc(STATE[before[item['id']]['state']]['label']))
                cm.append('  Previously: %s' % STATE[before[item['id']]['state']]['label'])
            h.append(ch)
            m += cm
        m.append('')
    return sec('What moved', '\n'.join(h), '\n'.join(m))


def s_asks(doc):
    asks = doc.d.get('asks') or []
    if not asks:
        return None
    rows = [[inline(a.get('ask')), inline(a.get('who')), inline(a.get('why')), inline(a.get('blocks'))] for a in asks]
    md = md_table(['Ask', 'Who', 'Why', 'What it unblocks'], [[a.get('ask'), a.get('who'), a.get('why'), a.get('blocks')] for a in asks])
    return sec('What we need from you', table(['Ask', 'Who', 'Why', 'What it unblocks'], rows), '\n'.join(md))


def s_acts(doc):
    acts = doc.d.get('acts_needing_go') or []
    if doc.ed != 'owner' or not acts:
        return None
    rows = [[inline(a.get('act')), inline(a.get('effect')), inline(a.get('reversible'))] for a in acts]
    md = md_table(['Act', 'Effect', 'Reversible'], [[a.get('act'), a.get('effect'), a.get('reversible')] for a in acts])
    return sec('Acts waiting for your go', table(['Act', 'Effect', 'Reversible'], rows), '\n'.join(md))


def s_risks(doc):
    risks = [r for r in doc.d.get('risks') or [] if not doc.client or r.get('client')]
    if not risks:
        return None
    rows = [[inline(r.get('risk')), inline(r.get('effect')), inline(r.get('mitigation'))] for r in risks]
    md = md_table(['Risk', 'Effect', 'What we do about it'], [[r.get('risk'), r.get('effect'), r.get('mitigation')] for r in risks])
    return sec('Risks', table(['Risk', 'Effect', 'What we do about it'], rows), '\n'.join(md))


def s_next(doc):
    steps = doc.d.get('next') or []
    if not steps:
        return None
    return sec('Next', '<ol class="next">%s</ol>' % ''.join('<li>%s</li>' % inline(s) for s in steps),
               '\n'.join('%d. %s' % (n + 1, s) for n, s in enumerate(steps)))


def s_glossary(doc):
    terms = doc.d.get('glossary') or []
    if not terms:
        return None
    rows = [['<strong>%s</strong>' % esc(t.get('term')), inline(t.get('meaning'))] for t in terms]
    return sec('Glossary', table(['Term', 'Meaning'], rows),
               '\n'.join(md_table(['Term', 'Meaning'], [[t.get('term'), t.get('meaning')] for t in terms])))


def s_index(doc):
    if doc.client or not doc.items:
        return None
    rows, md_rows = [], []
    for aid, group in doc.grouped(doc.items):
        for item in group:
            links = doc.links(item)
            rows.append(['<span class="nowrap">%s</span>' % esc(item['id']), inline(item['title']), esc(area_label(doc, aid)), chip(item['state']),
                         ' '.join('<a href="%s">%s</a>' % (esc(l['url']), esc(l['label'])) for l in links)])
            md_rows.append([item['id'], item['title'], area_label(doc, aid), STATE[item['state']]['label'],
                            ' '.join('[%s](%s)' % (l['label'], l['url']) for l in links)])
    return sec('Item index', table(['Id', 'Item', 'Area', 'State', 'Links'], rows),
               '\n'.join(md_table(['Id', 'Item', 'Area', 'State', 'Links'], md_rows)))


def s_about(doc):
    if doc.client:
        return None
    a = doc.d.get('as_of') or {}
    rows = [('Read at', when(a.get('read_at'))), ('Baseline', when(a.get('since'), False)),
            ('Plan reference', a.get('plan_ref', '')), ('Edition', EDITION_LABEL[doc.ed])]
    rows = [(k, v) for k, v in rows if v]
    h = table(['', ''], [[esc(k), inline(v)] for k, v in rows])
    m = md_table(['', ''], rows)
    if a.get('sources'):
        h += '<div class="label">Sources read</div><ul>%s</ul>' % ''.join('<li>%s</li>' % inline(s) for s in a['sources'])
        m += ['', '**Sources read**', ''] + ['- %s' % s for s in a['sources']]
    return sec('About this report', h, '\n'.join(m))


SECTIONS = {'read_first': s_read_first, 'glance': s_glance, 'checklist': s_checklist, 'test_now': s_test_now, 'coming': s_coming,
            'internal': s_internal, 'landed': s_landed, 'plan': s_plan, 'moved': s_moved, 'asks': s_asks,
            'acts': s_acts, 'risks': s_risks, 'next': s_next, 'glossary': s_glossary, 'index': s_index,
            'about': s_about}


def build(doc):
    out = []
    for key in ORDER[doc.d['kind']]:
        s = SECTIONS[key](doc)
        if s:
            s['key'] = key
            out.append(s)
    for n, s in enumerate(out, 1):
        s['num'] = n
        s['anchor'] = 'sec-%s' % s['key']
    return out


# ---------------------------------------------------------------- assembly

def cover_rows(doc):
    d, a = doc.d, doc.d.get('as_of') or {}
    rows = [('Prepared for', per_edition(d.get('prepared_for'), doc.ed)),
            ('Prepared by', per_edition(d.get('prepared_by'), doc.ed)),
            ('As of', when(a.get('read_at'))),
            ('Covers', 'Changes since %s' % when(a.get('since'), False) if a.get('since') else '')]
    if not doc.client:
        rows.append(('Plan reference', a.get('plan_ref', '')))
    return [(k, v) for k, v in rows if v]


def legend_states(doc):
    present = [s for s in LADDER if any(i['state'] == s for i in doc.items)]
    if 'internal' not in present and sum(doc.internal_by_area().values()):
        present.append('internal')
    return present


def page_css(doc):
    def q(s):
        return '"%s"' % str(s).replace('\\', '\\\\').replace('"', '\\"')
    title = doc.d['title'] if len(doc.d['title']) <= 70 else doc.d['title'][:67] + '...'
    top_right = per_edition(doc.d.get('prepared_for'), doc.ed)
    top_right = ('Prepared for %s' % top_right) if top_right else ''
    if not doc.client:
        top_right = (top_right + '  ·  ' if top_right else '') + EDITION_LABEL[doc.ed]
    foot = '%s  ·  As of %s' % (title, when((doc.d.get('as_of') or {}).get('read_at'), False))
    font = 'font:500 7.3pt/1.2 Helvetica,Arial,sans-serif;color:#8a93a1'
    return ('@page{size:A4;margin:17mm 15mm 17mm 15mm;'
            '@top-left{content:%s;%s;letter-spacing:.12em}@top-right{content:%s;%s}'
            '@bottom-left{content:%s;%s}@bottom-right{content:"Page " counter(page) " of " counter(pages);%s}}'
            '@page:first{@top-left{content:none}@top-right{content:none}@bottom-left{content:none}@bottom-right{content:none}}'
            % (q(KIND_TITLE[doc.d['kind']].upper()), font, q(top_right), font, q(foot), font, font))


def section_html(s):
    """The heading travels with the first block its section marks, so no heading ends a page alone."""
    head = '<h2><span class="num">%d</span>%s</h2>' % (s['num'], esc(s['title']))
    if KEEP in s['html']:
        first, rest = s['html'].split(KEEP, 1)
        return '<section class="sec" id="%s"><div class="keep">%s%s</div>%s</section>' % (s['anchor'], head, first, rest.replace(KEEP, ''))
    return '<section class="sec" id="%s">%s%s</section>' % (s['anchor'], head, s['html'])


def to_html(doc, sections, css):
    d = doc.d
    eyebrow = KIND_TITLE[d['kind']] if doc.client else '%s &middot; %s' % (KIND_TITLE[d['kind']], EDITION_LABEL[doc.ed])
    meta = ''.join('<dt>%s</dt><dd>%s</dd>' % (esc(k), inline(v)) for k, v in cover_rows(doc))
    kpis = ''.join('<div class="kpi"><div class="v">%s</div><div class="l">%s</div><div class="n">%s</div></div>'
                   % (esc(k.get('value')), esc(k.get('label')), esc(k.get('note', ''))) for k in (d.get('kpis') or [])[:4])
    legend = ''.join('<div class="row"><div>%s</div><div>%s</div></div>' % (chip(s), esc(STATE[s]['meaning'])) for s in legend_states(doc))
    toc = ''.join('<li><a href="#%s">%s</a></li>' % (s['anchor'], esc(s['title'])) for s in sections)
    body = ''.join(section_html(s) for s in sections)
    signature = per_edition(d.get('signature'), doc.ed)
    return ('<!doctype html><html lang="%s"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>%s</title><style>%s\n%s</style></head><body><main class="doc">'
            '<header class="cover"><div class="band"></div><div class="eyebrow">%s</div><h1>%s</h1>%s'
            '<dl class="meta">%s</dl>%s<p class="standfirst">%s</p>%s</header>'
            '<nav class="toc"><h4>Contents</h4><ol>%s</ol></nav>%s%s</main></body></html>'
            % (esc(d.get('locale', 'en')), esc(d['title']), css, page_css(doc), eyebrow, esc(d['title']),
               '<p class="subtitle">%s</p>' % esc(d['subtitle']) if d.get('subtitle') else '', meta,
               '<section class="kpis">%s</section>' % kpis if kpis else '', inline(d.get('standfirst', '')),
               '<section class="legend"><h4>How to read this report</h4>%s</section>' % legend if legend else '',
               toc, body, '<p class="signoff">%s</p>' % esc(signature) if signature else ''))


def to_md(doc, sections):
    d = doc.d
    kind = KIND_TITLE[d['kind']] if doc.client else '%s, %s' % (KIND_TITLE[d['kind']], EDITION_LABEL[doc.ed].lower())
    lines = ['# %s' % d['title'], '']
    if d.get('subtitle'):
        lines += ['_%s_' % d['subtitle'], '']
    lines += ['**%s**' % kind, ''] + md_table(['', ''], cover_rows(doc)) + ['', '> %s' % d.get('standfirst', ''), '']
    if d.get('kpis'):
        lines += md_table(['Figure', 'Value', 'Note'], [[k.get('label'), k.get('value'), k.get('note', '')] for k in d['kpis'][:4]]) + ['']
    states = legend_states(doc)
    if states:
        lines += ['**How to read this report.**', ''] + ['- %s %s' % (md_chip(s), STATE[s]['meaning']) for s in states] + ['']
    lines += ['## Contents', ''] + ['%d. [%s](#%s)' % (s['num'], s['title'], gfm_anchor('%d %s' % (s['num'], s['title']))) for s in sections] + ['']
    for s in sections:
        lines += ['## %d %s' % (s['num'], s['title']), '', s['md'], '']
    signature = per_edition(d.get('signature'), doc.ed)
    if signature:
        lines += [signature, '']
    return '\n'.join(lines).rstrip() + '\n'


def worst(a, b):
    order = {0: 0, 2: 1, 1: 2}
    return a if order[a] >= order[b] else b


def main(argv=None):
    ap = argparse.ArgumentParser(description='Render delivery.json into Markdown, HTML and PDF per edition.')
    ap.add_argument('source')
    ap.add_argument('--out', required=True, help='output directory; screenshot paths resolve against it')
    ap.add_argument('--edition', action='append', choices=EDITIONS, help='repeatable; default: the source\'s editions')
    ap.add_argument('--previous', help='an earlier delivery.json, for a progress report')
    ap.add_argument('--no-pdf', action='store_true')
    ap.add_argument('--browser', help='path to a headless-capable browser; default: discovered')
    args = ap.parse_args(argv)

    try:
        raw, data = prepare(args.source)
        prev = prepare(args.previous)[1] if args.previous else None
    except SourceError as exc:
        print('FAIL        source: %s' % exc)
        return 1
    if data['kind'] == 'progress' and prev is None:
        print('FAIL        source: a progress report needs --previous, or its movement would be recalled rather than computed')
        return 1

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    css = CSS_PATH.read_text(encoding='utf-8')
    editions = args.edition or data.get('editions') or list(EDITIONS)
    browser = None if args.no_pdf else _browser.find(args.browser)
    status = 0
    manifest = {'schema': 'osteon.delivery-render/1', 'source_sha256': sha256(args.source),
                'previous_sha256': sha256(args.previous) if args.previous else None,
                'rendered_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
                'browser': _browser.version(browser) if browser else None, 'editions': {}}
    for ed in editions:
        doc = Doc(data, ed, prev)
        sections = build(doc)
        stem = '%s-%s' % (slug(data), ed)
        md_path, html_path, pdf_path = out / (stem + '.md'), out / (stem + '.html'), out / (stem + '.pdf')
        md_path.write_text(to_md(doc, sections), encoding='utf-8')
        html_path.write_text(to_html(doc, sections, css), encoding='utf-8')
        entry = {'md': md_path.name, 'md_sha256': sha256(md_path), 'html': html_path.name,
                 'html_sha256': sha256(html_path), 'pdf': None, 'pdf_sha256': None, 'pages': None,
                 'items': len(doc.items), 'screenshots': sorted(doc.shots)}
        if browser:
            ok, code, tail = _browser.print_pdf(browser, html_path, pdf_path)
            if ok:
                entry.update(pdf=pdf_path.name, pdf_sha256=sha256(pdf_path), pages=pdf_pages(pdf_path))
                print('PASS        %s: %s, %s, %s (%s pages)' % (ed, md_path.name, html_path.name, pdf_path.name, entry['pages']))
            else:
                status = worst(status, 1)
                print('FAIL        %s: PDF not printed (exit %s): %s' % (ed, code, tail.strip()[-300:]))
        else:
            status = worst(status, 2)
            why = '--no-pdf given' if args.no_pdf else 'no headless browser found; set DELIVERY_BROWSER or pass --browser'
            print('NEEDS-INFO  %s: %s and %s written, no PDF (%s)' % (ed, md_path.name, html_path.name, why))
        manifest['editions'][ed] = entry
    (out / manifest_name(data)).write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return status


if __name__ == '__main__':
    sys.exit(main())
