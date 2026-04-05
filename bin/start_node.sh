#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# start_node.sh
# Fetches the local Tailscale IP and boots the Hermes BEAM Elixir node with
# the correct Erlang distribution flags.
#
# Required env vars:
#   NODE_TYPE   hub | worker
#   NODE_ROLE   gaming_gpu | mac_mini_pro | mac_mini_base
#   HUB_IP      Tailscale IP of the Hub (required for workers)
#   DB_PASS     Postgres password
#   COOKIE      Erlang magic cookie (keep this secret!)
# ---------------------------------------------------------------------------
set -euo pipefail

COOKIE="${COOKIE:-hermes_beam_default_cookie_change_me}"

# Fetch the Tailscale IP of this machine so the Erlang node name is stable
# and reachable by other nodes over the mesh VPN.
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "127.0.0.1")

echo "======================================="
echo " Hermes BEAM Node Startup"
echo " NODE_TYPE : ${NODE_TYPE:-worker}"
echo " NODE_ROLE : ${NODE_ROLE:-mac_mini_base}"
echo " Tailscale IP : $TAILSCALE_IP"
echo "======================================="

exec elixir \
  --name "hermes@${TAILSCALE_IP}" \
  --cookie "${COOKIE}" \
  --erl "+K true +A 64" \
  -S mix run --no-halt
