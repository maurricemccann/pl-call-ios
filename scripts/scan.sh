#!/usr/bin/env bash
# Hygiene scan for a public repo: fails if anything private could be in the working tree or the history.
# Usage: bash scripts/scan.sh
# Allowed on purpose: the bundled fonts and the brand images (already public on the brand's website).
# Font licence files are skipped by the email check only: a licence may print its author's public contact.
set -u
fail=0
check() { # label, pattern, then any extra paths to leave out
  local label="$1" pattern="$2"
  shift 2
  local hits hist
  # "@call.local" is the app's own made-up contact handle (.local never routes on the internet), not a person's address
  hits=$(git grep -n -I --untracked -E "$pattern" -- . ':!scripts/scan.sh' "$@" 2>/dev/null | grep -v -E '[a-z]+@call\.local')
  hist=$(git log --all -p --no-color -- . ':!scripts/scan.sh' "$@" 2>/dev/null | grep -n -E "^\+.*($pattern)" | grep -v -E '[a-z]+@call\.local' | head -3)
  if [ -n "$hits" ] || [ -n "$hist" ]; then
    echo "FAIL: $label"; [ -n "$hits" ] && echo "$hits" | cut -c1-200 | head -5; [ -n "$hist" ] && echo "(history) $hist" | cut -c1-200; fail=1
  fi
}
check "email address"            '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' ':!*OFL.txt' ':!*LICENSE*'
check "tailnet hostname"         '\.ts\.net'
check "tailscale address"        '(^|[^0-9])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+'
check "long hex (key or token)"  '[0-9a-fA-F]{32,}'
check "token-looking string"     '(ghp_|github_pat_|(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{16,}|xox[abp]-|AKIA[0-9A-Z]{12})'
check "Apple ID wording"         '[Aa]pple ?ID'
check "claude session link"      'claude\.ai/code/session'
# commit identity must be the noreply address only
bad=$(git log --all --format='%ae %ce' 2>/dev/null | tr ' ' '\n' | sort -u | grep -v -E '@users\.noreply\.github\.com$' | grep -v '^$')
if [ -n "$bad" ]; then echo "FAIL: non-noreply commit email in history:"; echo "$bad"; fail=1; fi
if [ "$fail" = 0 ]; then echo "SCAN CLEAN: nothing private found in the tree or the history."; else echo "SCAN FAILED"; fi
exit $fail
