#!/bin/sh
set -e

# wait for the database (on first deploy postgres starts at the same time as the backend)
python - <<'PY'
import sys, time
from sqlalchemy import create_engine, text
from app.config import settings

engine = create_engine(settings.database_url)
for attempt in range(1, 61):
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print(f"database ready (attempt {attempt})", flush=True)
        break
    except Exception as exc:
        print(f"waiting for database ({attempt}/60): {exc.__class__.__name__}", flush=True)
        time.sleep(2)
else:
    sys.exit("database not reachable after 120s")
PY

# run DB migrations (alembic env.py takes a postgres advisory lock, so parallel pods are safe)
alembic upgrade head
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*' --no-access-log
