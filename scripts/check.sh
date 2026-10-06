#!/usr/bin/env bash
# Release gate, run before every push (by .githooks/pre-push once enabled) and
# by .github/workflows/check.yml. A linter that is not installed is skipped and
# named at the end.
#
# With --outgoing <remote>, as the pre-push hook runs it, the secret scan also
# covers what the push publishes beyond the tree, read from the ref updates git
# passes the hook on stdin.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n=== %s ===\n' "$1"; }
fail=0
skipped=()

# The repo is public. These patterns are generic; private ones (the forge's
# hostname, the home network's addresses) go in the gitignored
# .secret-patterns.local, one extended regex per line.
local_patterns=()
if [ -f .secret-patterns.local ]; then
    while IFS= read -r p; do
        case "$p" in ''|'#'*) continue ;; esac
        local_patterns+=("$p")
    done < .secret-patterns.local
fi

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
            git show --format= --no-color "$c" -- . ':(exclude)scripts/check.sh' |
                awk -v c="${c:0:7}" '/^\+\+\+ /{f = substr($0, 7); next}
                                     /^\+/{print c " " f ": " substr($0, 2)}'
        done
    done
}

search_tree() { git grep -nEI -e "$1" -- ':(exclude)scripts/check.sh'; }
search_outgoing() { grep -E -e "$1" "$outgoing"; }

scan() { # scan <label> <pattern-ERE> [allowlist-ERE], with $search
    local label="$1" pattern="$2" allow="${3:-}" hits rc=0
    # grep exits 1 for "no match"; anything above that is a broken scan, which
    # must fail rather than pass as clean.
    hits="$("$search" "$pattern")" || rc=$?
    if [ "$rc" -gt 1 ]; then
        echo "FAIL: the search could not run ($label)"
        return 1
    fi
    if [ -n "$allow" ] && [ -n "$hits" ]; then
        hits="$(printf '%s\n' "$hits" | grep -vE -- "$allow" || true)"
    fi
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits"
        echo "FAIL: possible private data ($label);"
        echo "      a false positive goes in this scan's allowlist in scripts/check.sh"
        return 1
    fi
}

scan_all() { # scan_all <search-function>
    local ok=1 p
    search="$1"
    scan "private key block" 'BEGIN [A-Z ]*PRIVATE KEY' || ok=0
    scan "credentials in a URL" '://[^/[:space:]]+:[^/[:space:]]+@' || ok=0
    scan "home directory path" '(/home|/Users)/[a-z][a-z0-9_-]*/' || ok=0
    # Allowlisted: OpenWrt's factory-default LAN address.
    scan "IPv4 address" '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' '192\.168\.1\.1\b' || ok=0
    scan "MAC address" '\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b' || ok=0
    for p in "${local_patterns[@]}"; do
        scan "local pattern" "$p" || ok=0
    done
    if [ "$ok" -eq 1 ]; then echo "OK"; else fail=1; fi
}

outgoing=""
if [ "${1:-}" = "--outgoing" ]; then
    outgoing="$(mktemp)"
    trap 'rm -f "$outgoing"' EXIT
    collect_outgoing "${2:?--outgoing needs the remote name}" > "$outgoing"
fi

step "secret scan (tracked files)"
[ -f .secret-patterns.local ] || echo "(no .secret-patterns.local: generic patterns only)"
scan_all search_tree
if [ -n "$outgoing" ]; then
    step "secret scan (outgoing commits)"
    scan_all search_outgoing
fi

lint() { # lint <tool> <command...>
    if command -v "$1" >/dev/null; then
        shift
        "$@" || fail=1
    else
        skipped+=("$1")
    fi
}

step "shellcheck";  lint shellcheck shellcheck scripts/*.sh .githooks/*
step "yamllint";    lint yamllint yamllint .github/workflows/
step "actionlint";  lint actionlint actionlint
step "JSON syntax"; lint python3 python3 -m json.tool renovate.json >/dev/null

echo
if [ ${#skipped[@]} -gt 0 ]; then
    echo "Skipped (not installed here; CI runs them): ${skipped[*]}"
fi
if [ "$fail" -ne 0 ]; then
    echo "Checks FAILED."
    exit 1
fi
echo "All checks passed."
