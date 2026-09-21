---
name: gate-style
description: Use when writing or changing a gate — any script that decides whether something may proceed (the CI release gate under release/, a PreToolUse hook, a pipeline stage). Encodes the exit-code protocol, the fail-closed rule, the verdict schema, the shell traps that silently turn a block into an approval, and the test contract. Produces a verdict; never ships anything.
---

# gate-style

The house standard for Northstar's gates. Read this **before** writing a line of gate code, and check the
finished gate against it.

A gate has one job: answer *may this proceed?* and be trusted when it says no. The dangerous failure is
not a gate that blocks too much — that gets noticed in an hour. It is a gate that **approves something it
never actually examined**, which gets noticed the day it matters.

## Inputs

- `gate` — the script being written (e.g. `release/ci-release-gate.sh`).
- `tests` — its test directory (`release/tests/`), holding `*.test.sh` and a `run.sh` runner.
- `analysers` — the read-only scripts the gate calls for evidence: `scripts/pipeline-analyze.sh`,
  `scripts/canary-verify.sh`. A gate composes analysers; it does not re-implement their logic.
- `candidate` — the thing under judgement, named explicitly (a values overlay, a plan JSON, an image tag).
  Never inferred.

## The exit-code protocol — the whole contract

Three outcomes, three codes, and the third one is the one people forget:

| Exit | Meaning | When |
|---|---|---|
| `0` | **approve** | The gate examined the candidate and found nothing blocking |
| `2` | **block** | The gate examined the candidate and found at least one blocker |
| `1` | **cannot evaluate** | The gate could not do its job — missing input, unreadable file, an analyser that failed, a dependency absent |

`1` is **fail-closed** and it is not the same as `2`. A caller that sees `2` knows what is wrong and can
print it. A caller that sees `1` knows the gate itself is broken. Collapsing them hides an outage in the
gate behind a message about the candidate.

**Never exit `0` on a path you did not intend as approval.** Every early return is either a block or a
fail-closed, and the default at the end of the script is the only `0`.

## The verdict — structured, on stdout

```json
{
  "gate": "ci-release-gate",
  "candidate": "fixtures/release/candidate-values.yaml",
  "verdict": "block",
  "blockers": [
    {"check": "readiness-probe", "detail": "rendered probe path /health is not a route the app serves", "source": "helm template + app/orders-api/src/health.py"}
  ],
  "checks_run": ["readiness-probe", "rollout-floor", "resource-bounds"],
  "evidence": {"analyser": "scripts/pipeline-analyze.sh", "exit": 2}
}
```

Rules:

- `candidate` is always present, including on a block. **A verdict that does not name what it judged is
  not auditable** — six weeks later nobody can tell whether it examined the release or the default.
- Every blocker carries a `source`: the file, field or command the finding came from. "Failed policy
  check" is not a blocker, it is a mood.
- `checks_run` is the honest list. If a check was skipped because an input was missing, that is a
  fail-closed, not a silent omission.
- Human-readable lines go to **stderr**; the JSON goes to **stdout** alone, so a pipeline can parse it.

## Exact shell traps — each one turns a block into an approval

These are the ways a gate lies, and all of them pass review by eye:

| Trap | What happens | The fix |
|---|---|---|
| `set -e` plus `grep -q` | `grep` exits 1 on no-match, killing the script — which a caller reads as *cannot evaluate*, or worse, as success if the trap is after the last check | `if grep -q … ; then` or `grep -q … \|\| true` with an explicit branch |
| `cmd \| jq …` then `$?` | `$?` is jq's status, not `cmd`'s. A failed analyser whose output jq happily parses as `null` reads as a pass | `set -o pipefail`, or capture and check each step |
| `[[ -f "$f" ]] \|\| echo "missing"` | Prints a message and carries on to approve | `\|\| { echo "…" >&2; exit 1; }` |
| `VALUE=$(analyser …)` under `set -e` | A failing analyser aborts the gate with **exit 1 from the shell**, which is fail-closed by luck, not by design | Capture status explicitly: `out=$(…) ; rc=$?` |
| `--values "$CANDIDATE"` with `CANDIDATE` unset | Analyses the default instead of the candidate and approves it | `set -u`, and validate the input exists before use |
| `exit $?` after an `echo` | `$?` is the echo's status — always 0 | Save the status first |

**A gate must be tested against a candidate it is supposed to block.** A gate that has only ever been run
on a good input has never demonstrated the behaviour it exists for.

## Never ship, never repair

- A gate **reports**. It does not `git tag`, `git push`, `docker push`, `helm upgrade`, `kubectl apply`,
  or edit the candidate to make itself pass.
- A gate does not carry credentials. If it needs a secret to run, it is doing someone else's job.
- A gate does not repair. Its output is a verdict; repairing is a separate change with its own review.

## Test contract

Tests live in `<gate-dir>/tests/`, one concern per file, named `*.test.sh`, each executable, each
asserting on **exit code and the JSON**, not on log text:

```bash
#!/usr/bin/env bash
# blocks-bad-candidate.test.sh — the gate must block the known-bad release candidate.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
out=$("$ROOT/release/ci-release-gate.sh" --values fixtures/release/candidate-values.yaml 2>/dev/null); rc=$?

[[ "$rc" -eq 2 ]] || { echo "FAIL: expected exit 2 (block), got $rc"; exit 1; }
v=$(echo "$out" | jq -r '.verdict')
[[ "$v" == "block" ]] || { echo "FAIL: verdict is '$v', want block"; exit 1; }
n=$(echo "$out" | jq -r '.blockers | length')
[[ "$n" -ge 1 ]] || { echo "FAIL: verdict is block with $n blockers — a block with no reason is unactionable"; exit 1; }
echo "PASS: blocks the bad candidate (exit 2, $n blockers)"
```

- `tests/run.sh` runs every `*.test.sh` and ends with `PASS n / FAIL n`, exiting non-zero if any failed.
- **Cover all three exit codes.** The approve path, the block path, and the cannot-evaluate path. The
  third is the one that catches the trap table above.
- Each failure message prints the value it found. A `FAIL` with no value is a test you cannot debug from
  CI output.
- Write each test against the current behaviour and **watch it fail before you make it pass.**

## Reasoning zone — check the gate before handing it over

- An `exit 0` reachable from a check that did not run → **CORRECTNESS: approves what it did not examine.**
  Blocks.
- A missing or unreadable input that does not exit `1` → **FAIL-CLOSED VIOLATION.** Blocks.
- A blocker with no `source` → **AUDITABILITY: unactionable finding.**
- A verdict with no `candidate` field → **AUDITABILITY: unattributable verdict.**
- Any command that tags, pushes, applies or edits the candidate → **AUTHORITY: a gate that ships.** Blocks.
- A check whose result is discarded (`|| true` with no branch) → **CORRECTNESS: decorative check.**
- Human output on stdout mixed with the JSON → **INTEGRATION: unparseable verdict.**

Every branch terminates in a named finding. "Looks fine" is not an output.

## Stop conditions

- If an analyser the gate depends on is missing or not executable, stop and say so. Do not reimplement it
  inside the gate — then there are two rule sets to keep in sync.
- If the candidate cannot be rendered or read, the gate exits `1` and you report that as the designed
  behaviour, not as a failure of the run.
- If satisfying a check would require editing the candidate, stop. That is the gate working.
