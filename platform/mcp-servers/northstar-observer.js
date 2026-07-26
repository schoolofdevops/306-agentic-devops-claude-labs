#!/usr/bin/env node
// Northstar read-only MCP observer.
//
// Speaks the Model Context Protocol over stdio (JSON-RPC 2.0, line-delimited).
// It exposes exactly three READ-ONLY tools and nothing else:
//   get_health      -> GET /healthz   (liveness)
//   get_readiness   -> GET /readyz    (dependency readiness)
//   get_info        -> GET /api/v1/info (build/runtime info)
//
// There is deliberately NO write tool. The agent cannot restart, scale, apply,
// or mutate anything through this server — not because a rule forbids it, but
// because no such tool exists in the interface. Read-only is a property of the
// tool set, not a promise in prose.
//
// Zero external dependencies: Node built-ins only, so the lab needs no npm install.

const http = require("http");

const PORTS = { "orders-api": 8080, "inventory-api": 8081 };

// ---- the tool surface: read-only, and that is the whole point -------------
const TOOLS = [
  {
    name: "get_health",
    description:
      "Liveness probe for a Northstar service. Returns the /healthz status. Read-only.",
    inputSchema: {
      type: "object",
      properties: {
        service: { type: "string", enum: ["orders-api", "inventory-api"] },
      },
      required: ["service"],
    },
    path: "/healthz",
  },
  {
    name: "get_readiness",
    description:
      "Readiness probe for a Northstar service. Returns /readyz including per-dependency checks. Read-only.",
    inputSchema: {
      type: "object",
      properties: {
        service: { type: "string", enum: ["orders-api", "inventory-api"] },
      },
      required: ["service"],
    },
    path: "/readyz",
  },
  {
    name: "get_info",
    description:
      "Build and runtime info for a Northstar service (version, hostname, container/k8s flags). Read-only.",
    inputSchema: {
      type: "object",
      properties: {
        service: { type: "string", enum: ["orders-api", "inventory-api"] },
      },
      required: ["service"],
    },
    path: "/api/v1/info",
  },
];

function fetchJson(port, path) {
  return new Promise((resolve) => {
    const req = http.get(
      { host: "localhost", port, path, timeout: 3000 },
      (res) => {
        let body = "";
        res.on("data", (c) => (body += c));
        res.on("end", () =>
          resolve({ http_status: res.statusCode, body: safeParse(body) })
        );
      }
    );
    req.on("error", (e) => resolve({ http_status: 0, error: String(e.message) }));
    req.on("timeout", () => {
      req.destroy();
      resolve({ http_status: 0, error: "timeout" });
    });
  });
}

function safeParse(s) {
  try {
    return JSON.parse(s);
  } catch {
    return s;
  }
}

async function callTool(name, args) {
  const tool = TOOLS.find((t) => t.name === name);
  if (!tool) throw new Error(`unknown tool: ${name}`);
  const service = (args && args.service) || "";
  const port = PORTS[service];
  if (!port) throw new Error(`unknown service: ${service}`);
  const result = await fetchJson(port, tool.path);
  return { service, endpoint: tool.path, ...result };
}

// ---- minimal JSON-RPC / MCP handling over stdio ---------------------------
function send(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

async function handle(msg) {
  const { id, method, params } = msg;
  // Notifications (no id) get no response.
  if (id === undefined || id === null) return;

  if (method === "initialize") {
    return send({
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: "2024-11-05",
        serverInfo: { name: "northstar-observer", version: "1.0.0" },
        capabilities: { tools: {} },
      },
    });
  }

  if (method === "tools/list") {
    return send({
      jsonrpc: "2.0",
      id,
      result: {
        tools: TOOLS.map(({ name, description, inputSchema }) => ({
          name,
          description,
          inputSchema,
        })),
      },
    });
  }

  if (method === "tools/call") {
    try {
      const out = await callTool(params.name, params.arguments || {});
      return send({
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify(out, null, 2) }],
        },
      });
    } catch (e) {
      return send({
        jsonrpc: "2.0",
        id,
        error: { code: -32602, message: String(e.message) },
      });
    }
  }

  // Any other method — including any write-shaped call — is simply not here.
  return send({
    jsonrpc: "2.0",
    id,
    error: { code: -32601, message: `method not found: ${method}` },
  });
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
