FROM python:3.10-slim

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl \
  && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy implementation modules (avoid missing imports at runtime).
# NOTE: we intentionally include only python sources; no synthetic data.
COPY *.py /app/

ENV PYTHONUNBUFFERED=1

CMD ["python", "/app/main.py"]


