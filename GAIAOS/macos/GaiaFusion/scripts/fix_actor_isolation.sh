#!/usr/bin/env zsh
# Fix all actor isolation issues in test protocols

set -e

cd "$(dirname "$0")/.."

echo "Fixing actor isolation in test protocols..."

# Fix all gameState = OpenUSDLanguageGameState() -> await MainActor.run { ... }
# Fix all playbackController = MetalPlaybackController() -> await MainActor.run { ... }

for file in Tests/Protocols/*.swift; do
    # Fix init calls - need to wrap in MainActor.run
    perl -i -p0e 's/gameState = OpenUSDLanguageGameState\(\)/gameState = await MainActor.run { OpenUSDLanguageGameState() }/gs' "$file"
    perl -i -p0e 's/playbackController = MetalPlaybackController\(\)/playbackController = await MainActor.run { MetalPlaybackController() }/gs' "$file"
    
    # Fix property access in XCTAssert - need await
    sed -i '' 's/XCTAssertEqual(gameState\.terminalState/let state = await gameState.terminalState; XCTAssertEqual(state/g' "$file"
    sed -i '' 's/XCTAssertTrue(gameState\.errorBoundaryActive/let active = await gameState.errorBoundaryActive; XCTAssertTrue(active/g' "$file"
    sed -i '' 's/XCTAssertFalse(gameState\.appCrashed/let crashed = await gameState.appCrashed; XCTAssertFalse(crashed/g' "$file"
    sed -i '' 's/XCTAssertTrue(gameState\.ncrLogged/let logged = await gameState.ncrLogged; XCTAssertTrue(logged/g' "$file"
    
    # Fix injectFaultTelemetry calls
    sed -i '' 's/gameState\.injectFaultTelemetry(/await gameState.injectFaultTelemetry(/g' "$file"
    sed -i '' 's/gameState\.injectMalformedTelemetry(/await gameState.injectMalformedTelemetry(/g' "$file"
done

echo "✅ Actor isolation fixed"
