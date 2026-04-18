import pytest
from unittest.mock import AsyncMock, MagicMock, patch

# Test 1: Game room routing
def test_game_room_routing():
    from services.discord_frontier.shared.cell_base import parse_channel_to_game_room

    assert parse_channel_to_game_room("owl-protocol") == "owl_protocol"
    assert parse_channel_to_game_room("discovery") == "discovery"
    assert parse_channel_to_game_room("governance") == "governance"
    assert parse_channel_to_game_room("treasury") == "treasury"
    assert parse_channel_to_game_room("sovereign-mesh") == "sovereign_mesh"
    assert parse_channel_to_game_room("receipts") == "receipt_wall"
    assert parse_channel_to_game_room("ask-franklin") == "ask_franklin"
    assert parse_channel_to_game_room("unknown") == "unclassified"


# Test 2: Wallet gate fires on unknown wallet
@pytest.mark.asyncio
async def test_wallet_gate_blocks_unknown():
    from services.discord_frontier.shared.wallet_bridge import check_wallet_registered

    with patch("aiohttp.ClientSession.get") as mock_get:
        mock_get.return_value.__aenter__ = AsyncMock(
            return_value=MagicMock(
                status=404,
                json=AsyncMock(return_value={"found": False}),
            )
        )
        mock_get.return_value.__aexit__ = AsyncMock(return_value=None)
        result = await check_wallet_registered("unknown_discord_user_123")
        assert result is False


# Test 3: Envelope payload structure
def test_envelope_payload_structure():
    from services.discord_frontier.shared.envelope_manager import build_envelope_payload

    payload = build_envelope_payload(
        sender="test_user",
        game_room="owl_protocol",
        content="maternal parity data exists",
        cell_id="gaiaftcl-discord-bot-owl",
    )
    assert payload["type"] == "MAIL"
    assert payload["game_room"] == "owl_protocol"
    assert payload["from"] == "test_user"
    assert "ttl" in payload
    assert payload["envelope_status"] == "OPEN"


# Test 4: NATS infinite retry config
def test_nats_infinite_retry_config():
    from services.discord_frontier.shared.nats_reconnect import get_nats_options

    opts = get_nats_options()
    assert opts.get("max_reconnect_attempts") == -1
    assert opts.get("reconnect_time_wait") is not None


# Test 5: Lineage structure
def test_lineage_structure():
    from services.discord_frontier.shared.lineage import build_lineage

    lineage = build_lineage(
        cell_id="gaiaftcl-discord-bot-owl",
        mother_id="gaiaftcl-discord-app-01",
        game_room="owl_protocol",
    )
    assert lineage["cell_id"] == "gaiaftcl-discord-bot-owl"
    assert lineage["mother"] == "gaiaftcl-discord-app-01"
    assert lineage["origin"] == "gaiaftcl-mac-origin-01"
    assert lineage["game_room"] == "owl_protocol"
    assert "inception_at" in lineage
