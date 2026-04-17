#!/usr/bin/env python3
"""Usage: verify_game_room.py <GAIAOS_ROOT> <to-address>  → prints game_room"""
import importlib.util
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
mod_path = root / "services/mailcow_inbound_adapter/adapter.py"
spec = importlib.util.spec_from_file_location("inbound_adapter", mod_path)
mod = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(mod)
to_addr = sys.argv[2]
raw = f"From: t@test.com\nTo: {to_addr}\nSubject: x\n\nbody".encode()
print(mod.parse_mail(raw)["game_room"])
