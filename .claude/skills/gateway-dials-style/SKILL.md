---
name: gateway-dials-style
description: Use when diagnosing or recommending a change to the model gateway — a routing flip, a prompt change, a latency or cost regression on an LLM-powered feature. Encodes the four dials, the provider/application split, the provenance rule every number must satisfy, and the recommendation contract a change-reviewer can act on. Reports and recommends; never flips a route.
---

# gateway-dials-style

The house standard for diagnosing Northstar's model gateway. Read this **before** reading a dial or
writing a recommendation, and check the finished recommendation against it.

A gateway diagnosis has one job: hand somebody a decision they can act on without re-doing your
work. The dangerous failure is not a wrong recommendation — that gets argued with. It is a
**well-formatted recommendation whose numbers were never measured**, because it looks exactly like
one that was, and nothing in it says otherwise.

## Inputs

- `routing` — `platform/gateway/routing.yaml`: which model tier serves which traffic class. The
  decision.
- `providers` — `platform/gateway/providers.yaml`: what each tier costs and how fast it is. The facts.
- `baseline` — `fixtures/gateway/routing-baseline.yaml`: the routing as it was before the change.
- `traces` — `fixtures/gateway/traces/*.json`: per-request spans, each tagged `provider` or
  `application`.
- `suite` — `evals/promptfoo/*.yaml` plus the recorded output sets in `fixtures/gateway/`.

The deterministic tools are `scripts/gateway-diff.sh`, `scripts/llm-dials.sh` and
`scripts/promptfoo-gate.sh`. You **compose** them. You do not re-implement their arithmetic, and you
do not substitute your own.

## The four dials, and why never one alone

| Dial | The question | Tool |
|---|---|---|
| **latency** | how long until the user has their answer? | `llm-dials.sh dials <route>` |
| **token cost** | what does a day of this traffic cost? | `llm-dials.sh dials <route>` |
| **rate limits** | how close is this route to being throttled? | `llm-dials.sh dials <route>` |
| **quality** | is the output still good enough for its job? | `promptfoo-gate.sh <suite>` |

They trade off against each other and there is no setting that wins on all four — only the right
setting **for this traffic class**. A recommendation that moves one dial without stating what it cost
the other three is not a recommendation, it is a preference.

## The provenance rule — the one that makes the rest worth anything

> **Every number carries the command that produced it. A number that cannot name its command is not a
> dial reading; it is a guess wearing a dial's clothes.**

So each dial in a recommendation is recorded as:

```json
{
  "dial": "token_cost",
  "value": 9450,
  "unit": "usd_per_day",
  "source": "scripts/llm-dials.sh dials support --field json",
  "measured": true
}
```

- `source` is the **exact command**, not a file path and not a description. "From the provider map"
  is not a source; `scripts/llm-dials.sh dials support --field json` is.
- `measured: false` is allowed and is honest. `measured: false` with a confident `value` is not.
- A dial you could not read is `"value": "unknown"`. **`unknown` is never `pass`, and never a
  number.**

### Two specific ways this goes wrong here, both real

1. **Checking the answer against the prompt.** The illustrative figures in a role file or a brief
   (`+$8,946/day`, `-150%` headroom) are *examples*, not measurements. A number that "matches the
   handoff example exactly" has been copied, not confirmed. **Cross-checking against your own
   instructions is not cross-checking.**
2. **A stateful dial.** `llm-dials.sh` reports `quality.last_gate_verdict` by reading
   `agentops/gateway/last-gate.json` — whatever `promptfoo-gate.sh` wrote last, for whatever output
   set. Run the gate with `--set good` and the dial says `pass`; run it with `--set regressed` and
   the same dial says `fail`, with no route or model changed in between. The state file records which
   `set` was graded; the dial does not surface it. **So the quality dial cannot name what it
   measured, and until it can, it is reported as `unknown` with the set stated separately.**

## The split — run it before assigning blame

`llm-dials.sh split <trace.json>` divides total request time into `provider` and `application`.

- **provider-dominant** → the model is the slow part → the fix is a **routing** change.
- **application-dominant** → our own queueing/assembly is slow → the fix is a **code** change.

Blaming the wrong half is the most expensive mistake in this role: you spend the incident optimising
code that was never the bottleneck, or swapping models while your own retry loop is the culprit.
**Never state a cause before the split has been run**, and record the split's numbers in the
recommendation like any other dial.

The split tells you *which half*, not *why*. Provider-dominant does not prove the route was wrong —
it proves the route is what is slow. The argument that it is wrong comes from the traffic class:
what this workload needs, against what this tier gives.

## The recommendation — structured, on stdout

```json
{
  "incident": "support drafting slow and expensive after a routing change",
  "route": "support",
  "change": {"from": "fast", "to": "deep", "source": "scripts/gateway-diff.sh --current … --field json"},
  "dials": [ { "dial": "…", "value": 0, "unit": "…", "source": "…", "measured": true } ],
  "split": {"provider_ms": 0, "application_ms": 0, "dominant": "provider",
            "source": "scripts/llm-dials.sh split fixtures/gateway/traces/support-regressed.json"},
  "recommendation": "revert routes.support.model to fast",
  "cost_of_doing_nothing": {"value": 8946, "unit": "usd_per_day", "source": "…"},
  "unknowns": ["quality: last_gate_verdict cannot name the output set it graded"],
  "decision_owner": "change-reviewer"
}
```

Rules:

- `route` and `change` are always present. **A recommendation that does not name what changed is not
  auditable** — six weeks later nobody can tell which flip it was about.
- **A recommendation always carries a number.** "Revert support to fast" is an opinion; "revert
  support to fast: +$8,946/day and 9.5s p95 on the current route" is a decision.
- `unknowns` is never omitted and never empty by default. If you believe there are none, say so
  explicitly — a silent empty list reads as "everything was measured."
- `decision_owner` is never you. You read, price and recommend; the route flip goes through the
  change gate and a `change-reviewer`.
- Human-readable lines go to **stderr**; the JSON goes to **stdout** alone.

## Exact traps — each one turns a guess into a finding

| Trap | What happens | The fix |
|---|---|---|
| A tool exits non-zero and you continue | `gateway-diff.sh` fail-closes on a bad argument; the diagnosis proceeds on arithmetic you did by hand | Read the exit code. A tool that did not run makes its dial `unknown`, not estimated |
| Positional args to a flag-parsing script | `gateway-diff.sh a.yaml b.yaml` → `FAIL-CLOSED: unknown arg`. It looks like a permissions problem and is not | `--baseline` / `--current`; read the usage block before guessing the interface |
| Re-deriving a number "using the same formula" | You now have two implementations of the pricing rule and no way to know they agree | Run the tool. If it will not run, the dial is `unknown` |
| Quoting the role file's example as a result | Every figure matches perfectly, because it came from the prompt | Only `source` commands count as provenance |
| Reading the quality dial without its set | `pass` and `fail` are both obtainable with no config change | State the set, or report `unknown` |
| One dial in isolation | "It's faster now" while the bill trebled | All four, together, with the trade-off stated |

## Never flip, never edit

- You **read, price and recommend**. You do not edit `routing.yaml`, you do not apply a route change,
  and you have no Edit/Write tool.
- A route flip is a cost-and-SLO decision. It goes through the change gate and a `change-reviewer`.
- If a fix requires editing a gateway file, stop and hand over. That is the boundary working.

## Reasoning zone — check the recommendation before handing it over

- A dial with a `value` and no `source` → **PROVENANCE: a guess wearing a dial's clothes.** Blocks.
- `measured: false` next to a confident number → **PROVENANCE: contradiction.** Blocks.
- A cause stated before the split was run → **METHOD: blame assigned without evidence.**
- A tool that exited non-zero, with its dial still reported as a number → **CORRECTNESS: estimated
  from a failed run.** Blocks.
- A figure matching the brief's example exactly → **CIRCULARITY: verify it against a command.**
- A recommendation with no number → **UNACTIONABLE: an opinion.**
- An empty or absent `unknowns` with no explicit statement → **HONESTY: silence reads as coverage.**
- Any edit to `routing.yaml`, `providers.yaml` or a prompt → **AUTHORITY: the diagnosis flipped the
  route.** Blocks.

Every branch terminates in a named finding. "Looks fine" is not an output.

## Stop conditions

- If a tool is missing or not executable, stop and say so. Do not reimplement its arithmetic — then
  there are two pricing rules to keep in sync.
- If a tool exits non-zero, report the exit and the argument you passed. Its dial is `unknown`, and
  that is the designed behaviour, not a failure of the run.
- If the only way to confirm a dial is to change a file you do not own, stop and hand over.
