import os
from fastapi import FastAPI
import uvicorn

app = FastAPI(title="Quantum Substrate")
CELL_ID = os.getenv("CELL_ID", "local")

@app.get("/health")
def health():
    return {"status": "healthy", "service": "quantum-substrate", "cell_id": CELL_ID}

@app.get("/")
def root():
    return {"service": "Quantum Substrate", "cell_id": CELL_ID}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
