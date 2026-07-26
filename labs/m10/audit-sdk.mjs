#!/usr/bin/env node
// audit-sdk.mjs — the Terraform estate audit as an Agent SDK fan-out.
//
// This is the WORKFLOW from the core lab, rebuilt in code with the Claude Agent
// SDK (@anthropic-ai/claude-agent-sdk). The shell version (audit-orchestrate.sh)
// expressed the fan-out with `&` and `wait`; here every orchestration control
// from the lesson becomes an explicit line you wrote:
//
//   * PARTITION (no duplication) — one worker per module, over a deduped set.
//   * BOUNDED CONCURRENCY (no runaway) — a semaphore caps in-flight workers at N,
//     the SDK equivalent of the shell's --max-parallel batch barrier.
//   * NORMALIZED JOIN — every worker returns the SAME record shape {module,
//     security_findings, cost_delta_usd, verdict}, so the join is a merge of
//     comparable records, not a pile of free-form agent prose.
//
// Two modes, one orchestration:
//
//   --live       Each module worker is a real SDK agent: query() with a per-worker
//                system prompt, a pinned model, a read-only tool set, and a turn
//                budget. Requires the SDK installed and an API key. This is the
//                production shape — swap the deterministic worker for a real agent
//                and the fan-out/join around it does not change.
//
//   --simulate   (default) Each worker is the SAME deterministic evidence read the
//                shell workflow uses, so the run is reproducible and gradeable with
//                no API in the loop. The ORCHESTRATION (partition, semaphore, join)
//                is identical to --live; only the worker body differs. This is why
//                the two modes produce the same normalized report.
//
// The point of the Deep Dive is exactly that comparison: the SDK buys you explicit
// control (a real semaphore, per-worker models, measured cost/latency) at the price
// of writing the fan-out yourself. --simulate lets you see the orchestration shape
// and grade it; --live lets you measure what the explicitness costs in tokens and
// time.
//
// Usage:  node audit-sdk.mjs [--simulate|--live] [--max-parallel N] [--modules "a b c"]
// Exit 0  -> normalized report printed as JSON
// Exit 1  -> FAIL-CLOSED: duplicate/phantom module, bad cap, or --live without the SDK

import { readFileSync, existsSync, readdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, "..", "..");
const MODULES_DIR = join(REPO_ROOT, "infra", "modules");
const PLAN_OVERSIZE = join(REPO_ROOT, "infra", "fixtures", "plan-oversize.json");

// ---- args ----
const argv = process.argv.slice(2);
let mode = "simulate";
let maxParallel = 2;
let modules = ["networking", "database", "compute", "storage"];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--live") mode = "live";
  else if (argv[i] === "--simulate") mode = "simulate";
  else if (argv[i] === "--max-parallel") maxParallel = Number(argv[++i]);
  else if (argv[i] === "--modules") modules = argv[++i].trim().split(/\s+/);
  else failClosed(`unknown arg '${argv[i]}'`);
}

function failClosed(msg) {
  process.stderr.write(`audit-sdk: FAIL-CLOSED: ${msg}\n`);
  process.exit(1);
}

// ---- fail-closed guards (same contract as the shell workflow) ----
if (!Number.isInteger(maxParallel) || maxParallel < 1)
  failClosed(`--max-parallel must be an integer >= 1 (got ${maxParallel})`);

const seen = new Set();
for (const m of modules) {
  if (seen.has(m)) failClosed(`duplicate module in fan-out: ${m}`);
  seen.add(m);
}
for (const m of modules) {
  if (!existsSync(join(MODULES_DIR, m)))
    failClosed(`no module directory infra/modules/${m}`);
}

// ---- the deterministic worker (shared by --simulate; the fallback for --live) ----
// Real, sourced findings, identical to the shell workflow's audit_one():
//   security_findings = count of 0.0.0.0/0 CIDRs in the module's HCL
//   cost_delta_usd    = the db.r6g.4xlarge blow-up, on the database module
function auditDeterministic(m) {
  const dir = join(MODULES_DIR, m);
  let security = 0;
  for (const f of walkHcl(dir)) {
    const body = readFileSync(f, "utf8");
    security += (body.match(/0\.0\.0\.0\/0/g) || []).length;
  }
  let cost = 0;
  if (m === "database" && existsSync(PLAN_OVERSIZE)) {
    const plan = JSON.parse(readFileSync(PLAN_OVERSIZE, "utf8"));
    const bigDb = (plan.resource_changes || []).some(
      (rc) =>
        rc.type === "aws_db_instance" &&
        rc.change?.after?.instance_class === "db.r6g.4xlarge"
    );
    if (bigDb) cost = 2847;
  }
  const verdict =
    security > 0 && cost > 0 ? "block" : security > 0 || cost > 0 ? "flag" : "clean";
  return { module: m, security_findings: security, cost_delta_usd: cost, verdict };
}

function walkHcl(dir) {
  const out = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...walkHcl(p));
    else if (e.name.endsWith(".tf")) out.push(p);
  }
  return out;
}

// ---- the live worker: a real Agent SDK agent per module ----
// One query() per module, each a read-only auditor with a pinned model and a turn
// budget. The agent inspects the module and returns the SAME normalized record.
// This is the production shape; --simulate swaps this body for auditDeterministic
// while keeping the orchestration (semaphore + join) byte-for-byte identical.
async function auditLive(m) {
  let query;
  try {
    ({ query } = await import("@anthropic-ai/claude-agent-sdk"));
  } catch {
    failClosed(
      "--live requires @anthropic-ai/claude-agent-sdk installed (npm i @anthropic-ai/claude-agent-sdk) and an API key"
    );
  }
  const dir = join(MODULES_DIR, m);
  const prompt =
    `You are a read-only IaC auditor for the Northstar '${m}' module at ${dir}. ` +
    `Count 0.0.0.0/0 CIDRs (security_findings) and any cost blast radius. ` +
    `Return ONLY a JSON object: ` +
    `{"module":"${m}","security_findings":<int>,"cost_delta_usd":<int>,"verdict":"clean|flag|block"}.`;

  let last = "";
  for await (const msg of query({
    prompt,
    options: {
      model: "claude-haiku-4-5-20251001", // right-sized: a mechanical read (M9)
      allowedTools: ["Read", "Grep", "Glob"], // read-only worker
      maxTurns: 6, // turn budget — bounded depth per worker
      cwd: REPO_ROOT,
    },
  })) {
    if (msg.type === "assistant") {
      for (const block of msg.message.content || []) {
        if (block.type === "text") last = block.text;
      }
    }
    // The SDK's final "result" message carries usage + total_cost_usd, which is
    // where you would tally per-worker token cost for the Deep Dive's comparison.
  }
  const match = last.match(/\{[\s\S]*\}/);
  if (!match) failClosed(`live worker for '${m}' returned no JSON record`);
  return JSON.parse(match[0]);
}

// ---- bounded-concurrency fan-out (the semaphore) ----
// At most `maxParallel` workers run at once — the SDK equivalent of the shell's
// batch barrier and the runaway-concurrency control. The RESULT is independent of
// the cap: workers write into a fixed-index slot, so the join order is stable
// regardless of completion order.
async function fanOut(worker) {
  const results = new Array(modules.length);
  let next = 0;
  async function runner() {
    while (true) {
      const i = next++;
      if (i >= modules.length) return;
      results[i] = await worker(modules[i]);
    }
  }
  const pool = Array.from({ length: Math.min(maxParallel, modules.length) }, runner);
  await Promise.all(pool);
  return results;
}

// ---- join: merge the per-module records into one normalized report ----
function joinReport(records) {
  const covered = records.map((r) => r.module).sort().join(",");
  const expected = [...modules].sort().join(",");
  if (covered !== expected) failClosed(`coverage mismatch (covered=${covered} expected=${expected})`);
  return {
    audit: "terraform-estate",
    orchestration: "agent-sdk",
    mode,
    max_parallel: maxParallel,
    modules_audited: records.map((r) => r.module),
    total_security_findings: records.reduce((a, r) => a + r.security_findings, 0),
    total_cost_delta_usd: records.reduce((a, r) => a + r.cost_delta_usd, 0),
    blocking: records.filter((r) => r.verdict === "block").map((r) => r.module),
    verdict: records.some((r) => r.verdict === "block")
      ? "block"
      : records.some((r) => r.verdict === "flag")
      ? "flag"
      : "clean",
    evidence: records,
  };
}

// ---- main ----
const worker = mode === "live" ? auditLive : (m) => Promise.resolve(auditDeterministic(m));
const records = await fanOut(worker);
process.stdout.write(JSON.stringify(joinReport(records), null, 2) + "\n");
