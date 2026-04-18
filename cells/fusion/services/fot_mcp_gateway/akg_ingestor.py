#!/usr/bin/env python3
"""
FoT-MCP AKG Ingestor

Converts MCP ClaimEnvelopes into AKG graph structures using the fot_mcp.ttl ontology.
Creates and updates Digital Twins based on tool operations.

NO SYNTHETIC DATA. NO SIMULATIONS. ALL OPERATIONS ARE REAL.
"""

import json
import logging
from datetime import datetime
from typing import Any, Dict, List, Optional
import httpx

logger = logging.getLogger("fot-mcp-akg-ingestor")


class AKGIngestor:
    """
    Ingests MCP claims into the AKG knowledge graph.
    Creates graph structures aligned with fot_mcp.ttl ontology.
    """

    def __init__(
        self,
        arango_url: str,
        arango_db: str,
        arango_user: str,
        arango_password: str,
    ):
        self.arango_url = arango_url
        self.arango_db = arango_db
        self.auth = (arango_user, arango_password)
        self.client = httpx.AsyncClient(timeout=30.0)

    async def close(self):
        await self.client.aclose()

    async def _execute_aql(self, query: str, bind_vars: Dict[str, Any] = None) -> List[Any]:
        """Execute an AQL query - NO SIMULATION."""
        response = await self.client.post(
            f"{self.arango_url}/_db/{self.arango_db}/_api/cursor",
            json={"query": query, "bindVars": bind_vars or {}},
            auth=self.auth,
        )

        if response.status_code != 201:
            raise Exception(f"AQL execution failed: {response.status_code} - {response.text}")

        return response.json().get("result", [])

    async def _upsert_document(
        self,
        collection: str,
        key: str,
        doc: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Upsert a document - NO SIMULATION."""
        doc["_key"] = key

        response = await self.client.post(
            f"{self.arango_url}/_db/{self.arango_db}/_api/document/{collection}",
            json=doc,
            auth=self.auth,
            params={"overwriteMode": "replace"},
        )

        if response.status_code not in (200, 201, 202):
            raise Exception(f"Document upsert failed: {response.status_code} - {response.text}")

        return response.json()

    async def _create_edge(
        self,
        collection: str,
        from_id: str,
        to_id: str,
        data: Dict[str, Any] = None,
    ) -> Dict[str, Any]:
        """Create an edge - NO SIMULATION."""
        edge = {
            "_from": from_id,
            "_to": to_id,
            **(data or {}),
        }

        response = await self.client.post(
            f"{self.arango_url}/_db/{self.arango_db}/_api/document/{collection}",
            json=edge,
            auth=self.auth,
        )

        if response.status_code not in (200, 201, 202):
            raise Exception(f"Edge creation failed: {response.status_code} - {response.text}")

        return response.json()

    # ─────────────────────────────────────────────────────────────────────────
    # MCP Server/Tool Registration
    # ─────────────────────────────────────────────────────────────────────────

    async def register_mcp_server(
        self,
        server_name: str,
        tools: List[Dict[str, Any]],
    ) -> str:
        """
        Register an MCP server and its tools in the AKG.
        Creates mcp:MCPServer and mcp:MCPTool nodes.
        """
        # Create server node
        server_doc = {
            "type": "mcp:MCPServer",
            "name": server_name,
            "registered_at": datetime.utcnow().isoformat(),
            "tool_count": len(tools),
        }

        await self._upsert_document("mcp_servers", server_name, server_doc)
        logger.info(f"✅ Registered MCP server: {server_name}")

        # Create tool nodes and edges
        for tool in tools:
            tool_key = f"{server_name}_{tool['name']}"
            tool_doc = {
                "type": "mcp:MCPTool",
                "name": tool["name"],
                "server_name": server_name,
                "risk_class": tool.get("risk_class", "LOW"),
                "mode": tool.get("mode", "PROPOSAL_ONLY"),
                "reads_twins": tool.get("reads_twins", []),
                "writes_twins": tool.get("writes_twins", []),
                "virtue_requirements": json.dumps(tool.get("virtue_requirements", {})),
            }

            await self._upsert_document("mcp_tools", tool_key, tool_doc)

            # Create edge from server to tool
            await self._create_edge(
                "mcp_has_tool",
                f"mcp_servers/{server_name}",
                f"mcp_tools/{tool_key}",
                {"type": "mcp:hasTool"},
            )

        logger.info(f"✅ Registered {len(tools)} tools for server: {server_name}")
        return f"mcp_servers/{server_name}"

    # ─────────────────────────────────────────────────────────────────────────
    # Claim Ingestion
    # ─────────────────────────────────────────────────────────────────────────

    async def ingest_claim(self, claim: Dict[str, Any]) -> str:
        """
        Ingest a claim into the AKG.
        Creates claim node and edges to:
          - MCP tool
          - Affected digital twins
          - Session (if exists)
          - Caller
        """
        claim_id = claim["claim_id"]

        # Create claim node
        claim_doc = {
            "type": self._get_claim_type(claim),
            "claim_id": claim_id,
            "caller_id": claim["caller_id"],
            "session_id": claim.get("session_id"),
            "client_id": claim.get("client_id"),
            "server_name": claim["server_name"],
            "tool_name": claim["tool_name"],
            "direction": claim["direction"],
            "input_snapshot": json.dumps(claim["input_snapshot"]),
            "output_snapshot": json.dumps(claim.get("output_snapshot")),
            "timestamp": claim["timestamp"],
            "hash_value": claim["hash_value"],
            "signature": claim.get("signature"),
            "chain_anchor": claim.get("chain_anchor"),
            "virtue_vector": json.dumps(claim.get("virtue_vector")),
            "risk_score": claim.get("risk_score"),
            "policy_decision": claim.get("policy_decision"),
            "eight_d_vector": claim.get("eight_d_vector"),
            "vqbit_id": claim.get("vqbit_id"),
            "coherence": claim.get("coherence"),
        }

        await self._upsert_document("mcp_claims", claim_id, claim_doc)

        # Create edge to tool
        tool_key = f"{claim['server_name']}_{claim['tool_name']}"
        await self._create_edge(
            "mcp_invokes_tool",
            f"mcp_claims/{claim_id}",
            f"mcp_tools/{tool_key}",
            {"type": "mcp:invokesTool", "timestamp": claim["timestamp"]},
        )

        # Create edges to affected twins
        for twin in claim.get("affects_twins", []):
            twin_id = await self._ensure_digital_twin(twin, claim)
            await self._create_edge(
                "mcp_affects_twin",
                f"mcp_claims/{claim_id}",
                twin_id,
                {"type": "mcp:affectsTwin", "timestamp": claim["timestamp"]},
            )

        # Create edge to session if exists
        if claim.get("session_id"):
            session_id = await self._ensure_session(claim["session_id"], claim["client_id"])
            await self._create_edge(
                "mcp_claim_in_session",
                f"mcp_claims/{claim_id}",
                session_id,
                {"type": "mcp:claimInSession"},
            )

        logger.info(f"✅ Ingested claim: {claim_id}")
        return f"mcp_claims/{claim_id}"

    def _get_claim_type(self, claim: Dict[str, Any]) -> str:
        """Determine claim type based on policy decision."""
        decision = claim.get("policy_decision", "")

        if decision == "ALLOW":
            return "mcp:TruthClaim"
        elif decision == "DENY":
            return "mcp:RejectedClaim"
        else:
            return "mcp:SuperposedClaim"

    async def _ensure_digital_twin(
        self,
        twin_type: str,
        claim: Dict[str, Any],
    ) -> str:
        """
        Ensure a digital twin exists in the AKG.
        Creates it if it doesn't exist.
        """
        # Extract twin key from type (e.g., "akg:CodeRepoTwin" -> "code_repo_twin")
        twin_key = twin_type.replace("akg:", "").lower()

        # For specific twins, try to extract identifier from claim
        input_data = claim.get("input_snapshot", {})

        if "CodeRepoTwin" in twin_type:
            repo = input_data.get("repo", input_data.get("repository", "unknown"))
            twin_key = f"repo_{repo.replace('/', '_')}"
        elif "PullRequestTwin" in twin_type:
            pr = input_data.get("pr_number", input_data.get("pull_request", "unknown"))
            twin_key = f"pr_{pr}"
        elif "WorkItemTwin" in twin_type:
            item = input_data.get("issue_id", input_data.get("ticket_id", "unknown"))
            twin_key = f"work_item_{item}"

        twin_doc = {
            "type": twin_type,
            "created_at": datetime.utcnow().isoformat(),
            "last_touched_by_claim": claim["claim_id"],
        }

        await self._upsert_document("digital_twins", twin_key, twin_doc)
        return f"digital_twins/{twin_key}"

    async def _ensure_session(
        self,
        session_id: str,
        client_id: Optional[str],
    ) -> str:
        """Ensure an MCP session exists in the AKG."""
        session_doc = {
            "type": "mcp:MCPSession",
            "session_id": session_id,
            "client_id": client_id,
            "created_at": datetime.utcnow().isoformat(),
        }

        await self._upsert_document("mcp_sessions", session_id, session_doc)
        return f"mcp_sessions/{session_id}"

    # ─────────────────────────────────────────────────────────────────────────
    # Collection Initialization
    # ─────────────────────────────────────────────────────────────────────────

    async def ensure_collections(self):
        """
        Ensure all required collections exist.
        NO SIMULATION - fails if ArangoDB unavailable.
        """
        collections = [
            ("mcp_servers", "document"),
            ("mcp_tools", "document"),
            ("mcp_claims", "document"),
            ("mcp_sessions", "document"),
            ("digital_twins", "document"),
            ("mcp_has_tool", "edge"),
            ("mcp_invokes_tool", "edge"),
            ("mcp_affects_twin", "edge"),
            ("mcp_claim_in_session", "edge"),
        ]

        for name, coll_type in collections:
            try:
                response = await self.client.post(
                    f"{self.arango_url}/_db/{self.arango_db}/_api/collection",
                    json={"name": name, "type": 2 if coll_type == "document" else 3},
                    auth=self.auth,
                )

                if response.status_code in (200, 201, 409):  # 409 = already exists
                    logger.info(f"✅ Collection ready: {name}")
                else:
                    raise Exception(f"Failed to create {name}: {response.text}")

            except Exception as e:
                logger.error(f"❌ Failed to ensure collection {name}: {e}")
                raise

        logger.info("✅ All MCP collections ready")

