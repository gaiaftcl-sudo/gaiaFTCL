#!/usr/bin/env python3
"""
G_FREESTYLE_L0 Axiom Verification - AQL Operations
Shared AQL queries for substrate-verifiable axioms.
Used by axiom_audit.py and referenced in G_FREESTYLE_L0.ttl.
"""

# Axiom 1: Non-extractive exchange of vQbits
# A turn is non-extractive when it contributes (discovery_refs or entropy reduction)
AXIOM1_SINGLE = """
FOR e IN truth_envelopes
  FILTER e._key == @envelope_id
  FILTER LENGTH(e.turn_log) > 0
  LET last_turn = LAST(e.turn_log)
  LET has_discovery_refs = LENGTH(e.discovery_refs || []) > 0
  LET entropy_reduced = last_turn.entropy_after < last_turn.entropy_before
  RETURN {
    non_extractive: has_discovery_refs OR entropy_reduced,
    evidence: {
      discovery_refs_count: LENGTH(e.discovery_refs || []),
      entropy_before: last_turn.entropy_before,
      entropy_after: last_turn.entropy_after
    }
  }
"""

AXIOM1_BULK = """
FOR e IN truth_envelopes
  FILTER e.game_id == @game_id
  FILTER LENGTH(e.turn_log) > 0
  SORT e.created_at DESC
  LIMIT 100
  LET last_turn = LAST(e.turn_log)
  LET non_extractive = LENGTH(e.discovery_refs || []) > 0 OR last_turn.entropy_after < last_turn.entropy_before
  RETURN {
    envelope_id: e._key,
    non_extractive: non_extractive,
    discovery_refs: LENGTH(e.discovery_refs || []),
    entropy_delta: last_turn.entropy_before - last_turn.entropy_after
  }
"""

AXIOM1_BULK_ALL = """
FOR e IN truth_envelopes
  FILTER e.created_at >= @since
  FILTER LENGTH(e.turn_log) > 0
  LET last_turn = LAST(e.turn_log)
  LET non_extractive = LENGTH(e.discovery_refs || []) > 0 OR last_turn.entropy_after < last_turn.entropy_before
  RETURN { envelope_id: e._key, non_extractive: non_extractive }
"""

# Axiom 2: Geodetic Floor preservation
# manifold_position valid [0,1]^8, entropy non-increase
AXIOM2_SINGLE = """
FOR e IN truth_envelopes
  FILTER e._key == @envelope_id
  FILTER LENGTH(e.turn_log) > 0
  LET last_turn = LAST(e.turn_log)
  LET pos = e.manifold_position || []
  LET all_dims_valid = LENGTH(pos) == 8 AND MIN(pos) >= 0 AND MAX(pos) <= 1
  LET entropy_preserved = last_turn.entropy_after <= last_turn.entropy_before
  RETURN {
    geodetic_floor_preserved: all_dims_valid AND entropy_preserved,
    evidence: {
      manifold_valid: all_dims_valid,
      entropy_before: last_turn.entropy_before,
      entropy_after: last_turn.entropy_after
    }
  }
"""

AXIOM2_BULK = """
FOR e IN truth_envelopes
  FILTER e.game_id == @game_id
  FILTER e.created_at >= @since
  FILTER LENGTH(e.turn_log) > 0
  LET last_turn = LAST(e.turn_log)
  LET pos = e.manifold_position || []
  LET valid = LENGTH(pos) == 8 AND MIN(pos) >= 0 AND MAX(pos) <= 1
  LET preserved = last_turn.entropy_after <= last_turn.entropy_before
  RETURN { _key: e._key, geodetic_floor_ok: valid AND preserved }
"""

AXIOM2_BULK_ALL = """
FOR e IN truth_envelopes
  FILTER e.created_at >= @since
  FILTER LENGTH(e.turn_log) > 0
  LET last_turn = LAST(e.turn_log)
  LET pos = e.manifold_position || []
  LET valid = LENGTH(pos) == 8 AND MIN(pos) >= 0 AND MAX(pos) <= 1
  LET preserved = last_turn.entropy_after <= last_turn.entropy_before
  RETURN { _key: e._key, geodetic_floor_ok: valid AND preserved }
"""

# Axiom 3: Wallet as topological anchor
AXIOM3_WALLET = """
FOR e IN truth_envelopes
  FILTER e.wallet_address == @wallet
  SORT e.created_at DESC
  LIMIT 1
  RETURN {
    anchored: e.wallet_address != null AND LENGTH(e.manifold_position || []) == 8,
    wallet: e.wallet_address,
    manifold_position: e.manifold_position
  }
"""

AXIOM3_BULK_ALL = """
FOR e IN truth_envelopes
  FILTER e.created_at >= @since
  FILTER e.wallet_address != null
  LET pos = e.manifold_position || []
  LET anchored = LENGTH(pos) == 8 AND MIN(pos) >= 0 AND MAX(pos) <= 1
  RETURN { _key: e._key, wallet_anchored: anchored }
"""
