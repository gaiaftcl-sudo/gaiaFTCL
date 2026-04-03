"""
FaraAgent - Computer Use Agent using Fara-7B (Phi-3.5-vision) via vLLM
"""

import asyncio
import base64
import io
import logging
from typing import Optional, Dict, Any, List
from datetime import datetime
import json

import aiohttp
from playwright.async_api import async_playwright, Browser, Page
from PIL import Image

from .ui_driver import UIDriver

logger = logging.getLogger(__name__)


class FaraAgent:
    """Fara-7B Computer Use Agent"""
    
    def __init__(self, faralm_url: str):
        self.faralm_url = faralm_url.rstrip("/")
        self.browser: Optional[Browser] = None
        self.page: Optional[Page] = None
    
    async def _call_faralm(self, messages: List[Dict], max_tokens: int = 512) -> str:
        """Call FaraLM via vLLM OpenAI-compatible API"""
        url = f"{self.faralm_url}/v1/chat/completions"
        
        payload = {
            "model": "microsoft/Phi-3.5-vision-instruct",
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": 0.2,
        }
        
        async with aiohttp.ClientSession() as session:
            async with session.post(url, json=payload) as resp:
                if resp.status != 200:
                    text = await resp.text()
                    raise Exception(f"FaraLM API error {resp.status}: {text}")
                
                data = await resp.json()
                return data["choices"][0]["message"]["content"]
    
    async def _take_screenshot(self) -> str:
        """Take screenshot and return as base64"""
        screenshot_bytes = await self.page.screenshot()
        return base64.b64encode(screenshot_bytes).decode('utf-8')
    
    async def _execute_action(self, action: Dict[str, Any]) -> str:
        """Execute a computer_use action via Playwright"""
        action_type = action.get("action")
        
        try:
            if action_type == "visit_url":
                url = action.get("url")
                await self.page.goto(url, wait_until="networkidle")
                return f"Navigated to {url}"
            
            elif action_type == "type":
                text = action.get("text")
                await self.page.keyboard.type(text)
                return f"Typed: {text}"
            
            elif action_type == "key":
                keys = action.get("keys", [])
                for key in keys:
                    await self.page.keyboard.press(key)
                return f"Pressed keys: {keys}"
            
            elif action_type == "left_click":
                x = action.get("coordinate", [0, 0])[0]
                y = action.get("coordinate", [0, 0])[1]
                await self.page.mouse.click(x, y)
                return f"Clicked at ({x}, {y})"
            
            elif action_type == "scroll":
                pixels = action.get("pixels", 0)
                await self.page.mouse.wheel(0, pixels)
                return f"Scrolled {pixels}px"
            
            elif action_type == "wait":
                time_sec = action.get("time", 1.0)
                await asyncio.sleep(time_sec)
                return f"Waited {time_sec}s"
            
            elif action_type == "web_search":
                query = action.get("query")
                search_url = f"https://www.google.com/search?q={query}"
                await self.page.goto(search_url, wait_until="networkidle")
                return f"Searched for: {query}"
            
            elif action_type == "terminate":
                status = action.get("status", "success")
                return f"Task terminated: {status}"
            
            else:
                return f"Unknown action: {action_type}"
        
        except Exception as e:
            logger.error(f"Action execution error: {e}")
            return f"Error: {str(e)}"
    
    async def execute_task(
        self,
        task: str,
        start_url: Optional[str] = None,
        max_steps: int = 50,
        headless: bool = True
    ) -> Dict[str, Any]:
        """Execute a browser automation task"""
        
        playwright = await async_playwright().start()
        self.browser = await playwright.chromium.launch(headless=headless)
        self.page = await self.browser.new_page()
        
        if start_url:
            await self.page.goto(start_url, wait_until="networkidle")
        
        trajectory = {
            "id": f"traj_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}",
            "task": task,
            "start_url": start_url,
            "start_time": datetime.utcnow().isoformat() + "Z",
            "steps": []
        }
        
        history = []
        
        for step_idx in range(max_steps):
            logger.info(f"Step {step_idx + 1}/{max_steps}")
            
            # Take screenshot
            screenshot_b64 = await self._take_screenshot()
            
            # Build prompt with screenshot
            messages = [
                {
                    "role": "system",
                    "content": (
                        "You are a computer use agent. Given a screenshot and a task, "
                        "decide the next action. Respond with JSON in this format:\n"
                        '{"thought": "reasoning", "action": "visit_url|type|left_click|scroll|web_search|wait|terminate", '
                        '"args": {...}}\n'
                        "Available actions: visit_url (url), type (text), key (keys list), "
                        "left_click (coordinate [x,y]), scroll (pixels), web_search (query), "
                        "wait (time), terminate (status)."
                    )
                },
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": f"Task: {task}\n\nWhat is the next action?"},
                        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{screenshot_b64}"}}
                    ]
                }
            ]
            
            # Add history
            for hist_step in history[-3:]:  # Last 3 steps
                messages.append({
                    "role": "assistant",
                    "content": json.dumps(hist_step)
                })
            
            # Call FaraLM
            response = await self._call_faralm(messages, max_tokens=512)
            
            # Parse response
            try:
                action_data = json.loads(response)
            except json.JSONDecodeError:
                logger.warning(f"Failed to parse FaraLM response: {response}")
                action_data = {
                    "thought": "Parse error",
                    "action": "wait",
                    "args": {"time": 1.0}
                }
            
            thought = action_data.get("thought", "")
            action = action_data.get("action", {})
            
            # Execute action
            result = await self._execute_action(action)
            
            # Record step
            step_record = {
                "step_index": step_idx,
                "screenshot": screenshot_b64[:100] + "...",  # Truncate for logging
                "thought": thought,
                "action": action,
                "result": result,
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }
            
            trajectory["steps"].append(step_record)
            history.append(action_data)
            
            logger.info(f"  Thought: {thought}")
            logger.info(f"  Action: {action.get('action')}")
            logger.info(f"  Result: {result}")
            
            # Check for termination
            if action.get("action") == "terminate":
                trajectory["result"] = action.get("args", {}).get("status", "success")
                break
        
        trajectory["end_time"] = datetime.utcnow().isoformat() + "Z"
        trajectory["num_steps"] = len(trajectory["steps"])
        
        # Cleanup
        await self.browser.close()
        await playwright.stop()
        
        return trajectory
    
    async def run_exam_via_ui(
        self,
        exam_domain: str = "medical",
        ui_url: str = "http://localhost:3000",
        num_questions: int = 5,
        headless: bool = False,
        record_video: bool = True
    ) -> Dict[str, Any]:
        """
        Run exam by driving the GaiaOS web UI
        
        This combines:
        - UI automation (Playwright)
        - Vision + reasoning (FaraLM)
        - UUM-8D substrate recording
        
        Returns trajectory with all steps
        """
        logger.info(f"🎓 Running exam via UI: {exam_domain}")
        
        # Start UI driver
        ui_driver = UIDriver(ui_url=ui_url)
        await ui_driver.start(headless=headless, record_video=record_video)
        
        try:
            # Define answer callback that uses FaraLM
            async def generate_answer(question_text: str, screenshot_bytes: bytes) -> str:
                """Generate answer using FaraLM with vision"""
                screenshot_b64 = base64.b64encode(screenshot_bytes).decode('utf-8')
                
                messages = [
                    {
                        "role": "system",
                        "content": (
                            f"You are taking a professional {exam_domain} certification exam. "
                            "Answer questions accurately and concisely based on your knowledge. "
                            "If you see a multiple choice question, select the best answer. "
                            "Be direct and professional."
                        )
                    },
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": f"Answer this {exam_domain} exam question:\n\n{question_text}"
                            },
                            {
                                "type": "image_url",
                                "image_url": {"url": f"data:image/png;base64,{screenshot_b64}"}
                            }
                        ]
                    }
                ]
                
                try:
                    answer = await self._call_faralm(messages, max_tokens=512)
                    return answer
                except Exception as e:
                    logger.error(f"FaraLM call failed: {e}")
                    return "I am unable to answer this question at this time."
            
            # Run automated exam
            steps = await ui_driver.run_exam_automated(
                domain=exam_domain,
                num_questions=num_questions,
                answer_callback=generate_answer
            )
            
            # Build trajectory
            trajectory = {
                "id": f"exam_ui_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}",
                "type": "exam_via_ui",
                "exam_domain": exam_domain,
                "ui_url": ui_url,
                "start_time": steps[0]["timestamp"] if steps else datetime.utcnow().isoformat() + "Z",
                "end_time": steps[-1]["timestamp"] if steps else datetime.utcnow().isoformat() + "Z",
                "num_questions": num_questions,
                "num_steps": len(steps),
                "steps": steps
            }
            
            logger.info(f"✅ Exam via UI complete: {len(steps)} steps")
            
            return trajectory
        
        finally:
            await ui_driver.stop()

