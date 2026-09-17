#!/usr/bin/env bash
# Canonical presenter entrypoint for the Act-based Saudi Aramco demo.
#
# Usage:
#   STEP_MODE=1 ./demos/mcp-gateway-lifecycle-demo.sh
#   STEP_MODE=1 SEED_DEMO=1 ./demos/mcp-gateway-lifecycle-demo.sh

set -euo pipefail
GIT_ROOT="$(git rev-parse --show-toplevel)"
exec "${GIT_ROOT}/aramco-mcp-lifecycle/mcp-gateway-lifecycle-demo.sh" "$@"
