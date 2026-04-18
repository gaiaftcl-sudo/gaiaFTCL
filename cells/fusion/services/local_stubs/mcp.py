import os
from fastapi import FastAPI
import uvicorn

app = FastAPI(title="FoT-MCP Gateway")
CELL_ID = os.getenv("CELL_ID", "local")

@app.get("/health")
def health():
    return {"status": "healthy", "service": "fot-mcp-gateway", "cell_id": CELL_ID}

@app.get("/")
def root():
    return {"service": "FoT-MCP Gateway", "cell_id": CELL_ID}

@app.get("/servers")
def servers():
    return {"servers": ["quantum-substrate", "virtue-engine", "game-runner"]}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8830)
