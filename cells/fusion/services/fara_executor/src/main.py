#!/usr/bin/env python3
"""
Fara-7B Computer Use Executor
- Playwright browser automation
- FaraLM inference via vLLM API
- UUM-8D substrate trajectory recording
"""

import os
import asyncio
import logging
from datetime import datetime
from typing import Optional, Dict, Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import uvicorn

from .fara_agent import FaraAgent
from .substrate_writer import SubstrateWriter
from .exam_runner import ExamRunner

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# FastAPI app
app = FastAPI(title="Fara Executor Service", version="1.0.0")

# Config from environment
FARALM_URL = os.getenv("FARALM_URL", "http://faralm-vllm:8000")
ARANGO_URL = os.getenv("ARANGO_URL", "http://arangodb:8529")
SUBSTRATE_URL = os.getenv("SUBSTRATE_URL", "http://quantum-substrate:8000")
PORT = int(os.getenv("FARA_EXECUTOR_PORT", "8200"))

# Global instances
fara_agent: Optional[FaraAgent] = None
substrate_writer: Optional[SubstrateWriter] = None
exam_runner: Optional[ExamRunner] = None


class TaskRequest(BaseModel):
    """Request to execute a browser automation task"""
    task_description: str
    url: Optional[str] = None
    max_steps: int = 50
    headless: bool = True


class ExamRequest(BaseModel):
    """Request to run an exam"""
    exam_id: str
    model_id: str = "microsoft/Phi-3.5-vision-instruct"
    record_video: bool = True
    headless: bool = False


class ExamViaUIRequest(BaseModel):
    """Request to run exam via UI automation"""
    exam_domain: str
    ui_url: Optional[str] = "http://localhost:3000"
    num_questions: int = 5
    headless: bool = False
    record_video: bool = True


@app.on_event("startup")
async def startup():
    """Initialize services on startup"""
    global fara_agent, substrate_writer, exam_runner
    
    logger.info("Fara Executor starting...")
    logger.info(f"FaraLM URL: {FARALM_URL}")
    logger.info(f"ArangoDB URL: {ARANGO_URL}")
    logger.info(f"Substrate URL: {SUBSTRATE_URL}")
    
    # Initialize components
    fara_agent = FaraAgent(faralm_url=FARALM_URL)
    substrate_writer = SubstrateWriter(
        arango_url=ARANGO_URL,
        substrate_url=SUBSTRATE_URL
    )
    exam_runner = ExamRunner(
        fara_agent=fara_agent,
        substrate_writer=substrate_writer
    )
    
    logger.info("✅ Fara Executor ready")


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "faralm_url": FARALM_URL,
        "arango_url": ARANGO_URL,
    }


@app.post("/execute")
async def execute_task(request: TaskRequest):
    """Execute a browser automation task"""
    if not fara_agent:
        raise HTTPException(status_code=503, detail="Fara agent not initialized")
    
    try:
        logger.info(f"Executing task: {request.task_description}")
        
        trajectory = await fara_agent.execute_task(
            task=request.task_description,
            start_url=request.url,
            max_steps=request.max_steps,
            headless=request.headless
        )
        
        # Write to substrate
        if substrate_writer and trajectory:
            await substrate_writer.write_trajectory(trajectory)
        
        return {
            "status": "success",
            "trajectory_id": trajectory.get("id"),
            "num_steps": len(trajectory.get("steps", [])),
            "result": trajectory.get("result")
        }
    
    except Exception as e:
        logger.error(f"Task execution failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/exam/run")
async def run_exam(request: ExamRequest):
    """Run a professional exam with FaraLM"""
    if not exam_runner:
        raise HTTPException(status_code=503, detail="Exam runner not initialized")
    
    try:
        logger.info(f"Running exam: {request.exam_id}")
        
        result = await exam_runner.run_exam(
            exam_id=request.exam_id,
            model_id=request.model_id,
            record_video=request.record_video,
            headless=request.headless
        )
        
        return {
            "status": "success",
            "exam_id": request.exam_id,
            "num_questions": result.get("num_questions"),
            "num_correct": result.get("num_correct"),
            "accuracy": result.get("accuracy"),
            "trajectory_id": result.get("trajectory_id"),
            "evidence_path": result.get("evidence_path")
        }
    
    except Exception as e:
        logger.error(f"Exam execution failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/exam/list")
async def list_exams():
    """List available exams"""
    if not exam_runner:
        raise HTTPException(status_code=503, detail="Exam runner not initialized")
    
    exams = await exam_runner.list_available_exams()
    return {"exams": exams}


@app.post("/exam/run-via-ui")
async def run_exam_via_ui(request: ExamViaUIRequest):
    """Run exam by driving the GaiaOS web UI with Playwright"""
    if not fara_agent:
        raise HTTPException(status_code=503, detail="Fara agent not initialized")
    
    try:
        logger.info(f"Running exam via UI: {request.exam_domain}")
        
        trajectory = await fara_agent.run_exam_via_ui(
            exam_domain=request.exam_domain,
            ui_url=request.ui_url,
            num_questions=request.num_questions,
            headless=request.headless,
            record_video=request.record_video
        )
        
        # Write to substrate
        if substrate_writer and trajectory:
            await substrate_writer.write_trajectory(trajectory)
        
        return {
            "status": "success",
            "trajectory_id": trajectory.get("id"),
            "exam_domain": request.exam_domain,
            "num_steps": trajectory.get("num_steps"),
            "num_questions": request.num_questions
        }
    
    except Exception as e:
        logger.error(f"UI exam execution failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/trajectory/{trajectory_id}")
async def get_trajectory(trajectory_id: str):
    """Get trajectory details from substrate"""
    if not substrate_writer:
        raise HTTPException(status_code=503, detail="Substrate writer not initialized")
    
    trajectory = await substrate_writer.get_trajectory(trajectory_id)
    if not trajectory:
        raise HTTPException(status_code=404, detail="Trajectory not found")
    
    return trajectory


def main():
    """Run the FastAPI server"""
    uvicorn.run(
        "src.main:app",
        host="0.0.0.0",
        port=PORT,
        log_level="info"
    )


if __name__ == "__main__":
    main()

