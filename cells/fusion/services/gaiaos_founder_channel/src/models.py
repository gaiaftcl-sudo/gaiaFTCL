from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any, Union
from datetime import datetime
import uuid

class MoveBase(BaseModel):
    move_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    game_id: str
    from_role: str
    created_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    witness_hash: Optional[str] = None

class MoveSpeech(MoveBase):
    kind: str = "SPEECH"
    text: str
    context_refs: List[str] = []

class MoveProposeQState(MoveBase):
    kind: str = "QSTATE_PROPOSAL"
    proposal: Dict[str, Any] # { intent, candidate_claims, required_evidence_refs, suggested_truth_envelope_type }

class MoveTruthEnvelope(MoveBase):
    kind: str = "TRUTH"
    envelope_type: str
    claims: List[Dict[str, Any]]
    evidence_refs: List[str]
    provenance: str
    binding_effects: Dict[str, List[Any]] # { akg_writes, registry_updates, actions }

class ThreadStatusEnvelope(BaseModel):
    game_id: str
    state: str # OPEN, QUIET, ESCALATED, CLOSED
    summary: str
    created_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
