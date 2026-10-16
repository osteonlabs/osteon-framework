"""Find a headless browser and run it in a throwaway profile. Standard library only.

Every run gets a fresh profile directory that is deleted afterwards, a mock keychain and no sync,
so a capture or a print can never read or write a person's own browser state. Every run is bounded:
on timeout the whole process group is killed, because a waiter that can only end on success waits
forever when the thing it watches dies.
"""
import glob
import os
import shutil
import signal
import subprocess
import tempfile
from pathlib import Path

NAMES = ('chromium', 'chromium-browser', 'chrome', 'headless_shell', 'headless-shell')
BASE = ['--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
        '--disable-extensions', '--disable-sync', '--use-mock-keychain', '--password-store=basic',
        '--disable-background-networking', '--hide-scrollbars', '--mute-audio']


def find(explicit=None):
    """Return an executable path, or None. An explicit path that is not executable is an error."""
    for cand in (explicit, os.environ.get('DELIVERY_BROWSER')):
        if cand:
            if os.path.isfile(cand) and os.access(cand, os.X_OK):
                return cand
            raise SystemExit('browser is not an executable file: %s' % cand)
    for name in NAMES:
        path = shutil.which(name)
        if path:
            return path
    home = os.path.expanduser('~')
    patterns = [
        home + '/Library/Caches/*/chromium_headless_shell-*/chrome-*/headless_shell',
        home + '/.cache/*/chromium_headless_shell-*/chrome-*/headless_shell',
        home + '/Library/Caches/*/chromium-*/chrome-mac*/*.app/Contents/MacOS/*',
        home + '/.cache/*/chromium-*/chrome-linux*/chrome',
        '/Applications/Chromium.app/Contents/MacOS/Chromium',
        '/Applications/*Chrome*.app/Contents/MacOS/*Chrome*',
    ]
    for pattern in patterns:
        hits = sorted(p for p in glob.glob(pattern) if os.path.isfile(p) and os.access(p, os.X_OK))
        if hits:
            return hits[-1]
    return None


def version(browser):
    try:
        r = subprocess.run([browser, '--version'], capture_output=True, text=True, timeout=30)
        return (r.stdout or r.stderr).strip()[:80]
    except (OSError, subprocess.TimeoutExpired):
        return 'unknown'


def run(browser, args, timeout=120):
    """Run the browser headless in a throwaway profile. Returns (exit code, stderr tail)."""
    profile = tempfile.mkdtemp(prefix='delivery-profile-')
    cmd = [browser] + BASE + ['--user-data-dir=' + profile] + list(args)
    if os.environ.get('DELIVERY_BROWSER_NO_SANDBOX') == '1':
        cmd.append('--no-sandbox')
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                start_new_session=True)
        try:
            _, err = proc.communicate(timeout=timeout)
            code, tail = proc.returncode, err.decode('utf-8', 'replace')[-800:]
        except subprocess.TimeoutExpired:
            _kill(proc.pid, signal.SIGKILL)
            proc.communicate()
            code, tail = 124, 'timed out after %ss' % timeout
        _kill(proc.pid, signal.SIGTERM)
        return code, tail
    finally:
        shutil.rmtree(profile, ignore_errors=True)


def _kill(pgid, sig):
    try:
        os.killpg(pgid, sig)
    except (ProcessLookupError, PermissionError):
        pass


def print_pdf(browser, html_path, pdf_path, timeout=300):
    """Print a local HTML file to PDF. Returns (ok, exit code, stderr tail)."""
    pdf_path = Path(pdf_path)
    if pdf_path.exists():
        pdf_path.unlink()
    args = ['--no-pdf-header-footer', '--print-to-pdf-no-header',
            '--run-all-compositor-stages-before-draw', '--virtual-time-budget=15000',
            '--print-to-pdf=%s' % pdf_path, Path(html_path).resolve().as_uri()]
    code, tail = run(browser, args, timeout)
    ok = pdf_path.exists() and pdf_path.stat().st_size > 800
    return ok, code, tail
