FROM python:3.11-slim
WORKDIR /app
COPY adapter.py queue.py drain_loop.py ./
ENV GAIAFTCL_GATEWAY=http://gaiaftcl-wallet-gate:8803
ENV MAIL_ADAPTER_QUEUE_DIR=/data/mail_adapter_queue
CMD ["python", "-u", "drain_loop.py"]
