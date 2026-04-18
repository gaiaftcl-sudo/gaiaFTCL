FROM python:3.11-slim

WORKDIR /app

RUN pip install fastapi uvicorn httpx pydantic pyyaml

COPY main.py .

EXPOSE 8831

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8831"]
