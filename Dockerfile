FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    POETRY_VIRTUALENVS_CREATE=false

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl netcat-openbsd && rm -rf /var/lib/apt/lists/*

# App dir
WORKDIR /app

# Install deps
COPY requirements.txt .
RUN pip install -r requirements.txt

# Create project
COPY src ./src

# Collect static is not needed for API-only. Create non-root user.
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

ENV DJANGO_SETTINGS_MODULE=config.settings \
    PYTHONPATH=/app/src \
    PORT=8000 \
    DJANGO_SECRET_KEY=changeme-in-prod

EXPOSE 8000
CMD gunicorn config.wsgi:application --bind 0.0.0.0:${PORT} --workers 2 --timeout 60
