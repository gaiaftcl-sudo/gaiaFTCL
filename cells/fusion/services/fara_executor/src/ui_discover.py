#!/usr/bin/env python3
"""
UI Element Discovery for Fara Automation
Discovers all interactive elements in the GaiaOS exam UI
"""
import asyncio
import json
import logging
from pathlib import Path
from playwright.async_api import async_playwright

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def discover_ui_elements(ui_url: str = "http://localhost:3000"):
    """Discover all UI elements for automation"""
    
    logger.info(f"🔍 Discovering UI elements at {ui_url}...")
    
    playwright = await async_playwright().start()
    browser = await playwright.chromium.launch(headless=False)
    page = await browser.new_page()
    
    try:
        # Navigate to UI
        await page.goto(ui_url, wait_until="networkidle")
        await asyncio.sleep(2)
        
        elements = {
            "url": ui_url,
            "buttons": [],
            "inputs": [],
            "selects": [],
            "textareas": [],
            "links": []
        }
        
        # Find all buttons
        buttons = await page.query_selector_all("button")
        for btn in buttons:
            try:
                id_attr = await btn.get_attribute("id")
                class_attr = await btn.get_attribute("class")
                text = await btn.inner_text()
                visible = await btn.is_visible()
                
                elements["buttons"].append({
                    "id": id_attr,
                    "class": class_attr,
                    "text": text.strip() if text else "",
                    "visible": visible,
                    "selector": f"#{id_attr}" if id_attr else f"button:has-text('{text[:20]}')"
                })
            except Exception as e:
                logger.debug(f"Error reading button: {e}")
        
        # Find all inputs
        inputs = await page.query_selector_all("input")
        for inp in inputs:
            try:
                id_attr = await inp.get_attribute("id")
                type_attr = await inp.get_attribute("type")
                placeholder = await inp.get_attribute("placeholder")
                name_attr = await inp.get_attribute("name")
                
                elements["inputs"].append({
                    "id": id_attr,
                    "type": type_attr,
                    "placeholder": placeholder,
                    "name": name_attr,
                    "selector": f"#{id_attr}" if id_attr else f"input[type='{type_attr}']"
                })
            except Exception as e:
                logger.debug(f"Error reading input: {e}")
        
        # Find all selects
        selects = await page.query_selector_all("select")
        for sel in selects:
            try:
                id_attr = await sel.get_attribute("id")
                options = await sel.query_selector_all("option")
                option_data = []
                
                for opt in options:
                    value = await opt.get_attribute("value")
                    text = await opt.inner_text()
                    option_data.append({"value": value, "text": text})
                
                elements["selects"].append({
                    "id": id_attr,
                    "options": option_data,
                    "selector": f"#{id_attr}" if id_attr else "select"
                })
            except Exception as e:
                logger.debug(f"Error reading select: {e}")
        
        # Find all textareas
        textareas = await page.query_selector_all("textarea")
        for ta in textareas:
            try:
                id_attr = await ta.get_attribute("id")
                placeholder = await ta.get_attribute("placeholder")
                
                elements["textareas"].append({
                    "id": id_attr,
                    "placeholder": placeholder,
                    "selector": f"#{id_attr}" if id_attr else "textarea"
                })
            except Exception as e:
                logger.debug(f"Error reading textarea: {e}")
        
        # Take screenshot
        screenshot_path = "/tmp/ui_discovery.png"
        await page.screenshot(path=screenshot_path, full_page=True)
        logger.info(f"📸 Screenshot saved: {screenshot_path}")
        
        # Print results
        print("\n" + "=" * 80)
        print("UI ELEMENT DISCOVERY RESULTS")
        print("=" * 80)
        
        print(f"\n📍 URL: {ui_url}\n")
        
        print(f"🔘 BUTTONS ({len(elements['buttons'])}):")
        for btn in elements["buttons"][:20]:  # Show first 20
            if btn["visible"]:
                print(f"  ✓ {btn['selector']:<40} | {btn['text'][:40]}")
        
        print(f"\n📝 INPUTS ({len(elements['inputs'])}):")
        for inp in elements["inputs"][:10]:
            print(f"  • {inp['selector']:<40} | type={inp['type']}, placeholder={inp['placeholder']}")
        
        print(f"\n🎛️  SELECTS ({len(elements['selects'])}):")
        for sel in elements["selects"]:
            print(f"  • {sel['selector']:<40} | {len(sel['options'])} options")
            for opt in sel["options"][:5]:
                print(f"      - {opt['value']}: {opt['text']}")
        
        print(f"\n📄 TEXTAREAS ({len(elements['textareas'])}):")
        for ta in elements["textareas"]:
            print(f"  • {ta['selector']:<40} | {ta['placeholder']}")
        
        # Save to JSON
        output_path = Path("/tmp/ui_elements.json")
        with open(output_path, "w") as f:
            json.dump(elements, f, indent=2)
        
        print(f"\n✅ Saved to {output_path}")
        print("=" * 80 + "\n")
        
        return elements
    
    finally:
        await browser.close()
        await playwright.stop()


async def main():
    """Main entry point"""
    import sys
    
    ui_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:3000"
    
    try:
        elements = await discover_ui_elements(ui_url)
        
        # Return exam-specific elements
        exam_elements = {
            "exam_mode_button": None,
            "exam_domain_select": None,
            "start_exam_button": None,
            "chat_input": None,
            "send_button": None
        }
        
        # Find exam mode button
        for btn in elements["buttons"]:
            if "exam" in btn["text"].lower() or "exam" in btn["id"].lower():
                exam_elements["exam_mode_button"] = btn["selector"]
                logger.info(f"✓ Found exam mode button: {btn['selector']}")
        
        # Find exam domain select
        for sel in elements["selects"]:
            if "domain" in sel["id"].lower() or "exam" in sel["id"].lower():
                exam_elements["exam_domain_select"] = sel["selector"]
                logger.info(f"✓ Found exam domain select: {sel['selector']}")
        
        # Find start exam button
        for btn in elements["buttons"]:
            if "start" in btn["text"].lower() and "exam" in btn["text"].lower():
                exam_elements["start_exam_button"] = btn["selector"]
                logger.info(f"✓ Found start exam button: {btn['selector']}")
        
        # Find chat input
        for ta in elements["textareas"]:
            if "input" in ta["id"].lower() or "message" in ta["placeholder"].lower():
                exam_elements["chat_input"] = ta["selector"]
                logger.info(f"✓ Found chat input: {ta['selector']}")
        
        # Find send button
        for btn in elements["buttons"]:
            if "send" in btn["id"].lower() or "send" in btn["text"].lower():
                exam_elements["send_button"] = btn["selector"]
                logger.info(f"✓ Found send button: {btn['selector']}")
        
        # Save exam elements
        exam_output = Path("/tmp/exam_ui_elements.json")
        with open(exam_output, "w") as f:
            json.dump(exam_elements, f, indent=2)
        
        logger.info(f"✅ Exam elements saved to {exam_output}")
        
    except Exception as e:
        logger.error(f"Discovery failed: {e}", exc_info=True)
        return 1
    
    return 0


if __name__ == "__main__":
    exit(asyncio.run(main()))

