---
name: reachability-check
description: Use whenever a security finding names a vulnerable package/symbol and you need to know whether the running code actually reaches it — the deterministic answer that turns a CVE's severity into a priority. Greps the Go and Python trees for a real import and call site; returns reachable yes|no|unknown with file:line evidence.
---

# reachability-check

A scanner tells you a package is vulnerable. It cannot tell you whether anything calls it. This skill
answers that question deterministically — grep, not judgement — because reachability is the single
fact that separates a CVSS 9.8 that is noise from a CVSS 6.1 that is the real finding.

## Deterministic zone — collect facts

```bash
bash "$(dirname "$0")/scripts/reachability-check.sh" --lang py --import yaml --root platform/secfixtures/vulnerable-service
bash "$(dirname "$0")/scripts/reachability-check.sh" --lang py --import requests --root platform/secfixtures/vulnerable-service
```

- `--lang` — `py` or `go`.
- `--import` — the module name (Python, e.g. `yaml`, `requests`) or import path (Go, e.g.
  `github.com/go-chi/chi/v5`).
- `--root` — the source tree to search. Scope this to the actual service the finding is about — do
  not search the whole repo, or an unrelated service's import of the same package will produce a
  false `reachable: yes`.
- `--call` — optional override regex for the call-site pattern. Default is `<shortname>\.\w+\(`,
  which covers the common `import requests; requests.get(...)` / `import "chi"; chi.NewRouter()`
  shape. Override it when the code aliases the import (`import requests as r`).

The script's stdout ends with `reachable=yes|no|unknown` and a `reason=` line. Treat that line as the
fact; do not re-derive it by reading the CVE description.

## Reasoning zone — the three outcomes

- **`reachable=no`** — no import found. This is not a "possible false negative, keep looking" result;
  it is the finding's actual answer. A dependency that is pinned but never imported is dead weight —
  rank it last regardless of CVSS. Report the "reason" line as your evidence.
- **`reachable=yes`** — import and call site both found. Cite the `import:` and `call:` lines
  (file:line) verbatim as evidence in the finding. This is what promotes a MEDIUM CVE above a
  CRITICAL one that scored `reachable=no`.
- **`reachable=unknown`** — imported but no call site matched. Do not round this to `yes` or `no`.
  Report it as `unknown` with `confidence: low` and say what you'd need to resolve it (e.g. the call
  is behind a wrapper the default `--call` pattern doesn't match — re-run with a tighter `--call`, or
  read the file directly and say why).

## Stop conditions

- Never assert `reachable` without running this script (or, for `unknown`, having read the actual
  call site yourself and saying so). A guess dressed as a verdict is the failure mode this skill
  exists to prevent.
- If the language isn't Python or Go, say so and mark the finding `reachable: unknown` — do not
  improvise a grep pattern for a language this script doesn't support.
