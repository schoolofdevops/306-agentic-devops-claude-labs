#!/usr/bin/env python3
"""error_budget.py — deterministic SLO error-budget and burn-rate analysis.

WHY THIS IS A SCRIPT AND NOT PROSE IN A SKILL
---------------------------------------------
Everything below is arithmetic over counters. There is exactly one correct
answer, and a language model asked to do it will produce a plausible one that
drifts between runs — wrong denominator, counters treated as gauges, a burn
rate divided by the wrong window. None of those failures look like failures.

So the model does not do this. It runs this, reads the verdict, and spends its
judgment on the part that actually needs judgment: whether to page a human at
2am given what else is happening tonight.

This is also the alternative to writing a Python "agent" (CrewAI, LangChain,
etc.) around the same logic. The logic is deterministic, so it does not need an
agent — it needs a script, and a skill that knows when to call it.

WHAT IT DOES
------------
Scrapes a Prometheus text-format /metrics endpoint twice, N seconds apart,
computes the request/error rate over that interval from the counter delta, and
turns it into the two numbers an SRE actually acts on: how much of the error
budget is being consumed, and how fast.

Burn rate = observed error rate / error budget. A burn rate of 1 spends exactly
the whole budget over the SLO window. A burn rate of 14.4 spends 2% of a 30-day
budget in one hour, which is the Google SRE fast-burn page threshold.

USAGE
    error_budget.py --url http://localhost:8080/metrics [--slo 0.99]
                    [--window 10] [--format json|text]

EXIT CODES
    0  budget healthy, no action
    1  fail-closed: could not scrape, or metrics missing (never guess)
    2  burn rate warrants a ticket
    3  burn rate warrants a page
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.request

# Google SRE multiwindow burn-rate thresholds. A burn rate of 14.4 consumes 2%
# of a 30-day budget in 1 hour; 6 consumes 5% in 6 hours.
PAGE_BURN_RATE = 14.4
TICKET_BURN_RATE = 6.0
WATCH_BURN_RATE = 1.0

# The counter this SLO is defined over, and the label that marks a failure.
REQUEST_COUNTER = "orders_api_requests_total"
ERROR_STATUS_PREFIX = "5"


def fail_closed(message):
    """Refuse rather than report a number we cannot stand behind."""
    print(f"error_budget: FAIL-CLOSED: {message}", file=sys.stderr)
    sys.exit(1)


def scrape(url, timeout=10):
    """Fetch a Prometheus text-format exposition page."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            if response.status != 200:
                fail_closed(f"{url} returned HTTP {response.status}")
            return response.read().decode("utf-8")
    except urllib.error.URLError as exc:
        fail_closed(f"cannot reach {url}: {exc.reason}")
    except OSError as exc:
        fail_closed(f"cannot reach {url}: {exc}")


def parse_labels(label_block):
    """Parse a Prometheus label block: status="200",method="GET" -> dict."""
    labels = {}
    for part in label_block.split(","):
        if "=" not in part:
            continue
        key, _, value = part.partition("=")
        labels[key.strip()] = value.strip().strip('"')
    return labels


def parse_counter(text, metric_name):
    """Sum a counter's samples into (total, errors) by the status label.

    Prometheus counters arrive as one line per label set:
        orders_api_requests_total{method="GET",path="/x",status="200"} 4.0
    """
    total = 0.0
    errors = 0.0
    found = False

    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if not line.startswith(metric_name):
            continue

        remainder = line[len(metric_name):]
        # Guard against matching a longer metric that shares this prefix
        # (e.g. *_total vs *_total_created).
        if remainder and remainder[0] not in "{ ":
            continue

        labels = {}
        if remainder.startswith("{"):
            close = remainder.rfind("}")
            if close == -1:
                continue
            labels = parse_labels(remainder[1:close])
            remainder = remainder[close + 1:]

        try:
            value = float(remainder.strip().split()[0])
        except (ValueError, IndexError):
            continue

        found = True
        total += value
        if labels.get("status", "").startswith(ERROR_STATUS_PREFIX):
            errors += value

    if not found:
        fail_closed(
            f"metric '{metric_name}' not present at the endpoint — "
            "the service may not be instrumented, or has served no traffic"
        )
    return total, errors


def classify(burn_rate):
    """Map a burn rate onto the action an on-call engineer should take."""
    if burn_rate >= PAGE_BURN_RATE:
        return "page", 3, (
            f"burn rate {burn_rate:.1f}x — at this pace a 30-day error budget "
            "is 2% gone within the hour"
        )
    if burn_rate >= TICKET_BURN_RATE:
        return "ticket", 2, (
            f"burn rate {burn_rate:.1f}x — sustained, this exhausts the budget "
            "well inside the SLO window"
        )
    if burn_rate >= WATCH_BURN_RATE:
        return "watch", 0, (
            f"burn rate {burn_rate:.1f}x — spending faster than budgeted but "
            "not fast enough to page"
        )
    return "ok", 0, f"burn rate {burn_rate:.2f}x — inside budget"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://localhost:8080/metrics")
    parser.add_argument("--slo", type=float, default=0.99,
                        help="availability objective, e.g. 0.99 for 99%%")
    parser.add_argument("--window", type=int, default=10,
                        help="seconds between the two samples")
    parser.add_argument("--format", choices=["json", "text"], default="json")
    args = parser.parse_args()

    if not 0 < args.slo < 1:
        fail_closed(f"--slo must be between 0 and 1, got {args.slo}")

    error_budget = 1.0 - args.slo

    first_total, first_errors = parse_counter(scrape(args.url), REQUEST_COUNTER)
    time.sleep(args.window)
    second_total, second_errors = parse_counter(scrape(args.url), REQUEST_COUNTER)

    # Counters only ever increase; a decrease means the process restarted and
    # the delta is meaningless. Refuse rather than report a negative rate.
    if second_total < first_total or second_errors < first_errors:
        fail_closed(
            "counter went backwards — the service restarted between samples, "
            "so this interval cannot be measured"
        )

    requests = second_total - first_total
    failures = second_errors - first_errors

    if requests == 0:
        fail_closed(
            f"no requests in {args.window}s — there is no traffic to measure. "
            "Drive some load, or widen --window"
        )

    observed_error_rate = failures / requests
    burn_rate = observed_error_rate / error_budget if error_budget else 0.0
    verdict, exit_code, reason = classify(burn_rate)

    report = {
        "slo_target": args.slo,
        "error_budget": round(error_budget, 6),
        "window_seconds": args.window,
        "requests": int(requests),
        "failures": int(failures),
        "observed_error_rate": round(observed_error_rate, 6),
        "burn_rate": round(burn_rate, 2),
        "verdict": verdict,
        "reason": reason,
    }

    if args.format == "json":
        print(json.dumps(report, indent=2))
    else:
        print(f"SLO {args.slo:.2%} | budget {error_budget:.2%}")
        print(f"{int(requests)} requests, {int(failures)} failures "
              f"in {args.window}s -> error rate {observed_error_rate:.2%}")
        print(f"burn rate {burn_rate:.2f}x -> {verdict.upper()}")
        print(reason)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
