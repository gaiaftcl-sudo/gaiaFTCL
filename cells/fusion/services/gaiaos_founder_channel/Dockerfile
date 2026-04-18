FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Make sure start.sh is executable
RUN chmod +x start.sh

# Expose ports
EXPOSE 8005 8006

CMD ["./start.sh"]
