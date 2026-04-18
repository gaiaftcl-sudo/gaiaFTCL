import os
import sys
from src.db import FounderDB

# Add current dir to sys.path
sys.path.append(os.getcwd())

db = FounderDB()
try:
    db.connect()
    print("✅ Successfully connected to ArangoDB and ensured collections.")
except Exception as e:
    print(f"❌ Failed to connect: {e}")
