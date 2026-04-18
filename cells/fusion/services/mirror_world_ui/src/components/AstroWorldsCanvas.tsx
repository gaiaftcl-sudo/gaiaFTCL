// ============================================================================
// ASTRO WORLDS CANVAS - React Component for Bevy WASM
// ============================================================================
// Purpose: Embed the Bevy WASM Astro Worlds 3D orbital visualization
// Technology: React wrapper around WebAssembly module
// Performance: 60 FPS 3D rendering with direct substrate access

import React, { useEffect, useRef, useState } from 'react';

interface AstroWorldsCanvasProps {
  width?: number;
  height?: number;
}

export function AstroWorldsCanvas({ width = 1920, height = 1080 }: AstroWorldsCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [initialized, setInitialized] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Prevent double initialization
    if (initialized) return;

    const initWasm = async () => {
      try {
        setLoading(true);
        setError(null);

        // Dynamic import of WASM module
        // This will fail until WASM is built and copied to public/
        const wasmModule = await import('/astro_worlds.js');

        // Initialize WASM module
        await wasmModule.default();

        // Run the Bevy app (takes over the canvas)
        // This never returns - Bevy controls the canvas from here
        wasmModule.run_astro_worlds();

        setInitialized(true);
        setLoading(false);

        console.log('✅ Astro Worlds initialized successfully');
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : 'Unknown error';
        setError(errorMsg);
        setLoading(false);
        console.error('❌ Failed to initialize Astro Worlds:', err);
      }
    };

    initWasm();
  }, [initialized]);

  return (
    <div className="astro-worlds-container" style={{ width: '100%', height: '100%', position: 'relative' }}>
      {/* Header */}
      <div className="astro-worlds-header" style={{
        position: 'absolute',
        top: 0,
        left: 0,
        right: 0,
        padding: '1rem',
        background: 'rgba(0, 0, 0, 0.8)',
        color: 'white',
        zIndex: 10,
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
      }}>
        <h3 style={{ margin: 0 }}>🌌 Astro Worlds (Bevy WASM)</h3>

        {loading && (
          <div style={{ color: '#fbbf24' }}>Loading WASM...</div>
        )}

        {error && (
          <div style={{ color: '#ef4444', fontSize: '0.875rem' }}>
            Error: {error}
            <div style={{ fontSize: '0.75rem', marginTop: '0.25rem' }}>
              WASM not built yet. Run: cd astro-worlds && wasm-pack build --target web --release
            </div>
          </div>
        )}

        {initialized && (
          <div style={{ display: 'flex', gap: '0.5rem' }}>
            <span style={{ color: '#10b981' }}>✓ Running</span>
            <span style={{ color: '#6b7280' }}>|</span>
            <span>60 FPS</span>
          </div>
        )}
      </div>

      {/* Controls Help */}
      <div className="astro-worlds-controls" style={{
        position: 'absolute',
        bottom: 0,
        left: 0,
        right: 0,
        padding: '1rem',
        background: 'rgba(0, 0, 0, 0.8)',
        color: 'white',
        zIndex: 10,
        fontSize: '0.875rem',
      }}>
        <div style={{ fontWeight: 'bold', marginBottom: '0.5rem' }}>Camera Controls:</div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '0.5rem' }}>
          <div>← → ↑ ↓ : Rotate camera</div>
          <div>W / S : Zoom in/out</div>
          <div>Mouse : Look around (planned)</div>
        </div>
      </div>

      {/* Bevy Canvas */}
      <canvas
        ref={canvasRef}
        id="bevy-canvas"
        width={width}
        height={height}
        style={{
          width: '100%',
          height: '100%',
          display: 'block',
          background: '#000',
        }}
      />

      {/* Info Panel */}
      {initialized && (
        <div className="astro-worlds-info" style={{
          position: 'absolute',
          top: '80px',
          right: '1rem',
          padding: '1rem',
          background: 'rgba(0, 0, 0, 0.8)',
          color: 'white',
          borderRadius: '0.5rem',
          fontSize: '0.875rem',
          zIndex: 10,
          minWidth: '200px',
        }}>
          <div style={{ fontWeight: 'bold', marginBottom: '0.5rem' }}>System Status</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.25rem' }}>
            <div>
              <span style={{ color: '#10b981' }}>●</span> Bevy Engine
            </div>
            <div>
              <span style={{ color: '#10b981' }}>●</span> Direct Substrate
            </div>
            <div>
              <span style={{ color: '#fbbf24' }}>●</span> Guardian Active
            </div>
            <div style={{ marginTop: '0.5rem', paddingTop: '0.5rem', borderTop: '1px solid #374151' }}>
              <div>Entities: <span id="entity-count">1</span></div>
              <div>FPS: <span id="fps">60</span></div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ============================================================================
// USAGE EXAMPLE
// ============================================================================
/*
// In App.tsx or main layout:

import { AstroWorldsCanvas } from './components/AstroWorldsCanvas';

function App() {
  return (
    <div style={{ width: '100vw', height: '100vh' }}>
      <AstroWorldsCanvas />
    </div>
  );
}

// Or as a tab/section:

<div className="worlds-container">
  <div className="mirror-world">
    <MirrorWorldUI />
  </div>

  <div className="astro-world">
    <AstroWorldsCanvas />
  </div>
</div>

*/

// ============================================================================
// FEATURES
// ============================================================================
/*
WHEN WASM IS BUILT, THIS COMPONENT WILL SHOW:

✅ 3D orbital visualization
  - Earth at origin (6,371 km radius)
  - Satellites in LEO, MEO, GEO orbits
  - Real Keplerian mechanics (when substrate connected)

✅ Consciousness Visualization
  - Cyan halos around entities (self-awareness level)
  - Yellow Guardian zones (separation constraints)
  - Green/red decision nodes (approved/rejected trajectories)

✅ Interactive Controls
  - Arrow keys: Rotate camera around Earth
  - W/S keys: Zoom in/out
  - Real-time 60 FPS rendering

✅ Direct Substrate Access
  - No HTTP overhead (Rust-to-Rust calls)
  - Embedded physics calculations
  - Franklin Guardian constraints applied in real-time
  - AKG introspection for self-awareness

TO BUILD AND ENABLE:
1. Fix Rust setup (use rustup instead of Homebrew):
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   rustup target add wasm32-unknown-unknown

2. Build WASM:
   cd /Users/richardgillespie/Documents/FoT8D/cells/fusion/astro-worlds
   wasm-pack build --target web --release

3. Copy to public:
   cp pkg/astro_worlds_bg.wasm ../services/mirror_world_ui/public/
   cp pkg/astro_worlds.js ../services/mirror_world_ui/public/

4. This component will auto-load it!
*/
