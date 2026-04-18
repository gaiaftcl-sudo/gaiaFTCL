"""
SubstrateWriter - Write Fara trajectories to UUM-8D substrate (ArangoDB)
Implements the fara:CUAStep + uum:UUM8DState encoding contract
"""

import logging
import hashlib
from typing import Dict, Any, Optional, List
from datetime import datetime
import json

import aiohttp

logger = logging.getLogger(__name__)


class SubstrateWriter:
    """Writes Fara CUA trajectories to the substrate"""
    
    def __init__(self, arango_url: str, substrate_url: str):
        self.arango_url = arango_url.rstrip("/")
        self.substrate_url = substrate_url.rstrip("/")
    
    def _compute_uum8d_state(self, step: Dict[str, Any]) -> Dict[str, float]:
        """
        Compute UUM-8D state vector for a CUA step
        
        Dimensions (virtue-based encoding):
        d0: task_alignment (0-1)
        d1: action_confidence (0-1)
        d2: sensory_complexity (screenshot entropy proxy)
        d3: reasoning_depth (thought length proxy)
        d4: temporal_coherence (step index normalization)
        d5: interaction_intensity (action type weight)
        d6: goal_progress (estimated)
        d7: error_likelihood (0-1)
        """
        
        thought = step.get("thought", "")
        action = step.get("action", {})
        action_type = action.get("action", "wait")
        step_idx = step.get("step_index", 0)
        
        # Simple heuristic encodings (real system would use learned embeddings)
        action_weights = {
            "visit_url": 0.9,
            "left_click": 0.8,
            "type": 0.7,
            "web_search": 0.85,
            "scroll": 0.4,
            "key": 0.6,
            "wait": 0.2,
            "terminate": 1.0,
        }
        
        return {
            "d0": 0.8,  # task_alignment (would be learned)
            "d1": 0.75,  # action_confidence (would come from model logits)
            "d2": 0.6,  # sensory_complexity (would be computed from screenshot)
            "d3": min(len(thought) / 200.0, 1.0),  # reasoning_depth
            "d4": min(step_idx / 50.0, 1.0),  # temporal_coherence
            "d5": action_weights.get(action_type, 0.5),  # interaction_intensity
            "d6": 0.5,  # goal_progress (would be estimated)
            "d7": 0.1,  # error_likelihood (would be predicted)
        }
    
    def _compute_vqbit_hash(self, step: Dict[str, Any], uum8d: Dict[str, float]) -> str:
        """Compute vQbit hash for a CUA step"""
        # Hash combines: thought + action + UUM-8D state
        content = json.dumps({
            "thought": step.get("thought", ""),
            "action": step.get("action", {}),
            "uum8d": uum8d
        }, sort_keys=True)
        
        return hashlib.sha256(content.encode()).hexdigest()[:16]
    
    async def write_trajectory(self, trajectory: Dict[str, Any]) -> str:
        """
        Write a complete Fara CUA trajectory to the substrate
        
        Returns trajectory_id
        """
        trajectory_id = trajectory.get("id")
        logger.info(f"Writing trajectory {trajectory_id} to substrate...")
        
        # Build substrate records
        substrate_payload = {
            "trajectory_id": trajectory_id,
            "task": trajectory.get("task"),
            "start_url": trajectory.get("start_url"),
            "start_time": trajectory.get("start_time"),
            "end_time": trajectory.get("end_time"),
            "num_steps": trajectory.get("num_steps"),
            "result": trajectory.get("result"),
            "steps": []
        }
        
        for step in trajectory.get("steps", []):
            # Compute UUM-8D state
            uum8d_state = self._compute_uum8d_state(step)
            
            # Compute vQbit hash
            vqbit_hash = self._compute_vqbit_hash(step, uum8d_state)
            
            # Build step record
            step_record = {
                "step_index": step.get("step_index"),
                "timestamp": step.get("timestamp"),
                "thought": step.get("thought"),
                "action": step.get("action"),
                "result": step.get("result"),
                "uum8d_state": uum8d_state,
                "vqbit_hash": vqbit_hash,
                "screenshot_hash": hashlib.sha256(
                    step.get("screenshot", "").encode()
                ).hexdigest()[:16]
            }
            
            substrate_payload["steps"].append(step_record)
        
        # Write to substrate via REST API
        url = f"{self.substrate_url}/fara/trajectories"
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(url, json=substrate_payload) as resp:
                    if resp.status not in (200, 201):
                        text = await resp.text()
                        logger.error(f"Substrate write failed: {resp.status} {text}")
                        raise Exception(f"Substrate write error: {resp.status}")
                    
                    logger.info(f"✅ Trajectory {trajectory_id} written to substrate")
                    return trajectory_id
        
        except aiohttp.ClientError as e:
            logger.error(f"Substrate write network error: {e}")
            # Fallback: write to local file
            fallback_path = f"/tmp/fara_trajectories/{trajectory_id}.json"
            with open(fallback_path, "w") as f:
                json.dump(substrate_payload, f, indent=2)
            logger.warning(f"Wrote to fallback: {fallback_path}")
            return trajectory_id
    
    async def get_trajectory(self, trajectory_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve a trajectory from substrate"""
        url = f"{self.substrate_url}/fara/trajectories/{trajectory_id}"
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(url) as resp:
                    if resp.status == 404:
                        return None
                    
                    if resp.status != 200:
                        logger.error(f"Substrate read failed: {resp.status}")
                        return None
                    
                    return await resp.json()
        
        except aiohttp.ClientError as e:
            logger.error(f"Substrate read error: {e}")
            return None

