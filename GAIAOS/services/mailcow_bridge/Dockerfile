FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY mailcow_bridge.py .
EXPOSE 8840
CMD ["uvicorn", "mailcow_bridge:app", "--host", "0.0.0.0", "--port", "8840"]
