#!/usr/bin/env bash
set -euo pipefail

OLD="0x858e7ED49680C38B0254abA515793EEc3d1989F5"
NEW="0x91f6e41B4425326e42590191c50Db819C587D866"

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

echo "EMERGENCY WALLET UPDATE - ALL 9 CELLS"
echo "Old: $OLD"
echo "New: $NEW"
echo ""

for cell in "${CELLS[@]}"; do
    echo "Updating $cell..."
    ssh -i ~/.ssh/qfot_unified root@$cell << ENDSSH
cd /root/GAIAOS
rg "$OLD" -l 2>/dev/null | while read file; do
    sed -i "s/$OLD/$NEW/g" "\$file"
    echo "  Updated: \$file"
done
# Update ArangoDB
docker exec gaiaftcl-arangodb arangosh --server.database gaiaos --server.password gaiaftcl2026 --javascript.execute-string "
db._query('FOR w IN authorized_wallets FILTER w.wallet_address == @old UPDATE w WITH {wallet_address: @new} IN authorized_wallets', {old: '$OLD', new: '$NEW'});
db._query('FOR w IN wallet_balances FILTER w.wallet_address == @old UPDATE w WITH {wallet_address: @new} IN wallet_balances', {old: '$OLD', new: '$NEW'});
print('Updated ArangoDB');
" 2>/dev/null || echo "  ArangoDB update skipped"
ENDSSH
    echo "  ✓ $cell updated"
done

echo ""
echo "✅ ALL CELLS UPDATED"
