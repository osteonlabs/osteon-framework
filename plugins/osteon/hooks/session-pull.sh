#!/bin/sh
# session-pull.sh - bring a BONE up to date from its remote at session start.
#
# Usage: session-pull.sh DIR [REPORT]. session-start.sh calls it for a BONE (a MANIFEST.yaml
# declaring bone_version), and it can be run by hand. It acts only when DIR is the top of its own
# git repository, never on an enclosing one. The default branch D is the one the local origin/HEAD
# names; without origin/HEAD it is main or master, the one checked out first.
#
#   1. Fetch D alone from origin into origin/D, whatever remote.origin.fetch says, within 20 s in
#      all, with every prompt off (terminal, askpass, Git Credential Manager, and ssh batch mode
#      unless the user set an ssh command). No origin, or a clone that has never fetched anything
#      from an origin with nothing pushed yet: silent. A failed fetch: one line saying why.
#   2. Not on D: nothing moves. One line when the checked-out commit lacks commits of origin/D.
#   3. On D and not behind: silent, unless D moved forward while this session started (another
#      session's pull, one by hand, or a commit).
#   4. On D and behind: one line, and nothing moves, when D has commits origin/D lacks, when a
#      merge, rebase, am, cherry-pick, revert or bisect is in progress, when branch.D.mergeOptions
#      is set, when D is checked out or being rebased in another worktree, when origin/D holds
#      names that differ only in case on a file system that ignores case, or while a lock on D, on
#      HEAD or on the index stays in place. Otherwise fast-forward D to the commit fetched, with
#      git merge --ff-only --no-overwrite-ignore and autostash off, so git itself refuses to
#      overwrite a changed, untracked or ignored file; one line names the files in the way. When
#      git stops part-way, the line names the files it changed on disk. With a REPORT, the paths
#      changed since this session started are written to it, and a read-only command a line shows
#      to REPORT.cmd, so that session-start.sh prints it after its own note.
#
# Only the fetch is cut off at 20 s. The checkout runs as in a manual git pull, with the
# repository's own git hooks and filters (prompts off, C locale). Never merges a divergent
# history, rebases, stashes, resets or pushes, and no line suggests a command that changes
# anything. Always exits 0: a broken hook must never end a session. Kill switch:
# BONE_SESSION_PULL=off.
case ${BONE_SESSION_PULL:-} in [Oo][Ff][Ff]|0|[Ff][Aa][Ll][Ss][Ee]|[Nn][Oo]) exit 0 ;; esac
exec 2>/dev/null
# A shell may predefine aliases (ksh93 has stop='kill -s STOP'); none may change what runs here.
unalias -a
# Act on the repository found from the project folder, never on one the environment points at.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_NAMESPACE
unset GIT_ALTERNATE_OBJECT_DIRECTORIES
# cd prints the folder it reaches through CDPATH, which would end up inside the paths below.
unset CDPATH
# git's messages are matched below, so they must not be translated.
LC_ALL=C
export LC_ALL
P=${1:-${CLAUDE_PROJECT_DIR:-}}
REPORT=${2:-}
[ -n "$P" ] && cd "$P" || exit 0
if ! cdup=$(git rev-parse --show-cdup); then
  # git refuses a repository that another user owns unless safe.directory names it; when this
  # folder is the top of that repository, that gets one line. Any other failure here (no
  # repository at all, or a refused one around this folder) stays silent.
  [ -e .git ] && git rev-parse --show-cdup 2>&1 | grep -q -e 'dubious ownership' -e 'unsafe repository' &&
    printf '%s\n' "BONE sync: git refuses this folder because another user owns it (safe.directory), so nothing was pulled; this session reads the local copy."
  exit 0
fi
[ -z "$cdup" ] || exit 0
# The commit this session started on, read before anything that can take time: Claude Code
# loaded the files of this commit.
start=$(git rev-parse -q --verify HEAD) || start=
startref=$(git symbolic-ref -q HEAD) || startref=
url=$(git remote get-url origin) || exit 0

# One line out. Names come from the repository, so control characters are taken out and
# nothing is expanded.
say() { printf '%s' "$1" | tr '\t\r\n' '   ' | tr -d '\000-\037\177'; printf '\n'; }
# A word quoted for sh, for the one read-only command a line may show.
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# An absolute path for a file whose folder exists.
abs() { printf '%s/%s' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"; }
# The paths changed from $1 to $2, one per line, for session-start.sh. -z keeps git from quoting
# names that hold a quote, a backslash or a control character; a newline in a name becomes ?.
report() {
  [ -n "$REPORT" ] || return 0
  git -c core.quotePath=false diff -z --no-renames --name-only "$1" "$2" | tr '\n\000' '?\n' >"$REPORT"
}

cur=$(git symbolic-ref -q HEAD) || cur=
R=$(git symbolic-ref -q refs/remotes/origin/HEAD) && D=${R#refs/remotes/origin/} || D=
if [ -z "$D" ]; then
  case $cur in refs/heads/main|refs/heads/master) D=${cur#refs/heads/} ;; esac
fi
if [ -z "$D" ]; then
  for b in main master; do
    git rev-parse -q --verify "refs/heads/$b" >/dev/null && { D=$b; break; }
  done
fi
[ -n "$D" ] || exit 0
L="refs/heads/$D"
O="refs/remotes/origin/$D"
# Whether this clone has ever fetched anything from origin: a branch of origin, or origin/HEAD,
# even one that names a branch since pruned.
ever=$R$(git for-each-ref --count=1 --format=x refs/remotes/origin)

# git's error output is kept for the reason given in the line, never printed as it is; the
# merge's standard output and two snapshots of git status are kept beside it. They all live in one
# folder made for this run, in TMPDIR or else /tmp, and only that folder is removed at the end.
TD=$(mktemp -d "${TMPDIR:-/tmp}/bone-sync.XXXXXX") || TD=$(mktemp -d /tmp/bone-sync.XXXXXX) || TD=
trap '[ -n "$TD" ] && rm -rf "$TD"' EXIT
if [ -n "$TD" ]; then E=$TD/err E2=$TD/out; else E=/dev/null E2=/dev/null; fi
# A signal stops a fetch still running, with its watchdog, and ends through the EXIT trap. Further
# signals are ignored from then on, so that a second one cannot cut the cleanup short.
pid=
watch=
trap 'trap "" HUP INT TERM PIPE; [ -n "$pid" ] && stop_tree "$pid"; [ -n "$watch" ] && kill -s TERM "$watch"; exit 0' HUP INT TERM PIPE

# No prompt of any kind: git's own terminal prompt, an askpass program (an empty GIT_ASKPASS
# also overrides core.askPass and SSH_ASKPASS), Git Credential Manager, and ssh in batch mode
# unless the user chose their own ssh command. A transfer that stalls ends on its own.
GIT_TERMINAL_PROMPT=0 GIT_ASKPASS='' SSH_ASKPASS='' SSH_ASKPASS_REQUIRE=never GCM_INTERACTIVE=never
GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=10
export GIT_TERMINAL_PROMPT GIT_ASKPASS SSH_ASKPASS SSH_ASKPASS_REQUIRE GCM_INTERACTIVE
export GIT_HTTP_LOW_SPEED_LIMIT GIT_HTTP_LOW_SPEED_TIME
if [ -z "${GIT_SSH_COMMAND:-}${GIT_SSH:-}" ] && ! git config core.sshCommand >/dev/null; then
  GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2'
  export GIT_SSH_COMMAND
fi

# Stop process $1 and everything it started: its process group where the shell made one (set -m),
# otherwise every descendant, all listed before any is stopped, because a process whose parent
# dies moves to init and can no longer be found. CONT lets a process a terminal stopped act on it.
stop_tree() {
  if kill -s TERM -- "-$1"; then
    kill -s CONT -- "-$1"
    return
  fi
  t=$(ps -A -o pid= -o ppid= | awk -v r="$1" '{ up[$1] = $2 }
    END { for (c in up) { p = c; n = 0
            while ((p in up) && p + 0 != r + 0 && n++ < 64) p = up[p]
            if (p + 0 == r + 0 && c + 0 != r + 0) print c } }')
  kill -s TERM $t "$1"
  kill -s CONT $t "$1"
}

# Job control gives the fetch a process group of its own. It is used only when no terminal is
# attached, as when Claude Code runs the hook: in a terminal, dash's set -m can stop the hook when
# it runs in the background, and the descendant list above does the same work there.
jc=
( : </dev/tty ) 2>/dev/null || jc=1

# fetch_d SECONDS: the fetch runs in the background so that a watchdog can stop it after SECONDS.
# It is a plain command, not a function, so that $! is git itself. --refmap= keeps git from also
# applying remote.origin.fetch, which can map origin's branches onto local ones. Once the watchdog
# fires it finishes stopping the fetch whatever happens, and its exit status 3 says that it fired.
fetch_d() {
  [ -n "$jc" ] && set -m
  git -c gc.auto=0 -c maintenance.auto=false -c fetch.writeCommitGraph=false fetch -q --refmap= --no-tags --no-recurse-submodules origin "+$L:$O" </dev/null >/dev/null 2>"$E" &
  pid=$!
  [ -n "$jc" ] && set +m
  ( trap 'kill -s TERM "$s"; exit 0' HUP INT TERM
    sleep "$1" & s=$!
    wait "$s"
    trap '' TERM
    stop_tree "$pid"
    exit 3 ) >/dev/null 2>&1 &
  watch=$!
  wait "$pid"; rc=$?
  kill -s TERM "$watch"
  wait "$watch"
  [ $? -eq 3 ] && [ "$rc" -ne 0 ] && rc=timeout
  pid=
  watch=
}

why=
cmd=
t0=$(date +%s)
fetch_d 20
if [ "$rc" = 1 ] && ! grep -q 'but expected' "$E" && grep -q -e 'File exists' -e 'cannot lock references' "$E"; then
  # A ref lock held by another git command: wait up to 3 s for it, then fetch once more within
  # what is left of the 20 s. A lock that stays is reported. A reftable clone locks its table list.
  gcd=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
  lk=$gcd/$O.lock
  [ -e "$gcd/reftable/tables.list.lock" ] && lk=$gcd/reftable/tables.list.lock
  n=0
  while [ -e "$lk" ] && [ "$n" -lt 3 ] && [ $(($(date +%s) - t0)) -lt 20 ]; do sleep 1; n=$((n + 1)); done
  left=$((20 - $(date +%s) + t0))
  [ "$left" -gt $((20 - n)) ] && left=$((20 - n))
  if [ -e "$lk" ]; then
    why="the lock file $(q "$lk") stays in place: a git command is still running, or one stopped without removing it"
  elif [ "$left" -ge 2 ]; then
    fetch_d "$left"
  else
    why="another git command held the lock on origin/$D until the 20 s were up"
  fi
fi
# Quoted names, such as the remote's address, are left out of the text matched, and so is the
# remote's host name where it stands as a word, so that words in them cannot choose the reason. A
# bare host alias such as git is kept: it is also an ordinary word.
host=$(printf '%s' "$url" | sed -e 's|^[A-Za-z][A-Za-z0-9+.-]*://||' -e 's|^[^@/]*@||' -e 's|[:/].*$||')
m=$(sed -e "s/'[^']*'//g" "$E" | awk -v h="$host" '
  function strip(s,   out, i, b, a, a2, okb, oka) {
    out = ""
    while ((i = index(tolower(s), tolower(h))) > 0) {
      b = substr(s, i - 1, 1); a = substr(s, i + length(h), 1); a2 = substr(s, i + length(h) + 1, 1)
      okb = (i == 1 || b !~ /[A-Za-z0-9.-]/)
      oka = (a !~ /[A-Za-z0-9.-]/ || (a == "." && (a2 == "" || a2 == " ")))
      if (okb && oka) { out = out substr(s, 1, i - 1); s = substr(s, i + length(h)) }
      else { out = out substr(s, 1, i); s = substr(s, i + 1) }
    }
    return out s
  }
  h ~ /[.]/ { $0 = strip($0) }
  { print }')
has() { printf '%s\n' "$m" | grep -qi "$@"; }
# The same without lines a server sends (remote: ...), which name neither a local command nor TLS.
hasl() { printf '%s\n' "$m" | grep -vi '^remote:' | grep -qi "$@"; }
if [ -z "$why" ]; then
  case $rc in
    0) ;;
    timeout) why="origin did not answer within 20 s" ;;
    1)
      # "is at ... but expected ...": a session that started at the same moment updated the ref
      # first, with the same value. What it wrote is used.
      has 'but expected' || why="git fetch exited 1" ;;
    *)
      if has 'find remote ref'; then
        # A clone that never fetched anything, from an origin with nothing pushed yet, as for a new
        # BONE, has nothing to pull.
        [ -n "$ever" ] || exit 0
        why="origin has no branch $D, perhaps because it was renamed"
        cmd="The branch origin names as its default: git -C $(q "$P") ls-remote --symref origin HEAD"
      elif hasl -e 'command not found' -e ': not found$'; then
        why="a command git needs to reach origin is missing"
      elif has -e 'does not appear to be a git repository' -e 'repository not found' -e 'could not be found' \
          -e 'not found'; then
        why="origin's repository was not found, or it cannot be seen without a credential"
      elif has -e 'authentication failed' -e 'could not read username' -e 'could not read password' \
          -e 'terminal prompts disabled' -e 'permission denied' -e 'host key verification failed' \
          -e 'access denied' -e 'returned error: 40[13]'; then
        why="it needs a credential or a host key that cannot be asked for here"
      elif has -e 'could not resolve' -e 'connection refused' -e 'unreachable' -e 'no route to host' \
          -e 'failed to connect' -e "couldn't connect"; then
        why="origin could not be reached"
      elif hasl -e 'certificate' -e 'verification failed' -e 'ssl routines' -e 'ssl_connect' -e 'ssl_error' \
          -e 'ssl: ' -e 'gnutls' -e 'tls handshake' -e 'schannel'; then
        why="the TLS connection to origin failed"
      elif has -e 'too slow' -e 'timed out'; then
        why="origin did not answer in time"
      elif has -e 'connection reset' -e 'connection closed' -e 'unable to access'; then
        why="origin could not be reached"
      else
        why="git fetch exited $rc"
      fi ;;
  esac
fi
# since: when this session started on D and D moved forward from that commit since then, write
# the changed paths to REPORT and set SINCE to a sentence that says so. It does not say who moved
# D, since another session's pull, a pull or push by hand and a local commit look alike here; it
# says only whether D now equals origin/D.
since() {
  SINCE=
  [ -n "$start" ] && [ "$startref" = "$L" ] && [ "$(git symbolic-ref -q HEAD)" = "$L" ] || return 1
  now=$(git rev-parse HEAD) && [ "$now" != "$start" ] && git merge-base --is-ancestor "$start" "$now" || return 1
  report "$start" "$now"
  how=
  [ "$now" = "$(git rev-parse -q --verify "$O")" ] && how=", and it now matches origin/$D"
  SINCE="$D moved forward $(git rev-list --count "$start..$now") commit(s) while this session started ($(git rev-parse --short "$start")..$(git rev-parse --short "$now"))$how."
}
# line TEXT [COMMAND]: print one line, with the since sentence added when D moved forward
# meanwhile. A read-only COMMAND the line shows comes last, so that it can be copied as it is:
# with a REPORT it goes to REPORT.cmd instead, and session-start.sh prints it after its own note.
line() {
  lt=$1
  since && lt="$lt Meanwhile $SINCE"
  if [ -n "${2:-}" ] && [ -n "$REPORT" ]; then
    say "$2" >"$REPORT.cmd"
    say "$lt"
  else
    say "$lt${2:+ $2}"
  fi
}
# wait_lock FILE: wait while FILE exists, within what is left of the 20 s.
wait_lock() {
  lim=$((20 - $(date +%s) + t0))
  [ "$lim" -lt 0 ] && lim=0
  [ "$lim" -gt 20 ] && lim=20
  n=0
  while [ -e "$1" ] && [ "$n" -lt "$lim" ]; do sleep 1; n=$((n + 1)); done
  [ ! -e "$1" ]
}

if [ -n "$why" ]; then
  line "BONE sync: could not fetch $D from origin ($why); this session reads the local copy, which may be behind origin." "$cmd"
  exit 0
fi
# The commit fetched is the one checked and merged from here on: origin/D can move again while
# this runs (a fetch by another session), and every check below must hold for what is merged.
tgt=$(git rev-parse -q --verify "$O") || exit 0

# The branch is read again: it may have been switched during the fetch. Not on D: a session reads
# the files of the commit it is on, which a pull of D does not change.
cur=$(git symbolic-ref -q HEAD) || cur=
if [ "$cur" != "$L" ]; then
  n=$(git rev-list --count "HEAD..$tgt") || exit 0
  [ "${n:-0}" -gt 0 ] || exit 0
  if [ -n "$cur" ]; then on="branch ${cur#refs/heads/}"; else on="a detached HEAD"; fi
  say "BONE sync: this session is on $on, not on $D, so nothing was pulled, and it lacks $n commit(s) that origin/$D has."
  exit 0
fi

git rev-parse -q --verify "$L" >/dev/null || exit 0
behind=$(git rev-list --count "$L..$tgt") || exit 0
if [ "${behind:-0}" -eq 0 ]; then
  since && say "BONE sync: $SINCE"
  exit 0
fi
if ! git merge-base --is-ancestor "$L" "$tgt"; then
  ahead=$(git rev-list --count "$tgt..$L")
  line "BONE sync: $D has $ahead local commit(s) that origin/$D does not, and origin/$D has $behind that $D does not, so nothing was pulled; this session reads the local copy." "To see both sides: git -C $(q "$P") log --oneline --left-right $(q "$L...$O")"
  exit 0
fi
for f in MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD sequencer BISECT_LOG; do
  [ -e "$(git rev-parse --git-path "$f")" ] || continue
  case $f in
    MERGE_HEAD) op="a merge" ;;
    rebase-*) op="a rebase or git am" ;;
    CHERRY_PICK_HEAD) op="a cherry-pick" ;;
    REVERT_HEAD) op="a revert" ;;
    sequencer) op="a cherry-pick or revert" ;;
    *) op="a bisect" ;;
  esac
  line "BONE sync: $D is $behind commit(s) behind origin/$D and was not pulled, because $op is in progress; this session reads the local copy."
  exit 0
done
if [ -n "$(git config --get-all "branch.$D.mergeoptions")" ]; then
  line "BONE sync: $D is $behind commit(s) behind origin/$D and was not pulled, because branch.$D.mergeOptions is set and a session start merges with no options; this session reads the local copy."
  exit 0
fi
# On a file system that ignores case (core.ignorecase, which git sets on macOS and Windows), git's
# checkout of a tree that holds two names differing only in case, such as a file Docs beside a
# folder docs, can delete that folder with the changes in it. Such a tree is not checked out.
# Only ASCII letters are compared.
if [ "$(git config --bool core.ignorecase)" = true ]; then
  # Names are compared as strings: awk would compare 1e2 and 1E2 as numbers.
  dup=$(git -c core.quotePath=false ls-tree -r -t -z --name-only "$tgt" | tr '\n\000' '?\n' |
    awk '{ k = tolower($0) } (k in seen) && (seen[k] "") != ($0 "") && !(k in done) { print seen[k] " and " $0; done[k] = 1; next }
      !(k in seen) { seen[k] = $0 }')
  if [ -n "$dup" ]; then
    total=$(printf '%s\n' "$dup" | wc -l | tr -d ' ')
    list=$(printf '%s\n' "$dup" | head -n 3 | sed 's/$/;/' | tr '\n' ' ')
    list=${list%"; "}
    [ "$total" -gt 3 ] && list="$list; and $((total - 3)) more"
    line "BONE sync: $D is $behind commit(s) behind origin/$D and was not pulled, because origin/$D holds names that differ only in case ($list), which this file system cannot keep apart; this session reads the local copy."
    exit 0
  fi
fi
# D checked out in another worktree as well (git worktree add --force, or, on a file system that
# ignores case, a name that differs only in case), or being rebased there, would move under it.
# Every worktree git lists counts, also one whose folder git cannot find: it may have been moved
# by hand or sit on a drive that is not mounted. Case is ignored only where the refs are files:
# git reports its ref format itself (git before 2.45, which has only files, echoes the option).
ic=
[ "$(git config --bool core.ignorecase)" = true ] && [ "$(git rev-parse --show-ref-format)" != reftable ] && ic=-i
nwt=$(git worktree list --porcelain | grep -c $ic -F -x "branch $L")
reb=
gcd=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
own=$(cd "$(git rev-parse --git-dir)" && pwd -P)
for g in "$gcd" "$gcd"/worktrees/*; do
  [ -d "$g" ] && [ "$(cd "$g" && pwd -P)" != "$own" ] || continue
  for f in "$g/rebase-merge/head-name" "$g/rebase-apply/head-name"; do
    [ -f "$f" ] && grep -q $ic -F -x "$L" "$f" && reb=1
  done
done
if [ "${nwt:-0}" -gt 1 ] || [ -n "$reb" ]; then
  line "BONE sync: $D is $behind commit(s) behind origin/$D and was not pulled, because $D is also checked out, or being rebased, in another worktree, which a move of $D would leave behind; this session reads the local copy."
  exit 0
fi
# A lock on D's ref or on HEAD, or on the table list of a reftable clone, would let git write the
# new files and then fail to move D, so that they look like local changes. Wait for it, then leave
# everything as it is if it stays.
# A linked worktree of a reftable clone keeps HEAD in a table list of its own.
for lf in "$(git rev-parse --git-path "$L.lock")" "$(git rev-parse --git-path HEAD.lock)" \
    "$(git rev-parse --git-common-dir)/reftable/tables.list.lock" "$(git rev-parse --git-dir)/reftable/tables.list.lock"; do
  [ -e "$lf" ] || continue
  wait_lock "$lf" && continue
  line "BONE sync: $D is $behind commit(s) behind origin/$D and was not pulled, because the lock file $(q "$(abs "$lf")") stays in place: a git command is still running, or one stopped without removing it; this session reads the local copy."
  exit 0
done

# The merge's output goes to files, not through a pipe, so that a process one of the repository's
# own hooks leaves behind cannot hold this hook open: its standard output, where git writes
# "Updating" or "Already up to date", to one, and its errors to the other. The repository's hooks
# write to the error stream. The merge runs only while D is still the branch checked out.
merge_d() {
  before=$(git rev-parse HEAD)
  [ "$(git symbolic-ref -q HEAD)" = "$L" ] || return 9
  git -c gc.auto=0 -c maintenance.auto=false -c merge.autoStash=false merge --ff-only --no-stat --no-overwrite-ignore "$tgt" </dev/null >"$E2" 2>"$E"
}
# git status before the merge, so that a merge that git stops part-way can be told from one it
# refused before writing anything (see the end).
gst() { git --no-optional-locks status --porcelain -z --untracked-files=all --no-renames --ignore-submodules=all; }
st=
[ -n "$TD" ] && gst >"$TD/st0.z" && tr '\n\000' '?\n' <"$TD/st0.z" >"$TD/st0" && st=1
merge_d; mrc=$?
[ "$mrc" -eq 9 ] && exit 0
ilk=$(git rev-parse --git-path index.lock)
if [ "$mrc" -ne 0 ] && grep -q 'index\.lock' "$E"; then
  # Another git command holds the index, often a session that started at the same moment and is
  # checking out the same pull: wait for it, then merge once more if D is still behind.
  if wait_lock "$ilk" && ! git merge-base --is-ancestor "$tgt" HEAD; then
    merge_d; mrc=$?
    [ "$mrc" -eq 9 ] && exit 0
  fi
fi
after=$(git rev-parse HEAD)
# Without a file for the output, a merge that exits 0 while HEAD moved counts as this session's own.
ours=
if [ "$mrc" -eq 0 ] && [ "$after" != "$before" ]; then
  if [ "$E2" = /dev/null ]; then
    ours=1
  else
    first=$(sed -n -e '/^Updating /{p;q;}' -e '/^Already up.to.date/{p;q;}' "$E2")
    [ "${first#Updating }" != "$first" ] && ours=1
  fi
fi
if [ -n "$ours" ]; then
  # The changed paths are counted from the commit this session started on, so that a move of D
  # made in between is covered too.
  base=$before
  [ -n "$start" ] && git merge-base --is-ancestor "$start" "$after" && base=$start
  report "$base" "$after"
  say "BONE sync: pulled $(git rev-list --count "$before..$after") commit(s) from origin/$D ($(git rev-parse --short "$before")..$(git rev-parse --short "$after"))."
  exit 0
fi
# Another session that started at the same moment pulled first: D now holds the commit fetched,
# or D moved and now equals origin/D (origin was force-pushed, and that session pulled the new
# tip).
if git merge-base --is-ancestor "$tgt" "$after" ||
   { [ "$after" != "$start" ] && [ "$after" = "$(git rev-parse -q --verify "$O")" ]; }; then
  since && say "BONE sync: $SINCE"
  exit 0
fi
TAB=$(printf '\t')
files=$(sed -n "s/^$TAB//p" "$E")
if [ -n "$files" ]; then
  total=$(printf '%s\n' "$files" | wc -l | tr -d ' ')
  list=$(printf '%s\n' "$files" | head -n 5 | sed 's/$/,/' | tr '\n' ' ')
  list=${list%, }
  [ "$total" -gt 5 ] && list="$list and $((total - 5)) more"
  line "BONE sync: $D is $behind commit(s) behind origin/$D and was not pulled, because the update would overwrite local files that are changed, untracked or ignored: $list. This session reads the local copy; once those files are out of the way, a later session start tries again."
elif [ -e "$ilk" ]; then
  line "BONE sync: $D is $behind commit(s) behind origin/$D and was not pulled, because the lock file $(q "$(abs "$ilk")") stays in place: a git command is still running, or one stopped without removing it; this session reads the local copy."
else
  # The reason: a missing command first, as when a filter's program is not on PATH, then git's
  # first message.
  cnf=$(grep -e 'command not found' -e ': not found$' "$E" | head -n 1)
  why=$(sed -n -e 's/^error: //p' -e 's/^fatal: //p' "$E" | head -n 1)
  # git checks files out one by one and gives up when a filter such as git-lfs is missing or
  # fails, or when the file system refuses a name. The files it changed stay changed while D stays
  # where it was: they are named, and session-start.sh is told of them. git status shows them as
  # local changes, so a later start does not pull over them.
  part=
  if [ -n "$st" ] && gst >"$TD/st1.z"; then
    tr '\n\000' '?\n' <"$TD/st1.z" >"$TD/st1"
    part=$(git -c core.quotePath=false diff -z --no-renames --name-only HEAD "$tgt" | tr '\n\000' '?\n' |
      A=$TD/st0 B=$TD/st1 awk 'BEGIN { while ((getline l < ENVIRON["A"]) > 0) s[l] = 1
        while ((getline l < ENVIRON["B"]) > 0) if (!(l in s)) c[substr(l, 4)] = 1 }
        ($0 in c)')
  fi
  if [ -n "$part" ]; then
    # git's fatal message names the file it stopped at.
    whyf=$(sed -n 's/^fatal: //p' "$E" | head -n 1)
    why=${cnf:-${whyf:-$why}}
    # The since sentence first, since it writes REPORT; these files are added to it.
    ms=
    since && ms=" Meanwhile $SINCE"
    [ -n "$REPORT" ] && printf '%s\n' "$part" >>"$REPORT"
    total=$(printf '%s\n' "$part" | wc -l | tr -d ' ')
    list=$(printf '%s\n' "$part" | head -n 5 | sed 's/$/,/' | tr '\n' ' ')
    list=${list%, }
    [ "$total" -gt 5 ] && list="$list and $((total - 5)) more"
    say "BONE sync: the update of $D to origin/$D stopped part-way (${why:-git stopped}); $D stays at $(git rev-parse --short HEAD), but git changed these files on disk: $list. git status shows them as local changes; they come from the update, not from you, so do not commit them.$ms"
  else
    why=${cnf:-$why}
    line "BONE sync: $D is $behind commit(s) behind origin/$D and was not pulled (${why:-git refused the fast-forward}); this session reads the local copy."
  fi
fi
exit 0
