#!/usr/bin/env bash
# Hygiene scan for a public repo: fails if anything private could be in the working tree or the history.
# Usage: bash scripts/scan.sh
set -u
fail=0
check() { # label, pattern, extra grep args
  local label="$1" pattern="$2"
  local hits
  hits=$(git grep -n -I -E "$pattern" -- . ':!scripts/scan.sh' 2>/dev/null)
  hist=$(git log --all -p --no-color -- . ':!scripts/scan.sh' 2>/dev/null | grep -n -E "^\+.*($pattern)" | head -3)
  if [ -n "$hits" ] || [ -n "$hist" ]; then
    echo "FAIL: $label"; [ -n "$hits" ] && echo "$hits" | head -5; [ -n "$hist" ] && echo "(history) $hist"; fail=1
  fi
}
check "email address"            '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
check "tailnet hostname"         '\.ts\.net'
check "tailscale address"        '(^|[^0-9])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+'
check "long hex (key or token)"  '[0-9a-fA-F]{32,}'
check "token-looking string"     '(ghp_|github_pat_|sk-[A-Za-z0-9]|xox[abp]-|AKIA[0-9A-Z]{12})'
check "Apple ID wording"         '[Aa]pple ?ID'
check "claude session link"      'claude\.ai/code/session'
check "font or pattern asset"    '\.(ttf|otf|woff2?)'
# commit identity must be the noreply address only
bad=$(git log --all --format='%ae %ce' | tr ' ' '\n' | sort -u | grep -v -E '@users\.noreply\.github\.com$' | grep -v '^$')
if [ -n "$bad" ]; then echo "FAIL: non-noreply commit email in history:"; echo "$bad"; fail=1; fi
if [ "$fail" = 0 ]; then echo "SCAN CLEAN: nothing private found in the tree or the history."; else echo "SCAN FAILED"; fi
exit $fail
