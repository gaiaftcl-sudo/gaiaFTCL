"""
Gap 3: user_profiles wallet+uum_8d, conversation_threads by wallet.
"""
import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "services", "gaiaos_substrate"))


@pytest.mark.asyncio
async def test_get_or_create_by_wallet_returns_uum_8d(arango_auth, test_wallet):
    """user_profiles.get_or_create_by_wallet returns profile with uum_8d."""
    from user_profiles import UserProfileManager
    mgr = UserProfileManager(
        arango_url=os.getenv("ARANGO_URL", "http://localhost:8529"),
        arango_db=os.getenv("ARANGO_DB", "gaiaos"),
        arango_user=os.getenv("ARANGO_USER", "root"),
        arango_pass=os.getenv("ARANGO_PASSWORD", "gaiaftcl2026"),
    )
    try:
        profile = await mgr.get_or_create_by_wallet(test_wallet, uum_8d=[0.5] * 8)
        assert "uum_8d" in profile
        assert len(profile["uum_8d"]) == 8
        assert profile.get("wallet_address") == test_wallet
    finally:
        await mgr.close()


@pytest.mark.asyncio
async def test_get_or_create_thread_by_wallet(arango_auth, test_wallet):
    """ConversationContextManager.get_or_create_thread_by_wallet creates/retrieves by wallet."""
    from conversation_context import ConversationContextManager
    mgr = ConversationContextManager(
        arango_url=os.getenv("ARANGO_URL", "http://localhost:8529"),
        arango_db=os.getenv("ARANGO_DB", "gaiaos"),
        arango_user=os.getenv("ARANGO_USER", "root"),
        arango_pass=os.getenv("ARANGO_PASSWORD", "gaiaftcl2026"),
    )
    try:
        thread = await mgr.get_or_create_thread_by_wallet(test_wallet)
        assert thread is not None
        assert thread.get("wallet_address") == test_wallet
        assert "turns" in thread
    finally:
        await mgr.close()
