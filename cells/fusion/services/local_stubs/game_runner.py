import os
from fastapi import FastAPI
import uvicorn

app = FastAPI(title="Game Runner")
CELL_ID = os.getenv("CELL_ID", "local")

@app.get("/health")
def health():
    return {"status": "healthy", "service": "game-runner", "cell_id": CELL_ID}

@app.get("/games")
def games():
    return {"games": ["G_FTCL_UPDATE_FLEET_V1", "G_FTCL_ROLLBACK_V1", "G_EMAIL_INTERACTION_V1"]}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8801)
