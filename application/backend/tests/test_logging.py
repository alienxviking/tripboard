import json
import logging

from app.logging_config import JsonFormatter, configure_logging


def _access_records(caplog):
    return [r for r in caplog.records if r.name == "tripboard.access"]


def test_formatter_writes_one_json_object_with_extra_fields():
    record = logging.LogRecord("tripboard.access", logging.INFO, __file__, 1, "request", None, None)
    record.status = 201
    record.path = "/api/trips"
    line = JsonFormatter().format(record)
    entry = json.loads(line)
    assert entry["level"] == "info"
    assert entry["logger"] == "tripboard.access"
    assert entry["msg"] == "request"
    assert entry["status"] == 201 and entry["path"] == "/api/trips"
    assert entry["ts"].endswith("+00:00")
    assert "\n" not in line


def test_formatter_includes_the_traceback():
    try:
        raise ValueError("boom")
    except ValueError:
        import sys
        record = logging.LogRecord("x", logging.ERROR, __file__, 1, "failed", None, sys.exc_info())
    entry = json.loads(JsonFormatter().format(record))
    assert "ValueError: boom" in entry["exc"]


def test_each_request_is_logged_with_method_path_status_and_duration(client, caplog):
    caplog.set_level(logging.INFO, logger="tripboard.access")
    trip = {"destination": "Goa", "start_date": "2026-12-01", "end_date": "2026-12-05", "budget": 500}
    r = client.post("/api/trips", json=trip)
    assert r.status_code == 201
    [rec] = _access_records(caplog)
    assert (rec.method, rec.path, rec.status) == ("POST", "/api/trips", 201)
    assert rec.duration_ms >= 0
    assert rec.request_id == r.headers["X-Request-ID"]


def test_an_incoming_request_id_is_kept(client, caplog):
    caplog.set_level(logging.INFO, logger="tripboard.access")
    r = client.get("/api/trips", headers={"X-Request-ID": "abc123"})
    assert r.headers["X-Request-ID"] == "abc123"
    assert _access_records(caplog)[0].request_id == "abc123"


def test_errors_are_logged_with_their_status(client, caplog):
    caplog.set_level(logging.INFO, logger="tripboard.access")
    client.get("/api/trips/999")
    [rec] = _access_records(caplog)
    assert rec.status == 404 and rec.levelno == logging.INFO


def test_probes_are_only_logged_at_debug(client, caplog):
    caplog.set_level(logging.INFO, logger="tripboard.access")
    client.get("/health")
    assert _access_records(caplog) == []
    caplog.set_level(logging.DEBUG, logger="tripboard.access")
    client.get("/health")
    assert [r.levelno for r in _access_records(caplog)] == [logging.DEBUG]


def test_uvicorn_extras_and_access_log_are_dropped():
    record = logging.LogRecord("uvicorn.error", logging.INFO, __file__, 1, "Uvicorn running", None, None)
    record.color_message = "[1mUvicorn running[0m"
    assert "color_message" not in json.loads(JsonFormatter().format(record))

    access = logging.getLogger("uvicorn.access")
    access.propagate = True  # what uvicorn leaves it as without --no-access-log
    configure_logging()
    assert access.propagate is False and access.handlers == []
    assert logging.getLogger("uvicorn.error").propagate is True
