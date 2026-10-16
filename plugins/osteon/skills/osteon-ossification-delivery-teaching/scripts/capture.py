#!/usr/bin/env python3
"""Capture screenshots in a throwaway headless browser profile, signed out.

  capture.py --out DIR --name NAME --url URL [--width 1440] [--height 900] [--wait 4000] [--scale 1]
  capture.py --out DIR --list shots.json     # [{"name", "url", "width", "height", "wait", "scale"}]

Trims the empty space below short content unless "trim": false or --no-trim. Writes DIR/shots/<name>.png and merges a row per capture into DIR/shots/captures.json. Captures run
one at a time. Per capture: PASS; FAIL when nothing was written or the address was refused;
NEEDS-INFO when the image is blank or near-uniform, or when Pillow is absent so blankness cannot be
judged. Exit 0 all PASS, 1 any FAIL, 2 NEEDS-INFO with no FAIL.

Refuses an address that carries a credential in its user part, its query or its fragment. Never
uses, reads or writes a person's own browser profile.
"""
import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qsl, urlsplit

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True  # a bytecode cache would carry this checkout's absolute path
sys.path.insert(0, str(HERE))
import _browser  # noqa: E402

NAME = re.compile(r'^[a-z0-9][a-z0-9._-]{0,80}$')
SECRET_KEY = re.compile(r'(?i)^(token|access_token|id_token|refresh_token|code|key|api_key|apikey|secret|'
                        r'password|pass|pwd|signature|sig|auth|session|jwt|x-amz-signature|x-amz-credential)$')


def refused(url):
    parts = urlsplit(url)
    if parts.scheme not in ('http', 'https', 'file'):
        return 'scheme %r is not http, https or file' % parts.scheme
    if parts.username or parts.password or '@' in parts.netloc:
        return 'the address carries a credential in its user part'
    for key, _ in parse_qsl(parts.query, keep_blank_values=True):
        if SECRET_KEY.match(key):
            return 'the query parameter %r looks like a credential' % key
    if re.search(r'(?i)(access_token|id_token|refresh_token)=', parts.fragment or ''):
        return 'the fragment carries a token'
    return None


def blank(path):
    """True when near-uniform, False when not, None when Pillow is absent."""
    try:
        from PIL import Image
    except ImportError:
        return None
    with Image.open(path) as im:
        lo, hi = im.convert('L').resize((96, 60)).getextrema()
    return (hi - lo) < 10


def trim(path, margin, min_height):
    """Crop the empty space below the content, so a short response does not print as a tall blank frame."""
    try:
        from PIL import Image, ImageChops
    except ImportError:
        return None
    with Image.open(path) as im:
        rgb = im.convert('RGB')
    ground = Image.new('RGB', rgb.size, rgb.getpixel((rgb.width - 1, rgb.height - 1)))
    box = ImageChops.difference(rgb, ground).convert('L').point(lambda v: 255 if v > 12 else 0).getbbox()
    if not box:
        return None
    bottom = min(rgb.height, max(box[3] + margin, min_height))
    if bottom >= rgb.height - 8:
        return None
    rgb.crop((0, 0, rgb.width, bottom)).save(path)
    return rgb.height, bottom


def capture(browser, shot, shots_dir):
    name, url = str(shot.get('name', '')), str(shot.get('url', ''))
    row = {'name': name, 'url': url.replace(str(Path.home()), '~')}  # the home path names the account
    if not NAME.match(name):
        row.update(verdict='FAIL', note='name must be lower-case letters, digits, dot, dash or underscore')
        return row
    why = refused(url)
    if why:
        row.update(verdict='FAIL', note='refused: ' + why)
        return row
    width, height = int(shot.get('width', 1440)), int(shot.get('height', 900))
    wait, scale = int(shot.get('wait', 4000)), float(shot.get('scale', 1))
    path = shots_dir / (name + '.png')
    if path.exists():
        path.unlink()
    code, tail = _browser.run(browser, ['--window-size=%d,%d' % (width, height),
                                        '--force-device-scale-factor=%g' % scale,
                                        '--virtual-time-budget=%d' % wait,
                                        '--screenshot=%s' % path, url],
                              timeout=max(60, wait // 1000 + 60))
    row.update(file='shots/%s' % path.name, width=width, height=height, scale=scale, wait_ms=wait,
               captured_at=datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'), exit=code)
    if not path.exists() or path.stat().st_size == 0:
        row.update(verdict='FAIL', note='no image written (exit %s): %s' % (code, tail.strip()[-200:]))
        return row
    judged = blank(path)
    if judged is None:
        row.update(verdict='NEEDS-INFO', note='Pillow is absent, so blankness was not judged; look at the image')
    elif judged:
        row.update(verdict='NEEDS-INFO', note='blank or near-uniform image; the page may need a longer --wait, or a sign-in')
    else:
        row.update(verdict='PASS', note='')
        if shot.get('trim', True):
            cut = trim(path, margin=int(24 * scale), min_height=int(180 * scale))
            if cut:
                row['trimmed'] = {'from_height': cut[0], 'to_height': cut[1]}
    data = path.read_bytes()
    row.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
    return row


def main(argv=None):
    ap = argparse.ArgumentParser(description='Capture signed-out screenshots in a throwaway headless profile.')
    ap.add_argument('--out', required=True)
    ap.add_argument('--list', help='JSON list of captures')
    ap.add_argument('--name')
    ap.add_argument('--url')
    ap.add_argument('--width', type=int, default=1440)
    ap.add_argument('--height', type=int, default=900)
    ap.add_argument('--wait', type=int, default=4000, help='virtual milliseconds to let the page settle')
    ap.add_argument('--scale', type=float, default=1)
    ap.add_argument('--no-trim', action='store_true', help='keep the empty space below the content')
    ap.add_argument('--browser')
    args = ap.parse_args(argv)

    if args.list:
        shots = json.loads(Path(args.list).read_text(encoding='utf-8'))
    elif args.name and args.url:
        shots = [dict(name=args.name, url=args.url, width=args.width, height=args.height, wait=args.wait, scale=args.scale,
                      trim=not args.no_trim)]
    else:
        ap.error('give --list, or both --name and --url')
    names = [s.get('name') for s in shots]
    dups = sorted({n for n in names if names.count(n) > 1})
    if dups:
        print('FAIL        duplicate capture names %s; one would overwrite the other' % dups)
        return 1

    browser = _browser.find(args.browser)
    if not browser:
        print('NEEDS-INFO  no headless browser found; set DELIVERY_BROWSER or pass --browser')
        return 2
    shots_dir = Path(args.out) / 'shots'
    shots_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = shots_dir / 'captures.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {'captures': []}
    manifest['browser'] = _browser.version(browser)
    status = 0
    for shot in shots:
        row = capture(browser, shot, shots_dir)
        manifest['captures'] = [c for c in manifest['captures'] if c.get('name') != row['name']] + [row]
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        print('%-11s %s %s%s' % (row['verdict'], row['name'], row['url'], ' (%s)' % row['note'] if row.get('note') else ''))
        if row['verdict'] == 'FAIL':
            status = 1
        elif row['verdict'] == 'NEEDS-INFO' and status == 0:
            status = 2
    return status


if __name__ == '__main__':
    sys.exit(main())
