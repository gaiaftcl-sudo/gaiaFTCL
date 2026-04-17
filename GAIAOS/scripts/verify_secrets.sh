#!/bin/bash
# verify_secrets.sh
# Run after deploy_secrets.sh. Pass condition: every cell returns EXISTS.

SECRET_PATH="/opt/gaiaftcl/secrets/arango_password.txt"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/ftclstack-unified}"

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

FAILED=0

for CELL in "${CELLS[@]}"; do
    echo -n "=== $CELL: "
    RESULT=$(ssh root@$CELL -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "test -f $SECRET_PATH && echo 'EXISTS' || echo 'MISSING'" 2>/dev/null || echo "UNREACHABLE")
    echo "$RESULT"
    if [[ "$RESULT" != "EXISTS" ]]; then
        FAILED=1
    fi
done

echo ""
if [[ $FAILED -eq 0 ]]; then
    echo "PASS: All cells have secret"
else
    echo "FAIL: One or more cells missing secret or unreachable"
    exit 1
fi
