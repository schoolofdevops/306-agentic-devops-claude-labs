#!/usr/bin/env bash
# Smoke-test the secfindings MCP server over stdio without a full MCP client.
# Sends an initialize + tools/list + one findings_query + one corpus_summary +
# one write-shaped attempt, and prints the raw JSON-RPC responses. Same shape
# as labs/m7/probe-observer.sh — used by the lab to see the read-only
# boundary directly.
set -euo pipefail

SERVER="${SERVER:-platform/mcp-servers/secfindings/server.js}"

printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"corpus_summary","arguments":{}}}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"findings_query","arguments":{"tool":"trivy","severity":"critical"}}}' \
  '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"finding_resolve","arguments":{"id":"dep:vulnerable_service:PyYAML:CVE-2020-14343"}}}' \
  | node "$SERVER"
