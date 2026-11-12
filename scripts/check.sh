#!/usr/bin/env bash
# Release gate, run before every push (by .githooks/pre-push once enabled) and
# by CI (.github/workflows/ci.yml). The shared steps come from
# scripts/lib/gate.sh (managed by repo-template): the toolchain, shellcheck
# and the secret scan over tracked files. This repository's own steps run
# yamllint and actionlint over the workflows and check renovate.json's syntax.
#
# With --outgoing <remote>, as the pre-push hook runs it, the secret scan also
# covers what the push publishes beyond the tree, read from the ref updates git
# passes the hook on stdin.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=lib/gate.sh
. scripts/lib/gate.sh

is_zero() { case "$1" in *[!0]*) return 1 ;; esac; }

# A push publishes each new commit's message and added lines, even those a
# later commit removes again, plus the ref names and annotated tag messages.
# Every line is prefixed with where it comes from.
collect_outgoing() { # collect_outgoing <remote>, ref updates on stdin
  local remote="$1" local_oid remote_ref remote_oid range commits c
  while read -r _ local_oid remote_ref remote_oid; do
    is_zero "$local_oid" && continue # a deletion publishes nothing
    echo "ref: $remote_ref"
    if [ "$(git cat-file -t "$local_oid")" = tag ]; then
      git cat-file -p "$local_oid" | sed '1,/^$/d; s/^/tag message: /'
    fi
    # Commits the remote already has are public already; only new ones count.
    if ! is_zero "$remote_oid" && git cat-file -e "$remote_oid" 2>/dev/null; then
      range=("$local_oid" --not "$remote_oid")
    else
      range=("$local_oid" --not "--remotes=$remote")
    fi
    commits="$(git rev-list "${range[@]}")"
    for c in $commits; do
      git log -1 --format=%B "$c" | sed "s/^/${c:0:7} message: /"
      git show --format= --no-color "$c" -- . ':(exclude)scripts/check.sh' ':(exclude)scripts/lib/gate.sh' |
        awk -v c="${c:0:7}" '/^\+\+\+ /{f = substr($0, 7); next}
                             /^\+/{print c " " f ": " substr($0, 2)}'
    done
  done
}

# One pattern over the collected lines; 1 on a hit or a broken search.
out_scan() { # out_scan <file> <label> <pattern-ERE> [allowlist-ERE]
  local hits rc=0
  # grep exits 1 for "no match"; anything above that is a broken scan.
  hits="$(grep -E -e "$3" "$1")" || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "FAIL: the search could not run ($2)"
    return 1
  fi
  if [ -n "${4:-}" ] && [ -n "$hits" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE -- "$4" || true)"
  fi
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    echo "FAIL: possible private data ($2)"
    return 1
  fi
}

# The tree scan's patterns over what the push publishes.
outgoing_scan() { # outgoing_scan <file>
  local f="$1" ok=1 p
  out_scan "$f" "private key block" 'BEGIN [A-Z ]*PRIVATE KEY' || ok=0
  out_scan "$f" "credentials in a URL" '://[^/[:space:]]+:[^/[:space:]]+@' || ok=0
  out_scan "$f" "home directory path" '(/home|/Users)/[a-z][a-z0-9_-]*/' '/home/linuxbrew/' || ok=0
  # Allowed, as in the tree scan: OpenWrt's default LAN address, and the
  # four-part version pins of requirements files.
  out_scan "$f" "IPv4 address" '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' \
    '192\.168\.1\.1\b|requirements[^ :]*\.txt: [A-Za-z0-9_.-]+==[0-9.]+$' || ok=0
  out_scan "$f" "MAC address" '\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b' || ok=0
  if [ -f .secret-patterns.local ]; then
    while IFS= read -r p; do
      case "$p" in ''|'#'*) continue ;; esac
      out_scan "$f" "local pattern" "$p" || ok=0
    done < .secret-patterns.local
  fi
  [ "$ok" -eq 1 ] || exit 1
  echo "OK"
}

# Read the ref updates first: the hook's stdin is gone once anything else runs.
outgoing=""
if [ "${1:-}" = "--outgoing" ]; then
  outgoing="$(mktemp)"
  trap 'rm -f "$outgoing"' EXIT
  collect_outgoing "${2:?--outgoing needs the remote name}" > "$outgoing"
fi

gate_toolchain
"$VENV/bin/yamllint" --version
"$VENV/bin/actionlint" --version | head -n 1
gate_shellcheck

step "yamllint"
"$VENV/bin/yamllint" .github/workflows/
echo "OK"

step "actionlint"
"$VENV/bin/actionlint"
echo "OK"

step "JSON syntax"
"$VENV/bin/python" -m json.tool renovate.json > /dev/null
echo "OK"

gate_secret_scan
if [ -n "$outgoing" ]; then
  step "secret scan (outgoing commits)"
  outgoing_scan "$outgoing"
fi
gate_done
