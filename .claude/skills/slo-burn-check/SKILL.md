---
name: slo-burn-check
description: Use when you need to know whether a Northstar service is burning its error budget fast enough to page someone — during an incident, before deciding severity, or when an alert fires and you want the budget maths behind it. Reports a burn rate and a recommended action; never changes anything.
---

# slo-burn-check

Answer one question: **is this fast enough to wake someone up?**

An SLO breach on its own is not an incident. What decides the response is how
fast the error budget is being consumed. A service at 2% errors is either fine
or a page depending entirely on the objective it is held to.

## Deterministic zone — run the analyser, do not compute this yourself

All of the arithmetic lives in a script. Run it:

```bash
python3 .claude/skills/slo-burn-check/scripts/error_budget.py \
  --url http://localhost:8080/metrics \
  --slo 0.99 \
  --window 12
```

`--slo` is the availability objective for the service under discussion. For
Northstar's `orders-api` the recording rules in
`observability/prometheus/rules/slo-orders.yml` alert above a 1% error rate, so
the objective is `0.99` unless the incident says otherwise.

**Do not calculate the burn rate, the error rate, or the budget yourself, and do
not estimate them from logs.** The script samples the counter twice, takes the
delta, and divides. That is the whole reason it exists: the maths has exactly one
right answer and reasoning your way to it produces a different plausible number
each time.

Exit codes carry the verdict, so the pipeline can branch without parsing:

| Exit | Meaning |
|---|---|
| 0 | inside budget, or spending slowly — no action |
| 1 | fail-closed: could not scrape, no traffic, or the process restarted mid-sample |
| 2 | ticket |
| 3 | page |

## Reasoning zone — turn the number into a decision

The script gives you a burn rate and a category. Your job is what it cannot know.

- **`page` (burn ≥ 14.4).** The budget is going in under an hour. Say so plainly,
  and name what is burning it — pair this with whatever the triage found.
- **`ticket` (burn ≥ 6).** Real, not immediate. Worth a ticket now; worth a page
  if it is still running in a few hours.
- **`watch` (burn ≥ 1).** Spending faster than budgeted. Only interesting if it is
  sustained or if a release is going out.
- **`ok` (burn < 1).** Inside budget. If an alert fired anyway, the alert
  threshold and the SLO disagree, and that is the finding.

Then apply the context the numbers do not contain:

- **Is a deploy in flight?** A high burn rate during a rollout is a rollback
  decision, not a debugging session.
- **Is the window representative?** A 12-second sample during a traffic trough is
  thin evidence. Say so rather than over-claiming.
- **Is this the cause or a symptom?** A burn rate tells you the cost, never the
  reason. If you do not know the reason, say the budget is burning and the cause
  is not yet established.

## Output

Written for a human deciding severity. Give the burn rate, the verdict, the
window it was measured over, and your recommendation in a sentence. Include the
raw JSON if they asked for something machine-readable.

Do not restate the arithmetic — they can read the numbers. State what to do.

## Stop conditions

- **If the script exits 1, report that and stop.** It refused because it could not
  measure — unreachable endpoint, no traffic in the window, or a counter that went
  backwards because the service restarted. Never fill the gap with an estimate.
- **A thin window is a caveat, not a failure.** If the sample caught few requests,
  give the number and say the sample is small.
- **Report only.** This skill never restarts, scales, rolls back, or silences an
  alert. Those are decisions for the human reading the verdict.
