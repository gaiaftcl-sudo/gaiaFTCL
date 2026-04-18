"""
UI Driver for Fara Automation
Drives the GaiaOS exam UI using Playwright and records to UUM-8D substrate
"""
import asyncio
import json
import logging
from typing import Dict, Any, List, Optional
from datetime import datetime
from pathlib import Path

from playwright.async_api import Page, Browser, async_playwright

logger = logging.getLogger(__name__)


class UIDriver:
    """Drives the GaiaOS exam UI with Playwright"""
    
    def __init__(self, ui_url: str = "http://localhost:3000"):
        self.ui_url = ui_url
        self.browser: Optional[Browser] = None
        self.page: Optional[Page] = None
        self.playwright = None
        
        # UI element selectors (discovered)
        self.selectors = {
            "exam_mode_btn": "#exam-mode-btn",
            "exam_domain_select": "#exam-domain",
            "start_exam_btn": "#start-exam-btn",
            "chat_input": "#chat-input",
            "send_btn": "#send-btn",
            "messages_container": "#messages-container",
            "message_user": ".message.user",
            "message_assistant": ".message.assistant",
        }
    
    async def start(self, headless: bool = False, record_video: bool = False):
        """Start the browser and navigate to UI"""
        logger.info(f"🌐 Starting UI driver for {self.ui_url}")
        
        self.playwright = await async_playwright().start()
        
        # Browser options
        browser_opts = {
            "headless": headless,
            "args": ["--no-sandbox", "--disable-setuid-sandbox"]
        }
        
        # Video recording setup
        if record_video:
            video_dir = Path("/tmp/fara_videos")
            video_dir.mkdir(exist_ok=True)
            browser_opts["record_video_dir"] = str(video_dir)
            browser_opts["record_video_size"] = {"width": 1920, "height": 1080}
        
        self.browser = await self.playwright.chromium.launch(**browser_opts)
        
        context_opts = {
            "viewport": {"width": 1920, "height": 1080},
            "user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) GaiaOS/1.0 FaraAgent"
        }
        
        context = await self.browser.new_context(**context_opts)
        self.page = await context.new_page()
        
        # Navigate to UI
        logger.info(f"📡 Navigating to {self.ui_url}")
        await self.page.goto(self.ui_url, wait_until="networkidle", timeout=30000)
        await asyncio.sleep(2)
        
        logger.info("✅ UI driver ready")
    
    async def stop(self):
        """Stop the browser"""
        if self.browser:
            await self.browser.close()
        if self.playwright:
            await self.playwright.stop()
        logger.info("🛑 UI driver stopped")
    
    async def take_screenshot(self) -> bytes:
        """Take screenshot of current page"""
        return await self.page.screenshot(full_page=False)
    
    async def click_exam_mode(self):
        """Click the exam mode button"""
        logger.info("Clicking exam mode button...")
        await self.page.click(self.selectors["exam_mode_btn"])
        await asyncio.sleep(1)
    
    async def select_exam_domain(self, domain: str):
        """Select exam domain from dropdown"""
        logger.info(f"Selecting exam domain: {domain}")
        await self.page.select_option(self.selectors["exam_domain_select"], domain)
        await asyncio.sleep(0.5)
    
    async def start_exam(self):
        """Click start exam button"""
        logger.info("Starting exam...")
        await self.page.click(self.selectors["start_exam_btn"])
        await asyncio.sleep(2)
    
    async def wait_for_message(self, timeout: int = 30000) -> bool:
        """Wait for a new assistant message"""
        try:
            await self.page.wait_for_selector(
                self.selectors["message_assistant"],
                timeout=timeout
            )
            return True
        except Exception as e:
            logger.error(f"Timeout waiting for message: {e}")
            return False
    
    async def get_last_assistant_message(self) -> str:
        """Get the text of the last assistant message"""
        try:
            # Get all assistant messages
            messages = await self.page.query_selector_all(self.selectors["message_assistant"])
            
            if not messages:
                return ""
            
            # Get the last one
            last_message = messages[-1]
            text = await last_message.inner_text()
            return text.strip()
        
        except Exception as e:
            logger.error(f"Error reading message: {e}")
            return ""
    
    async def type_answer(self, answer: str):
        """Type an answer into the chat input"""
        logger.info(f"Typing answer ({len(answer)} chars)...")
        
        # Focus the input
        await self.page.focus(self.selectors["chat_input"])
        
        # Clear existing text
        await self.page.fill(self.selectors["chat_input"], "")
        
        # Type the answer
        await self.page.type(self.selectors["chat_input"], answer, delay=10)
        
        await asyncio.sleep(0.5)
    
    async def click_send(self):
        """Click the send button"""
        logger.info("Clicking send...")
        await self.page.click(self.selectors["send_btn"])
        await asyncio.sleep(1)
    
    async def send_message(self, message: str):
        """Type a message and send it"""
        await self.type_answer(message)
        await self.click_send()
    
    async def get_page_state(self) -> Dict[str, Any]:
        """Get current page state for debugging"""
        return {
            "url": self.page.url,
            "title": await self.page.title(),
            "viewport": self.page.viewport_size,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    
    async def run_exam_automated(
        self,
        domain: str,
        num_questions: int = 5,
        answer_callback = None
    ) -> List[Dict[str, Any]]:
        """
        Run a complete exam via UI automation
        
        Args:
            domain: Exam domain (e.g., "medical", "legal")
            num_questions: Number of questions to answer
            answer_callback: Async function to call for generating answers
                             Should accept (question_text, screenshot_bytes) and return answer string
        
        Returns:
            List of step records
        """
        logger.info(f"🎓 Running automated exam: {domain} ({num_questions} questions)")
        
        steps = []
        
        # 1. Navigate to exam mode
        await self.click_exam_mode()
        
        step = {
            "step_index": len(steps),
            "action": "click_exam_mode",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "screenshot": await self.take_screenshot()
        }
        steps.append(step)
        
        # 2. Select domain
        await self.select_exam_domain(domain)
        
        step = {
            "step_index": len(steps),
            "action": "select_domain",
            "domain": domain,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "screenshot": await self.take_screenshot()
        }
        steps.append(step)
        
        # 3. Start exam
        await self.start_exam()
        
        step = {
            "step_index": len(steps),
            "action": "start_exam",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "screenshot": await self.take_screenshot()
        }
        steps.append(step)
        
        # 4. Loop through questions
        for i in range(num_questions):
            logger.info(f"Question {i+1}/{num_questions}")
            
            # Wait for question
            if not await self.wait_for_message():
                logger.warning(f"No question received for question {i+1}")
                break
            
            # Read question
            question_text = await self.get_last_assistant_message()
            screenshot = await self.take_screenshot()
            
            logger.info(f"Question: {question_text[:100]}...")
            
            step = {
                "step_index": len(steps),
                "action": "read_question",
                "question": question_text,
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "screenshot": screenshot
            }
            steps.append(step)
            
            # Generate answer
            if answer_callback:
                answer = await answer_callback(question_text, screenshot)
            else:
                answer = "I need more information to answer this question accurately."
            
            logger.info(f"Answer: {answer[:100]}...")
            
            step = {
                "step_index": len(steps),
                "action": "generate_answer",
                "answer": answer,
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }
            steps.append(step)
            
            # Type and send answer
            await self.send_message(answer)
            
            step = {
                "step_index": len(steps),
                "action": "send_answer",
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "screenshot": await self.take_screenshot()
            }
            steps.append(step)
            
            # Wait between questions
            await asyncio.sleep(3)
        
        logger.info(f"✅ Exam complete: {len(steps)} steps recorded")
        
        return steps

