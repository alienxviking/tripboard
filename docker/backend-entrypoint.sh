#!/bin/sh
set -e
# run DB migrations (alembic env.py takes a postgres advisory lock, so parallel pods are safe)
alembic upgrade head
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*'
