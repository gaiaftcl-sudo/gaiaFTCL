# Fara-7B Computer Use Executor
# Playwright + Python + UUM-8D substrate integration

FROM mcr.microsoft.com/playwright/python:v1.40.0-jammy

WORKDIR /app

# Install Python dependencies
RUN pip install --no-cache-dir \
    requests \
    aiohttp \
    playwright \
    opencv-python-headless \
    pillow \
    numpy \
    arango-orm \
    pydantic \
    asyncio

# Install Playwright browsers
RUN playwright install chromium firefox webkit
RUN playwright install-deps

# Copy executor code
COPY services/fara_executor/src /app/src
COPY services/fara_executor/requirements.txt /app/

# Install any additional requirements
RUN pip install --no-cache-dir -r requirements.txt || true

# Create user
RUN useradd -m -u 1000 fara && chown -R fara:fara /app
USER fara

# Expose API port for executor control
EXPOSE 8200

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8200/health || exit 1

# Start executor service
CMD ["python", "-m", "src.main"]

