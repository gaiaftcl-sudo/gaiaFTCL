#!/bin/bash
# Zero-friction channel navigation via discord:// deep link
# Usage: source channel_ids.env && ./gaia_jump.sh "$CHANNEL_ID_OWL_PROTOCOL"
# Or:    ./gaia_jump.sh <channel_id>

set -e
GUILD_ID="${DISCORD_GUILD_ID:?Set DISCORD_GUILD_ID (source channel_ids.env)}"
CHANNEL_ID="$1"

if [ -z "$CHANNEL_ID" ]; then
  echo "Usage: ./gaia_jump.sh [channel_id]"
  exit 1
fi

open "discord://discord.com/channels/${GUILD_ID}/${CHANNEL_ID}"
echo "JUMPED_TO: ${GUILD_ID}/${CHANNEL_ID}"
