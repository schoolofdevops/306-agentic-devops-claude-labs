#!/usr/bin/env node
// secfindings — read-only MCP server over Northstar's combined security scan
// corpus (agentops/secops/scan-corpus.json, produced by
// platform/secfixtures/scan.sh).
//
// M3 + M7 teaching point: trivy + gitleaks + the posture scanners together
// emit a few hundred findings. That does not fit one context window, and it
// should not be pasted into one. So the corpus is not handed to the agent as
// a blob — it is QUERIED, a bounded read per question, the same discipline
// M3 asks for evidence generally.
//
// Speaks MCP over stdio (JSON-RPC 2.0, line-delimited), same shape as
// platform/mcp-servers/northstar-observer.js. It exposes exactly three
// READ-ONLY tools and nothing else:
//   findings_query(component?, severity?, tool?, reachable?) -> matching findings, capped
//   finding_get(id)                                          -> one finding in full
//   corpus_summary()                                         -> counts by tool/severity + corpus timestamp
//
// There is deliberately NO write tool, and no tool that marks a finding
// resolved, triaged, or ranked. A finding's rank/reachable verdict is written
// by the triage roles into their own handoff packets and ultimately into
// agentops/secops/verdict.json by security-reviewer — never back into this
// server or the corpus it reads. A capability that does not exist cannot be
// misused: there is no code path in this file that opens the corpus file (or
// any other file) for writing.
//
// Zero external dependencies: Node built-ins only, so the lab needs no npm install.

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");
const CORPUS_PATH =
  process.env.SECFINDINGS_CORPUS ||
  path.join(REPO_ROOT, "agentops", "secops", "scan-corpus.json");

const RESULT_CAP = 50;

// ---- the tool surface: read-only, and that is the whole point -------------
const TOOLS = [
  {
    name: "findings_query",
    description:
      "Query the combined security scan corpus (trivy dependency/image CVEs, gitleaks secrets, " +
      "posture findings) by component, severity, source tool, and/or reachability verdict. " +
      "Returns matching findings, capped at " +
      RESULT_CAP +
      ", with a note when results were truncated. Read-only — does not rank or mutate anything.",
    inputSchema: {
      type: "object",
      properties: {
        component: {
          type: "string",
          description: "Substring match against the finding's component (package@version, file path, or manifest name).",
        },
        severity: {
          type: "string",
          description: "Exact match, case-insensitive: critical | high | medium | low | unknown.",
        },
        tool: {
          type: "string",
          description: "Exact match: trivy | gitleaks | secops-surface-scan.sh.",
        },
        reachable: {
          type: "string",
          description:
            "Exact match: yes | no | unknown. Note: the raw scan corpus does not compute " +
            "reachability itself — every finding starts 'unknown' here until a triage role " +
            "(dep-triage, via the reachability-check skill) determines it. This server never " +
            "writes that verdict back; it only reflects what the corpus recorded at scan time.",
        },
      },
    },
  },
  {
    name: "finding_get",
    description: "Fetch one finding in full by its id (as returned by findings_query or corpus_summary).",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "Finding id, e.g. 'dep:vulnerable_service:PyYAML:CVE-2020-14343'." },
      },
      required: ["id"],
    },
  },
  {
    name: "corpus_summary",
    description:
      "Counts of findings by source tool and by severity, plus the corpus's generated_at timestamp. " +
      "Use this before findings_query to know the shape of what's there.",
    inputSchema: { type: "object", properties: {} },
  },
];

// ---- corpus loading + normalization ----------------------------------------
// Every read here is fs.readFileSync in "r" mode. Nothing in this file ever
// opens CORPUS_PATH (or any other path) for writing.

function loadCorpusRaw() {
  if (!fs.existsSync(CORPUS_PATH)) {
    return { error: `no scan corpus at ${CORPUS_PATH} — run platform/secfixtures/scan.sh first` };
  }
  try {
    const text = fs.readFileSync(CORPUS_PATH, "utf8");
    return { data: JSON.parse(text) };
  } catch (e) {
    return { error: `corpus at ${CORPUS_PATH} could not be read/parsed: ${e.message}` };
  }
}

function normalizeDependencyFindings(depFindings) {
  const out = [];
  if (!depFindings || typeof depFindings !== "object") return out;
  for (const [service, report] of Object.entries(depFindings)) {
    const results = (report && report.Results) || [];
    for (const result of results) {
      const target = result.Target || service;
      const vulns = result.Vulnerabilities || [];
      for (const v of vulns) {
        out.push({
          id: `dep:${service}:${v.PkgName}:${v.VulnerabilityID}`,
          tool: "trivy",
          finding_class: "dependency",
          component: `${v.PkgName}@${v.InstalledVersion}`,
          severity: (v.Severity || "unknown").toLowerCase(),
          reachable: "unknown", // the corpus never computes this — see findings_query docstring
          service,
          target,
          cve: v.VulnerabilityID,
          title: v.Title || "",
          fixed_version: v.FixedVersion || null,
          cvss_v3: (v.CVSS && v.CVSS.nvd && v.CVSS.nvd.V3Score) || (v.CVSS && v.CVSS.ghsa && v.CVSS.ghsa.V3Score) || null,
          description: v.Description || "",
        });
      }
    }
  }
  return out;
}

function normalizeSecretFindings(secretFindings) {
  const out = [];
  // scan.sh writes secret_findings via --slurpfile, which wraps gitleaks.json's
  // own top-level array in another array (secret_findings == [ [...] ]).
  // .flat() unwraps that one level of nesting regardless of which shape shows up.
  const arr = Array.isArray(secretFindings) ? secretFindings.flat() : [];
  for (const s of arr) {
    out.push({
      id: `secret:${s.Fingerprint || `${s.File}:${s.StartLine}:${s.RuleID}`}`,
      tool: "gitleaks",
      finding_class: "secret",
      component: s.File || "unknown",
      severity: "high", // gitleaks does not score severity; a committed credential defaults high until secret-triage assesses liveness
      reachable: "unknown",
      rule_id: s.RuleID || "",
      description: s.Description || "",
      line: s.StartLine || null,
      commit: s.Commit || null,
      author: s.Author || null,
      date: s.Date || null,
    });
  }
  return out;
}

const POSTURE_SEVERITY = {
  cluster_admin: "critical",
  wide_cidr: "critical",
  wide_open_ingress: "high",
  broad_iam: "medium",
};

function normalizePostureFindings(postureFindings) {
  const out = [];
  if (!postureFindings || typeof postureFindings !== "object") return out;
  for (const [category, paths] of Object.entries(postureFindings)) {
    if (!Array.isArray(paths)) continue; // skip count/verdict scalar fields
    for (const p of paths) {
      out.push({
        id: `posture:${category}:${p}`,
        tool: "secops-surface-scan.sh",
        finding_class: "posture",
        component: p,
        severity: POSTURE_SEVERITY[category] || "unknown",
        reachable: "unknown",
        category,
      });
    }
  }
  return out;
}

function buildIndex() {
  const loaded = loadCorpusRaw();
  if (loaded.error) return { error: loaded.error, findings: [], generatedAt: null };
  const data = loaded.data;
  const findings = [
    ...normalizeDependencyFindings(data.dependency_findings),
    ...normalizeSecretFindings(data.secret_findings),
    ...normalizePostureFindings(data.posture_findings),
  ];
  return { error: null, findings, generatedAt: data.generated_at || null };
}

// ---- tool implementations ---------------------------------------------------

function findingsQuery(args) {
  const { error, findings } = buildIndex();
  if (error) return { error };

  const { component, severity, tool, reachable } = args || {};
  let matches = findings;
  if (component) {
    const needle = String(component).toLowerCase();
    matches = matches.filter((f) => f.component.toLowerCase().includes(needle));
  }
  if (severity) {
    const want = String(severity).toLowerCase();
    matches = matches.filter((f) => f.severity === want);
  }
  if (tool) {
    matches = matches.filter((f) => f.tool === tool);
  }
  if (reachable) {
    const want = String(reachable).toLowerCase();
    matches = matches.filter((f) => f.reachable === want);
  }

  const total = matches.length;
  const truncated = total > RESULT_CAP;
  const page = matches.slice(0, RESULT_CAP).map((f) => ({
    id: f.id,
    tool: f.tool,
    finding_class: f.finding_class,
    component: f.component,
    severity: f.severity,
    reachable: f.reachable,
  }));

  return {
    count_returned: page.length,
    count_total_matched: total,
    truncated,
    note: truncated
      ? `truncated: ${total} findings matched, showing first ${RESULT_CAP}. Narrow with component/severity/tool/reachable, or call finding_get on a specific id.`
      : null,
    findings: page,
  };
}

function findingGet(args) {
  const { error, findings } = buildIndex();
  if (error) return { error };
  const id = args && args.id;
  if (!id) return { error: "finding_get requires an 'id' argument" };
  const found = findings.find((f) => f.id === id);
  if (!found) return { error: `no finding with id '${id}'` };
  return { finding: found };
}

function corpusSummary() {
  const { error, findings, generatedAt } = buildIndex();
  if (error) return { error };

  const byTool = {};
  const bySeverity = {};
  for (const f of findings) {
    byTool[f.tool] = (byTool[f.tool] || 0) + 1;
    bySeverity[f.severity] = (bySeverity[f.severity] || 0) + 1;
  }

  return {
    corpus_path: CORPUS_PATH,
    generated_at: generatedAt,
    total_findings: findings.length,
    by_tool: byTool,
    by_severity: bySeverity,
  };
}

async function callTool(name, args) {
  switch (name) {
    case "findings_query":
      return findingsQuery(args || {});
    case "finding_get":
      return findingGet(args || {});
    case "corpus_summary":
      return corpusSummary();
    default:
      throw new Error(`unknown tool: ${name}`);
  }
}

// ---- minimal JSON-RPC / MCP handling over stdio ---------------------------
function send(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

async function handle(msg) {
  const { id, method, params } = msg;
  if (id === undefined || id === null) return; // notifications get no response

  if (method === "initialize") {
    return send({
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: "2024-11-05",
        serverInfo: { name: "secfindings", version: "1.0.0" },
        capabilities: { tools: {} },
      },
    });
  }

  if (method === "tools/list") {
    return send({
      jsonrpc: "2.0",
      id,
      result: {
        tools: TOOLS.map(({ name, description, inputSchema }) => ({ name, description, inputSchema })),
      },
    });
  }

  if (method === "tools/call") {
    try {
      const out = await callTool(params.name, params.arguments || {});
      return send({
        jsonrpc: "2.0",
        id,
        result: { content: [{ type: "text", text: JSON.stringify(out, null, 2) }] },
      });
    } catch (e) {
      return send({ jsonrpc: "2.0", id, error: { code: -32602, message: String(e.message) } });
    }
  }

  // Any other method — including any write-shaped call — is simply not here.
  return send({ jsonrpc: "2.0", id, error: { code: -32601, message: `method not found: ${method}` } });
}

let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buf += chunk;
  let nl;
  while ((nl = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, nl).trim();
    buf = buf.slice(nl + 1);
    if (!line) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }
    handle(msg);
  }
});
