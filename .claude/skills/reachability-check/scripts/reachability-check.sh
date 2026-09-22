#!/usr/bin/env bash
# reachability-check.sh — deterministic: given a package/module and a source
# tree, report whether it is genuinely imported AND called, with file:line
# evidence. No LLM judgement in this script — that is the point.
#
# Usage:
#   reachability-check.sh --lang py|go --import <module-or-import-path> --root <dir> [--call <regex>]
#
# Output (stdout):
#   import: <file>:<line>:<matched text>   (zero or more)
#   call: <file>:<line>:<matched text>     (zero or more, only if imported)
#   reachable=yes|no|unknown
#   reason=<one line>
#
# Exit 0 always when args are valid — "reachable=unknown" is a legitimate,
# successful answer, not a script failure. Exit 1 only on bad usage.
set -euo pipefail

usage() {
  echo "usage: reachability-check.sh --lang py|go --import <name> --root <dir> [--call <regex>]" >&2
  exit 1
}

LANG_="" IMPORT="" ROOT="" CALL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --lang) LANG_="$2"; shift 2 ;;
    --import) IMPORT="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --call) CALL="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$LANG_" ] && [ -n "$IMPORT" ] && [ -n "$ROOT" ] || usage

if [ ! -d "$ROOT" ]; then
  echo "reachable=unknown"
  echo "reason=root not found: $ROOT"
  exit 0
fi

case "$LANG_" in
  py)
    IMPORT_PATTERN="^[[:space:]]*(import[[:space:]]+${IMPORT}\b|from[[:space:]]+${IMPORT}\b)"
    GLOB="*.py"
    SHORT="${IMPORT##*.}"
    ;;
  go)
    IMPORT_PATTERN="\"${IMPORT}\""
    GLOB="*.go"
    SHORT="${IMPORT##*/}"
    ;;
  *) usage ;;
esac

IMPORT_HITS="$(grep -rnE "$IMPORT_PATTERN" --include="$GLOB" "$ROOT" 2>/dev/null || true)"

if [ -z "$IMPORT_HITS" ]; then
  echo "reachable=no"
  echo "reason=no import of '$IMPORT' found under $ROOT"
  exit 0
fi

echo "$IMPORT_HITS" | sed 's/^/import: /'

CALL_PATTERN="${CALL:-${SHORT}\.[A-Za-z_][A-Za-z0-9_]*\(}"
CALL_HITS="$(grep -rnE "$CALL_PATTERN" --include="$GLOB" "$ROOT" 2>/dev/null || true)"

if [ -z "$CALL_HITS" ]; then
  echo "reachable=unknown"
  echo "reason=imported but no call site matched '$CALL_PATTERN' — verify manually, do not guess"
  exit 0
fi

echo "$CALL_HITS" | sed 's/^/call: /'
echo "reachable=yes"
echo "reason=import and call site both found under $ROOT"
