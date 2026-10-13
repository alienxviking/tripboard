"""Generates grafana-dashboard.yaml (ConfigMap picked up by the Grafana sidecar)."""
import json

DS = {"type": "prometheus", "uid": "prometheus"}
NS = 'namespace="tripboard"'


def panel(pid, kind, title, expr, legend, x, y, w, h, unit="short"):
    return {
        "id": pid, "type": kind, "title": title, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "fieldConfig": {"defaults": {"unit": unit}, "overrides": []},
        "targets": [{"expr": expr, "legendFormat": legend, "refId": "A"}],
    }


panels = [
    panel(1, "stat", "Backend up", f'sum(up{{{NS}, service="tripboard-backend"}})', "", 0, 0, 4, 4),
    panel(2, "stat", "Requests / s", f"sum(rate(http_requests_total{{{NS}}}[2m]))", "", 4, 0, 5, 4, "reqps"),
    panel(3, "stat", "5xx error rate",
          f'(sum(rate(http_requests_total{{{NS}, status="5xx"}}[5m])) or vector(0)) / sum(rate(http_requests_total{{{NS}}}[5m]))',
          "", 9, 0, 5, 4, "percentunit"),
    panel(4, "stat", "p95 latency",
          f"histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{{{NS}}}[5m])))",
          "", 14, 0, 5, 4, "s"),
    panel(5, "stat", "Trips stored", "sum(max by (status) (tripboard_trips))", "", 19, 0, 5, 4),
    panel(6, "timeseries", "Requests / s by endpoint and status",
          f"sum by (handler, status) (rate(http_requests_total{{{NS}}}[2m]))", "{{handler}} {{status}}", 0, 4, 12, 8, "reqps"),
    panel(7, "timeseries", "Latency p50 / p95",
          f"histogram_quantile(0.5, sum by (le) (rate(http_request_duration_seconds_bucket{{{NS}}}[2m])))",
          "p50", 12, 4, 12, 8, "s"),
    panel(8, "timeseries", "CPU by pod",
          f'sum by (pod) (rate(container_cpu_usage_seconds_total{{{NS}, container!=""}}[2m]))', "{{pod}}", 0, 12, 12, 8, "cores"),
    panel(9, "timeseries", "Memory by pod",
          f'sum by (pod) (container_memory_working_set_bytes{{{NS}, container!=""}})', "{{pod}}", 12, 12, 12, 8, "bytes"),
    panel(10, "bargauge", "Trips by status", "max by (status) (tripboard_trips)", "{{status}}", 0, 20, 12, 6),
    panel(11, "timeseries", "Pod restarts", f"sum by (pod) (kube_pod_container_status_restarts_total{{{NS}}})",
          "{{pod}}", 12, 20, 12, 6),
]
panels[6]["targets"].append({
    "expr": f"histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{{{NS}}}[2m])))",
    "legendFormat": "p95", "refId": "B"})

dashboard = {
    "title": "TripBoard - Application", "uid": "tripboard-app", "schemaVersion": 39, "tags": ["tripboard"],
    "time": {"from": "now-30m", "to": "now"}, "refresh": "10s", "panels": panels,
}

lines = [
    "apiVersion: v1",
    "kind: ConfigMap",
    "metadata:",
    "  name: tripboard-dashboard",
    "  namespace: monitoring",
    "  labels:",
    '    grafana_dashboard: "1"',
    "data:",
    "  tripboard.json: |",
]
lines += ["    " + line for line in json.dumps(dashboard, indent=2).splitlines()]
with open("grafana-dashboard.yaml", "w", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
print("wrote grafana-dashboard.yaml")
