
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Apply available OS security updates
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

# Install Python application dependencies
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt \
    && groupadd --system app \
    && useradd --system --gid app --home-dir /app app

# Copy application files
COPY --chown=app:app app.py .
COPY --chown=app:app templates ./templates

# Run as non-root user
USER app

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", \
     "--workers", "2", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "app:app"]
