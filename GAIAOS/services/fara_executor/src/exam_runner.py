"""
ExamRunner - Run professional exams using FaraAgent and record to substrate
"""

import os
import json
import logging
from typing import Dict, Any, List, Optional
from datetime import datetime
from pathlib import Path

logger = logging.getLogger(__name__)


class ExamRunner:
    """Runs exams with FaraAgent"""
    
    def __init__(self, fara_agent, substrate_writer):
        self.fara_agent = fara_agent
        self.substrate_writer = substrate_writer
        self.exams_dir = Path("/app/data/exams")
        self.evidence_dir = Path("/app/docs/exams/runs")
    
    async def list_available_exams(self) -> List[Dict[str, Any]]:
        """List available exams from catalog"""
        catalog_path = self.exams_dir / "EXAM_CATALOG_FULL.json"
        
        if not catalog_path.exists():
            logger.warning(f"Exam catalog not found: {catalog_path}")
            return []
        
        with open(catalog_path) as f:
            catalog = json.load(f)
        
        return catalog.get("exams", [])
    
    async def load_exam_questions(self, exam_id: str) -> List[Dict[str, Any]]:
        """Load exam questions from JSONL file"""
        exam_path = self.exams_dir / f"{exam_id}.jsonl"
        
        if not exam_path.exists():
            raise FileNotFoundError(f"Exam file not found: {exam_path}")
        
        questions = []
        with open(exam_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                q = json.loads(line)
                questions.append({
                    "id": q.get("id"),
                    "stem": q.get("stem") or q.get("question"),
                    "options": q.get("options") or q.get("choices"),
                    "correct": q.get("correct") or q.get("answer"),
                    "meta": {k: v for k, v in q.items()
                             if k not in ("id", "stem", "question", "options", "choices", "correct", "answer")}
                })
        
        return questions
    
    def _build_exam_task(self, question: Dict[str, Any]) -> str:
        """Build task description for a single exam question"""
        stem = question["stem"]
        options = question.get("options", [])
        
        if options:
            opts_text = "\n".join(f"{chr(65+i)}. {opt}" for i, opt in enumerate(options))
            return (
                f"You are taking a professional certification exam.\n\n"
                f"Question: {stem}\n\n"
                f"Options:\n{opts_text}\n\n"
                f"Provide your answer with reasoning."
            )
        else:
            return (
                f"You are taking a professional certification exam.\n\n"
                f"Question: {stem}\n\n"
                f"Provide your best answer with reasoning."
            )
    
    async def run_exam(
        self,
        exam_id: str,
        model_id: str = "microsoft/Phi-3.5-vision-instruct",
        record_video: bool = True,
        headless: bool = False
    ) -> Dict[str, Any]:
        """
        Run a complete exam with FaraAgent
        
        Returns exam results with evidence paths
        """
        logger.info(f"Starting exam: {exam_id}")
        
        # Load questions
        questions = await self.load_exam_questions(exam_id)
        logger.info(f"Loaded {len(questions)} questions for {exam_id}")
        
        # Create run directory
        run_timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        run_dir = self.evidence_dir / run_timestamp / exam_id
        run_dir.mkdir(parents=True, exist_ok=True)
        
        # Run each question
        results = []
        correct_count = 0
        
        for idx, question in enumerate(questions, start=1):
            logger.info(f"Question {idx}/{len(questions)}: {question['id']}")
            
            task = self._build_exam_task(question)
            
            try:
                # Execute with FaraAgent
                trajectory = await self.fara_agent.execute_task(
                    task=task,
                    start_url="about:blank",  # Start with blank page for exam
                    max_steps=10,  # Limit steps for exam questions
                    headless=headless
                )
                
                # Write to substrate
                await self.substrate_writer.write_trajectory(trajectory)
                
                # Extract answer from trajectory
                # (In real system, would parse last step's thought/action)
                answer = "A"  # Placeholder
                is_correct = (answer == question.get("correct"))
                
                if is_correct:
                    correct_count += 1
                
                result = {
                    "question_id": question["id"],
                    "question": question["stem"],
                    "correct_answer": question.get("correct"),
                    "model_answer": answer,
                    "is_correct": is_correct,
                    "trajectory_id": trajectory["id"],
                    "timestamp": datetime.utcnow().isoformat() + "Z"
                }
                
                results.append(result)
                
                # Write question result
                result_path = run_dir / f"question_{question['id']}.json"
                with open(result_path, "w") as f:
                    json.dump(result, f, indent=2)
            
            except Exception as e:
                logger.error(f"Question {question['id']} failed: {e}", exc_info=True)
                results.append({
                    "question_id": question["id"],
                    "error": str(e),
                    "timestamp": datetime.utcnow().isoformat() + "Z"
                })
        
        # Compute summary
        accuracy = correct_count / len(questions) if questions else 0.0
        
        summary = {
            "exam_id": exam_id,
            "model_id": model_id,
            "run_timestamp": run_timestamp,
            "num_questions": len(questions),
            "num_correct": correct_count,
            "accuracy": accuracy,
            "results": results,
            "evidence_path": str(run_dir)
        }
        
        # Write summary
        summary_path = run_dir / "exam_summary.json"
        with open(summary_path, "w") as f:
            json.dump(summary, f, indent=2)
        
        logger.info(f"✅ Exam {exam_id} complete: {correct_count}/{len(questions)} correct ({accuracy:.1%})")
        
        return summary

