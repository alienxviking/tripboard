TRIP = {"destination": "Goa", "start_date": "2026-12-20", "end_date": "2026-12-27", "budget": 25000, "status": "planned"}


def test_health(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json()["status"] == "ok"


def test_ready(client):
    assert client.get("/ready").json() == {"status": "ready"}


def test_create_and_list(client):
    res = client.post("/api/trips", json=TRIP)
    assert res.status_code == 201
    assert res.json()["id"] == 1
    trips = client.get("/api/trips").json()
    assert len(trips) == 1 and trips[0]["destination"] == "Goa"


def test_get_one_and_404(client):
    client.post("/api/trips", json=TRIP)
    assert client.get("/api/trips/1").json()["budget"] == 25000
    assert client.get("/api/trips/99").status_code == 404


def test_update(client):
    client.post("/api/trips", json=TRIP)
    res = client.put("/api/trips/1", json={**TRIP, "status": "booked"})
    assert res.status_code == 200
    assert res.json()["status"] == "booked"


def test_delete(client):
    client.post("/api/trips", json=TRIP)
    assert client.delete("/api/trips/1").status_code == 200
    assert client.delete("/api/trips/1").status_code == 404


def test_validation_end_before_start(client):
    bad = {**TRIP, "end_date": "2026-12-01"}
    assert client.post("/api/trips", json=bad).status_code == 422


def test_validation_bad_status(client):
    assert client.post("/api/trips", json={**TRIP, "status": "flying"}).status_code == 422


def test_metrics_endpoint(client):
    client.get("/api/trips")
    body = client.get("/metrics").text
    assert "http_requests_total" in body
    assert "tripboard_trips" in body
