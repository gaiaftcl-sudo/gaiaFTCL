# GaiaFTCL Console — dependency lock

**GaiaFTCL Console** is intentionally **isolated** from GaiaFusion and MacHealth Swift packages:

- Launches peer cell apps via `Process` and observes NATS **read-only**.
- **No** GaiaFusion / MacHealth SPM product dependencies (keeps the operator shell buildable when cell apps churn).

If you need shared UI or Metal types, add them to a **neutral** module — do not link GaiaFusion/MacHealth targets into this app.
