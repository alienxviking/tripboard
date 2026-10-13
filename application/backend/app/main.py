from fastapi import Depends, FastAPI, HTTPException
from prometheus_client import Gauge
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.models import Trip
from app.schemas import TripIn, TripOut

app = FastAPI(title=settings.app_name, version=settings.app_version)

# http_requests_total, http_request_duration_seconds, ... on /metrics
Instrumentator(excluded_handlers=["/metrics", "/health", "/ready"]).instrument(app).expose(app, include_in_schema=False)
TRIPS_TOTAL = Gauge("tripboard_trips", "Number of trips stored, by status", ["status"])


@app.get("/health")
def health():
    """Liveness: the process is up."""
    return {"status": "ok", "version": settings.app_version}


@app.get("/ready")
def ready(db: Session = Depends(get_db)):
    """Readiness: the database answers."""
    try:
        db.execute(text("SELECT 1"))
    except Exception as exc:  # noqa: BLE001 - report any DB error as not ready
        raise HTTPException(status_code=503, detail=f"database not reachable: {exc.__class__.__name__}")
    return {"status": "ready"}


@app.get("/api/info")
def info():
    return {"app": settings.app_name, "version": settings.app_version, "environment": settings.environment}


@app.get("/api/trips", response_model=list[TripOut])
def list_trips(db: Session = Depends(get_db)):
    trips = db.scalars(select(Trip).order_by(Trip.start_date)).all()
    _update_gauge(db)
    return trips


@app.post("/api/trips", response_model=TripOut, status_code=201)
def create_trip(trip: TripIn, db: Session = Depends(get_db)):
    obj = Trip(**trip.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    _update_gauge(db)
    return obj


@app.get("/api/trips/{trip_id}", response_model=TripOut)
def get_trip(trip_id: int, db: Session = Depends(get_db)):
    return _get_or_404(db, trip_id)


@app.put("/api/trips/{trip_id}", response_model=TripOut)
def update_trip(trip_id: int, trip: TripIn, db: Session = Depends(get_db)):
    obj = _get_or_404(db, trip_id)
    for key, value in trip.model_dump().items():
        setattr(obj, key, value)
    db.commit()
    db.refresh(obj)
    _update_gauge(db)
    return obj


@app.delete("/api/trips/{trip_id}")
def delete_trip(trip_id: int, db: Session = Depends(get_db)):
    obj = _get_or_404(db, trip_id)
    db.delete(obj)
    db.commit()
    _update_gauge(db)
    return {"deleted": trip_id}


def _get_or_404(db: Session, trip_id: int) -> Trip:
    obj = db.get(Trip, trip_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="trip not found")
    return obj


def _update_gauge(db: Session):
    for status in ("planned", "booked", "done"):
        TRIPS_TOTAL.labels(status=status).set(0)
    for status, count in db.execute(select(Trip.status, func.count()).group_by(Trip.status)):
        TRIPS_TOTAL.labels(status=status).set(count)
