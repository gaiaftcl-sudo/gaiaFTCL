#!/bin/bash
# visual_test_helpers.sh
# Shared visual confirmation functions for GAMP 5 TestRobot
# FortressAI Research Institute | USPTO 19/460,960

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -f "$PROJECT_ROOT/config/testrobot.toml" ]]; then
    eval "$("$PROJECT_ROOT/tools/gaiafusion-config-cli/target/release/gaiafusion-config-cli" "$PROJECT_ROOT/config/testrobot.toml")"
fi

EVIDENCE_ROOT="${EVIDENCE_ROOT:-evidence}"
SCREENSHOTS_DIR="${EXECUTION__SCREENSHOTS_DIR:-evidence/screenshots}"
VISUAL_TIMEOUT="${TIMEOUTS__VISUAL_CONFIRMATION_SECONDS:-30}"
SCREENSHOT_DELAY="${TIMEOUTS__SCREENSHOT_DELAY_SECONDS:-2}"

mkdir -p "$PROJECT_ROOT/$SCREENSHOTS_DIR"

# visual_checkpoint <test_id> <description> <pass_criteria>
# Captures screenshot, opens it in Quick Look, presents dialog for pass/fail
visual_checkpoint() {
    local test_id="$1"
    local description="$2"
    local pass_criteria="$3"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local screenshot_path="$PROJECT_ROOT/$SCREENSHOTS_DIR/${test_id}_${timestamp}.png"
    
    echo "📸 Visual Checkpoint: $test_id"
    echo "   $description"
    echo "   Pass criteria: $pass_criteria"
    
    # Wait for UI to stabilize
    sleep "$SCREENSHOT_DELAY"
    
    # Capture screenshot (full screen)
    screencapture -x "$screenshot_path"
    
    if [[ ! -f "$screenshot_path" ]]; then
        echo "❌ Screenshot capture failed for $test_id"
        return 1
    fi
    
    # Open screenshot in separate Quick Look window
    qlmanage -p "$screenshot_path" > /dev/null 2>&1 &
    local ql_pid=$!
    
    # Present confirmation dialog
    local result=$(osascript -e "
        display dialog \"Visual Checkpoint: $test_id\n\n$description\n\nPass criteria:\n$pass_criteria\n\nScreenshot saved to:\n$screenshot_path\n\nDoes the visual state match the pass criteria?\" buttons {\"FAIL\", \"PASS\"} default button \"PASS\" with title \"GaiaFusion GAMP 5 Validation\" giving up after $VISUAL_TIMEOUT
    " 2>&1)
    
    # Kill Quick Look process
    kill $ql_pid 2>/dev/null || true
    
    if echo "$result" | grep -q "PASS"; then
        echo "✅ $test_id PASS"
        return 0
    elif echo "$result" | grep -q "FAIL"; then
        echo "❌ $test_id FAIL (operator rejected)"
        return 1
    else
        echo "⏱️  $test_id TIMEOUT (no response after ${VISUAL_TIMEOUT}s)"
        return 2
    fi
}

# visual_baseline_compare <test_id> <current_screenshot> <baseline_screenshot>
# Compares current screenshot against baseline using ImageMagick
visual_baseline_compare() {
    local test_id="$1"
    local current="$2"
    local baseline="$3"
    local tolerance="${VISUAL_REGRESSION_TOLERANCE:-0.05}"
    
    if [[ ! -f "$baseline" ]]; then
        echo "⚠️  No baseline for $test_id — current becomes baseline"
        cp "$current" "$baseline"
        return 0
    fi
    
    # Use ImageMagick compare (if available)
    if command -v compare > /dev/null 2>&1; then
        local diff_img="$PROJECT_ROOT/$SCREENSHOTS_DIR/${test_id}_diff.png"
        local metric=$(compare -metric RMSE "$current" "$baseline" "$diff_img" 2>&1 | awk '{print $1}' || echo "1.0")
        
        # Convert metric to percentage
        local diff_pct=$(echo "scale=4; $metric * 100" | bc)
        local threshold_pct=$(echo "scale=4; $tolerance * 100" | bc)
        
        echo "   Visual diff: ${diff_pct}% (threshold: ${threshold_pct}%)"
        
        if (( $(echo "$diff_pct < $threshold_pct" | bc -l) )); then
            echo "✅ $test_id: Visual regression PASS"
            rm -f "$diff_img"
            return 0
        else
            echo "❌ $test_id: Visual regression FAIL"
            echo "   Diff image: $diff_img"
            return 1
        fi
    else
        echo "⚠️  ImageMagick 'compare' not found — skipping regression check"
        return 0
    fi
}

# update_baseline <test_id> <current_screenshot>
# Updates the baseline image for a test
update_baseline() {
    local test_id="$1"
    local current="$2"
    local baselines_dir="${EXECUTION__BASELINES_DIR:-evidence/baselines}"
    local baseline="$PROJECT_ROOT/$baselines_dir/${test_id}_baseline.png"
    
    mkdir -p "$PROJECT_ROOT/$baselines_dir"
    
    if [[ -f "$current" ]]; then
        cp "$current" "$baseline"
        echo "✅ Baseline updated for $test_id"
        echo "   $baseline"
        return 0
    else
        echo "❌ Current screenshot not found: $current"
        return 1
    fi
}

# visual_confirmation_banner <phase> <test_count>
# Shows a banner dialog for starting a visual confirmation phase
visual_confirmation_banner() {
    local phase="$1"
    local test_count="$2"
    
    osascript -e "
        display dialog \"Starting $phase\n\n$test_count visual confirmations required.\n\nEach checkpoint will:\n• Capture a screenshot\n• Display it in Quick Look\n• Ask you to verify pass criteria\n\nReady to begin?\" buttons {\"Cancel\", \"Begin\"} default button \"Begin\" with title \"GaiaFusion GAMP 5 Validation\"
    " > /dev/null 2>&1
    
    return $?
}

# notify_test_result <test_id> <result>
# Logs test result (no macOS notification banners to avoid STATUS on/off issue)
notify_test_result() {
    local test_id="$1"
    local result="$2"
    
    case "$result" in
        PASS)
            echo "✅ $test_id: PASS"
            ;;
        FAIL)
            echo "❌ $test_id: FAIL"
            ;;
        SKIP)
            echo "⏭️  $test_id: SKIP"
            ;;
        *)
            echo "❓ $test_id: $result"
            ;;
    esac
}

# Export functions for use in other scripts
export -f visual_checkpoint
export -f visual_baseline_compare
export -f update_baseline
export -f visual_confirmation_banner
export -f notify_test_result
