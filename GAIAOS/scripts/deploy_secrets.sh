#!/bin/bash
# deploy_secrets.sh
# Run once from your Mac. Propagates unified secret to all cells.
# Constitutional: Secret value never lives in git. Reads from local file only.
#
# Setup (one-time on Mac):
#   mkdir -p ~/.gaiaftcl_secrets
#   echo -n "gaiaftcl2026" > ~/.gaiaftcl_secrets/arango_password
#   chmod 600 ~/.gaiaftcl_secrets/arango_password

set -e

SECRET_FILE="${GAIAFTCL_SECRETS:-$HOME/.gaiaftcl_secrets}/arango_password"
SECRET_PATH="/opt/gaiaftcl/secrets/arango_password.txt"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/ftclstack-unified}"

if [[ ! -f "$SECRET_FILE" ]]; then
    echo "ERROR: Secret file not found: $SECRET_FILE"
    echo "Create it with: mkdir -p ~/.gaiaftcl_secrets && echo -n 'YOUR_PASSWORD' > ~/.gaiaftcl_secrets/arango_password && chmod 600 ~/.gaiaftcl_secrets/arango_password"
    exit 1
fi

SECRET_VALUE=$(cat "$SECRET_FILE")

CELLS=(
    "77.42.85.60"
    "135.181.88.134"
    "77.42.32.156"
    "77.42.88.110"
    "37.27.7.9"
    "37.120.187.247"
    "152.53.91.220"
    "152.53.88.141"
    "37.120.187.174"
)

for CELL in "${CELLS[@]}"; do
    echo "=== Deploying secret to $CELL ==="
    echo -n "$SECRET_VALUE" | ssh root@$CELL -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "mkdir -p /opt/gaiaftcl/secrets && cat > $SECRET_PATH && chmod 600 $SECRET_PATH && echo 'Secret deployed'"
done

echo "=== All cells updated ==="
