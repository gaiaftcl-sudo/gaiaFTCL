#!/usr/bin/env bash
set -euo pipefail

FOUNDER_ADDRESS="${FOUNDER_ADDRESS:-0x91f6e41B4425326e42590191c50Db819C587D866}"

docker exec gaiaftcl-arangodb arangosh \
    --server.database gaiaos \
    --server.password gaiaftcl2026 \
    --javascript.execute-string "
const db = require('@arangodb').db;

// Update or insert founder wallet in authorized_wallets
const wallets = db._collection('authorized_wallets');
const existing = wallets.firstExample({wallet_address: '$FOUNDER_ADDRESS'});
if (existing) {
    wallets.update(existing._key, {
        wallet_address: '$FOUNDER_ADDRESS',
        access_level: 'founder',
        created_at: existing.created_at || new Date().toISOString(),
        updated_at: new Date().toISOString()
    });
    print('Updated founder wallet: $FOUNDER_ADDRESS');
} else {
    wallets.insert({
        _key: 'founder_primary',
        wallet_address: '$FOUNDER_ADDRESS',
        access_level: 'founder',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
    });
    print('Inserted founder wallet: $FOUNDER_ADDRESS');
}

// Remove old dead wallet if exists
const old = wallets.firstExample({wallet_address: '0x858e7ED49680C38B0254abA515793EEc3d1989F5'});
if (old) {
    wallets.remove(old._key);
    print('Removed old wallet: 0x858e7ED49680C38B0254abA515793EEc3d1989F5');
}

print('✅ Founder wallet seeded successfully');
"
