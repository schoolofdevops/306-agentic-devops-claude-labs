#!/usr/bin/env bash
# Smoke-test the northstar-observer MCP server over stdio without a full MCP client.
# Sends an initialize + tools/list + one read call + one write attempt, and prints
# the raw JSON-RPC responses. Used by the lab to see the read-only boundary directly.
set -euo pipefail

SERVER="${SERVER:-platform/mcp-servers/northstar-observer.js}"
SERVICE="${1:-orders-api}"

printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"get_readiness\",\"arguments\":{\"service\":\"$SERVICE\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"restart\",\"arguments\":{\"service\":\"$SERVICE\"}}}" \
  | node "$SERVER"
