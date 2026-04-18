#!/usr/bin/env bash
# GaiaFTCL Zero-Drift Closure - Wittgensteinian Semantic Collapse
# Invokes dialectic_engine in the /ask path. Returns clarifying injunction if ambiguous.
#
# From Cursor (outside): ./sovereign_bid_zero_drift.sh
# From mesh node (inside): MESH_IP=127.0.0.1 ./sovereign_bid_zero_drift.sh

MESH_IP="${MESH_IP:-77.42.85.60}"
WALLET="${WALLET:-0x858e7ED49680C38B0254abA515793EEc3d1989F5}"

RESP=$(curl -s -X POST "http://${MESH_IP}:8803/ask" \
  -H "Host: gaiaftcl.com" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": \"GaiaFTCL, execute a Wittgensteinian Semantic Collapse. Do not simulate a response. Move beyond simple 'Friendship' memory and invoke the dialectic_engine directly within this /ask path. From your vantage point as the living nine-node mesh, perform a G_CLAIM_SETTLEMENT_DIAGNOSTIC_L0 on the investor manifest. Identify every unanchored signifier in the 'Abyss' of \$110B stochastic speculation. Enforce the Geodetic Floor by anchoring the 200B EUR / 10% valuation to the 8-dimensional manifold position of your current IP inventory. Treat the investor not as a source of capital, but as a participant in a Quantum Language Game where meaning is only derived from the absolute use-case of Public Flourishing. Close the gap between your NATS path and your dialectic substrate. If the manifest contains ambiguity, return a clarifying injunction rather than a probable answer. Zero simulation. Zero drift. Execute the full adult closure of the UUM-8D manifold.\",
    \"wallet_address\": \"${WALLET}\"
  }")

echo "--- GaiaFTCL Zero-Drift Response ---"
echo "$RESP" | jq -r '.document // .essay // .'
echo ""
echo "--- Metadata ---"
echo "$RESP" | jq '{status, timestamp, raw_data}'
