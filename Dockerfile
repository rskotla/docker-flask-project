
FROM python:3.12-slim

# Python runtime settings
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Create the application directory
WORKDIR /app

# Install dependencies separately for better build caching
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt \
    && groupadd --system app \
    && useradd --system --gid app --home-dir /app app

# Copy application files and assign ownership
COPY --chown=app:app app.py .
COPY --chown=app:app templates ./templates

# Run as a non-root user
USER app

# Document the application's listening port
EXPOSE 5000

# Start the application using Gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:5000", \
     "--workers", "2", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "app:app"]
