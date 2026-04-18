"""Ethereum-compatible signature verification (same message shape as fot_mcp_gateway/wallet_auth.py)."""

from __future__ import annotations

import time
from typing import Optional, Tuple

from eth_account import Account
from eth_account.messages import encode_defunct
from web3 import Web3

_w3 = Web3()


def is_valid_wallet_address(address: str) -> bool:
    try:
        return bool(_w3.is_address(address))
    except Exception:
        return False


def verify_signature(
    wallet_address: str,
    message: str,
    signature: str,
    timestamp: int,
    max_age_seconds: int = 300,
) -> Tuple[bool, Optional[str]]:
    try:
        current_time = int(time.time())
        age = abs(current_time - int(timestamp))
        if age > max_age_seconds:
            return False, f"Signature expired ({age}s old, max {max_age_seconds}s)"
        full_message = f"GaiaFTCL Authentication\nTimestamp: {timestamp}\nMessage: {message}"
        message_hash = encode_defunct(text=full_message)
        recovered = Account.recover_message(message_hash, signature=signature)
        if recovered.lower() != wallet_address.lower():
            return False, f"Signature mismatch: recovered {recovered}, claimed {wallet_address}"
        return True, None
    except Exception as e:
        return False, f"Signature verification error: {e}"
