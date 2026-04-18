#!/usr/bin/env bash
# Run on the head after rsync/git pull: expand discord-forest.env to full key set without
# clobbering existing values. Does not enable DISCORD_FOREST_FULL_DEPLOY.
set -euo pipefail
ROOT="${GAIAOS_ROOT:-/opt/gaia/GAIAOS}"
ENV_DST="${DISCORD_FOREST_ENV_PATH:-/etc/gaiaftcl/discord-forest.env}"
SECRETS="${GAIAFTCL_SECRETS_PATH:-/etc/gaiaftcl/secrets.env}"
cd "$ROOT"
ts="$(date +%s)"
if [ -f "$ENV_DST" ]; then
  cp -a "$ENV_DST" "${ENV_DST}.bak.${ts}"
fi
python3 scripts/merge_discord_forest_env.py \
  --repo-root "$ROOT" \
  --current "$ENV_DST" \
  --secrets "$SECRETS" \
  --set ARANGO_DB=gaiaftcl \
  --out "${ENV_DST}.new"
mv "${ENV_DST}.new" "$ENV_DST"
chmod 600 "$ENV_DST"
echo "Merged $ENV_DST (backup ${ENV_DST}.bak.${ts}). Next: fill tokens, then:"
echo "  python3 $ROOT/scripts/validate_discord_forest_full_deploy.py --repo-root $ROOT --env-file $ENV_DST"
