"""Real signature round-trip for Owl /moor (no HTTP mocks)."""

import time

from eth_account import Account
from eth_account.messages import encode_defunct

from services.discord_frontier.shared.inception_wallet import (
    inception_sign_message,
    is_valid_wallet_address,
    verify_signature,
)


# Public Hardhat-style account #0 — never holds mainnet funds; test-only.
_TEST_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
_TEST_ADDR = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"


def test_is_valid_wallet_address_accepts_checksummed_and_lower():
    assert is_valid_wallet_address(_TEST_ADDR) is True
    assert is_valid_wallet_address(_TEST_ADDR.lower()) is True
    assert is_valid_wallet_address("0xnot") is False
    assert is_valid_wallet_address("") is False


def test_verify_signature_round_trip_fresh_timestamp():
    discord_id = "123456789012345678"
    inner = inception_sign_message(discord_id)
    ts = int(time.time())
    full = f"GaiaFTCL Authentication\nTimestamp: {ts}\nMessage: {inner}"
    signed = Account.sign_message(encode_defunct(text=full), private_key=_TEST_KEY)
    ok, err = verify_signature(_TEST_ADDR, inner, signed.signature.hex(), ts, max_age_seconds=600)
    assert ok is True
    assert err is None


def test_verify_signature_rejects_stale_timestamp():
    discord_id = "999"
    inner = inception_sign_message(discord_id)
    old_ts = int(time.time()) - 10_000
    full = f"GaiaFTCL Authentication\nTimestamp: {old_ts}\nMessage: {inner}"
    signed = Account.sign_message(encode_defunct(text=full), private_key=_TEST_KEY)
    ok, err = verify_signature(_TEST_ADDR, inner, signed.signature.hex(), old_ts, max_age_seconds=300)
    assert ok is False
    assert err is not None
    assert "expired" in (err or "").lower() or "old" in (err or "").lower()


def test_verify_signature_rejects_wrong_wallet_claim():
    discord_id = "555"
    inner = inception_sign_message(discord_id)
    ts = int(time.time())
    full = f"GaiaFTCL Authentication\nTimestamp: {ts}\nMessage: {inner}"
    signed = Account.sign_message(encode_defunct(text=full), private_key=_TEST_KEY)
    other = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
    ok, err = verify_signature(other, inner, signed.signature.hex(), ts, max_age_seconds=600)
    assert ok is False
    assert err is not None
