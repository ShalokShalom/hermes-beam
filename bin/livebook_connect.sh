#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# livebook_connect.sh
#
# Launches Livebook pre-attached to the running Hermes BEAM Hub node.
# The Hub must already be running (bin/start_node.sh with NODE_TYPE=hub).
#
# Usage:
#   bash bin/livebook_connect.sh            # attach to local Hub (dev)
#   bash bin/livebook_connect.sh prod       # attach to remote Hub over Tailscale
#
# Required env vars (prod only):
#   HUB_IP    Tailscale IP of the Hub
#   COOKIE    Erlang magic cookie (same as used to start Hub)
# ---------------------------------------------------------------------------
set -euo pipefail

COOKIE="${COOKIE:-hermes_beam_default_cookie_change_me}"
MODE="${1:-dev}"

export LIVEBOOK_HOME="${LIVEBOOK_HOME:-$PWD/notebooks}"

case "$MODE" in
  prod)
    HUB_IP="${HUB_IP:?HUB_IP must be set for prod mode}"
    HUB_NODE="hermes@${HUB_IP}"

    echo "======================================="
    echo " Livebook -> Hermes BEAM [PRODUCTION]"
    echo " Hub node  : $HUB_NODE"
    echo " Notebooks : $LIVEBOOK_HOME"
    echo "======================================="

    export LIVEBOOK_DEFAULT_RUNTIME="attached:${HUB_NODE}:${COOKIE}"
    export LIVEBOOK_NODE="livebook@127.0.0.1"
    export LIVEBOOK_DISTRIBUTION="name"
    ;;

  *)
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "127.0.0.1")
    DEV_NODE="hermes@${TAILSCALE_IP}"

    echo "======================================="
    echo " Livebook -> Hermes BEAM [DEV]"
    echo " Hub node  : $DEV_NODE"
    echo " Notebooks : $LIVEBOOK_HOME"
    echo "======================================="

    export LIVEBOOK_DEFAULT_RUNTIME="attached:${DEV_NODE}:${COOKIE}"
    export LIVEBOOK_NODE="livebook_dev@127.0.0.1"
    ;;
esac

livebook server
