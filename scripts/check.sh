#!/usr/bin/env bash
# Release gate -- every repository check in one place. Run it before pushing,
# or let .githooks/pre-push run it (git config core.hooksPath .githooks):
#
#   ./scripts/check.sh
#
# CI (.github/workflows/check.yml) runs this same script. Steps:
#   1. secret scan -- tracked files; the generic patterns below, plus private
#                     ones from the gitignored .secret-patterns.local (one
#                     extended regex per line, '#' comments allowed)
#   2. shellcheck  -- scripts/*.sh and .githooks/*, configured by .shellcheckrc
#   3. yamllint    -- the workflows, configured by .yamllint
#   4. actionlint  -- the workflows' Actions semantics: expressions, job
#                     outputs, permissions, and shellcheck on run: blocks
#   5. JSON syntax -- renovate.json
# The secret scan needs only git. The linters run where they are installed;
# CI installs them, and a local run without them says which ones it skipped.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n=== %s ===\n' "$1"; }
fail=0
skipped=()

step "secret scan (tracked files)"
# The repo is public. These patterns are deliberately generic; private ones
# (the forge's hostname, the home network's addresses, ...) belong in the
# untracked .secret-patterns.local, never here.
scan() { # scan <label> <pattern-ERE> [allowlist-ERE]
    local label="$1" pattern="$2" allow="${3:-}" hits rc=0
    # git grep exits 1 for "no match"; anything above that is a broken scan,
    # which must fail rather than pass as clean.
    hits="$(git grep -nEI -e "$pattern" -- ':(exclude)scripts/check.sh')" || rc=$?
    if [ "$rc" -gt 1 ]; then
        echo "FAIL: git grep could not run ($label)"
        fail=1
        return
    fi
    if [ -n "$allow" ] && [ -n "$hits" ]; then
        hits="$(printf '%s\n' "$hits" | grep -vE -- "$allow" || true)"
    fi
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits"
        echo "FAIL: possible private data in tracked files ($label)"
        fail=1
    fi
}

scan "private key block" 'BEGIN [A-Z ]*PRIVATE KEY'
scan "credentials in a URL" '://[^/[:space:]]+:[^/[:space:]]+@'
scan "home directory path" '(/home|/Users)/[a-z][a-z0-9_-]*/'
# Allowlisted: OpenWrt's factory-default LAN address.
scan "IPv4 address" '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' \
    '192\.168\.1\.1\b'
scan "MAC address" '\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b'

if [ -f .secret-patterns.local ]; then
    while IFS= read -r p; do
        case "$p" in ''|'#'*) continue ;; esac
        scan "local pattern" "$p"
    done < .secret-patterns.local
else
    echo "(no .secret-patterns.local: generic patterns only)"
fi
[ "$fail" -eq 0 ] && echo "OK"

step "shellcheck"
if command -v shellcheck >/dev/null; then
    shellcheck scripts/*.sh .githooks/* || fail=1
else
    skipped+=(shellcheck)
fi

step "yamllint"
if command -v yamllint >/dev/null; then
    yamllint .github/workflows/ || fail=1
else
    skipped+=(yamllint)
fi

step "actionlint"
if command -v actionlint >/dev/null; then
    actionlint || fail=1
else
    skipped+=(actionlint)
fi

step "JSON syntax"
if command -v python3 >/dev/null; then
    python3 -m json.tool renovate.json >/dev/null && echo "OK" || fail=1
else
    skipped+=("JSON syntax")
fi

echo
if [ ${#skipped[@]} -gt 0 ]; then
    echo "Skipped (not installed here; CI runs them): ${skipped[*]}"
fi
if [ "$fail" -ne 0 ]; then
    echo "Checks FAILED. A secret-scan false positive? Extend the allowlist in scripts/check.sh."
    exit 1
fi
echo "All checks passed."
