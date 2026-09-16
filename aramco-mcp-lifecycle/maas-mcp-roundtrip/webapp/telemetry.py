"""Small MLflow REST client for the hosted and CLI round-trip demos.

The demo should remain useful when tracking is unavailable, so telemetry errors
are recorded locally and never interrupt the MCP or MaaS path.
"""
import json
import os
import re
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request


DEFAULT_TRACKING_URI = "https://mlflow-praxis-verified.apps.ocp-gb.ibm.redhataicatalyst.com"


class RunTelemetry:
    def __init__(self, source, task):
        self.source = source
        self.task = task[:500]
        self.tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", DEFAULT_TRACKING_URI).rstrip("/")
        self.experiment_name = os.environ.get("MLFLOW_EXPERIMENT_NAME", "aramco-mcp-maas-roundtrip")
        self.enabled = os.environ.get("MLFLOW_ENABLED", "true").lower() not in {"0", "false", "no", "off"}
        self.experiment_id = None
        self.run_id = None
        self.started_at = time.time()
        self.events = []
        self.error = None

    @staticmethod
    def _slug(value):
        return re.sub(r"[^a-zA-Z0-9_.-]+", "_", value).strip("_")[:80] or "step"

    def _request(self, method, path, payload=None, query=None):
        if not self.enabled:
            return None
        url = f"{self.tracking_uri}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        body = json.dumps(payload).encode() if payload is not None else None
        request = urllib.request.Request(
            url,
            data=body,
            headers={"Content-Type": "application/json", "Accept": "application/json"},
            method=method,
        )
        try:
            with urllib.request.urlopen(request, context=ssl.create_default_context(), timeout=10) as response:
                text = response.read().decode()
                return json.loads(text) if text else {}
        except Exception as exc:
            self.error = str(exc)
            return None

    def start(self):
        if not self.enabled:
            return
        experiment = self._request(
            "GET",
            "/api/2.0/mlflow/experiments/get-by-name",
            query={"experiment_name": self.experiment_name},
        )
        if not experiment or "experiment" not in experiment:
            created = self._request(
                "POST",
                "/api/2.0/mlflow/experiments/create",
                {"name": self.experiment_name, "tags": [{"key": "demo", "value": "saudi-aramco-mcp-maas"}]},
            )
            if created:
                self.experiment_id = created.get("experiment_id")
            else:
                experiment = self._request(
                    "GET",
                    "/api/2.0/mlflow/experiments/get-by-name",
                    query={"experiment_name": self.experiment_name},
                )
        else:
            self.experiment_id = experiment["experiment"].get("experiment_id")
        if not self.experiment_id:
            return

        created = self._request(
            "POST",
            "/api/2.0/mlflow/runs/create",
            {
                "experiment_id": self.experiment_id,
                "start_time": int(self.started_at * 1000),
                "tags": [
                    {"key": "mlflow.runName", "value": f"{self.source} MCP MaaS round trip"},
                    {"key": "demo.source", "value": self.source},
                    {"key": "demo.task", "value": self.task},
                    {"key": "mcp.gateway", "value": "Kuadrant MCP Gateway"},
                    {"key": "mcp.servers", "value": "MemPalace, OpenShift MCP"},
                ],
            },
        )
        if created:
            self.run_id = created.get("run", {}).get("info", {}).get("run_id")
        self.param("model", os.environ.get("MODEL", "granite-31-8b-lab-v1"))
        self.param("mcp_transport", "streamable-http")
        self.param("telemetry_source", self.source)

    def param(self, key, value):
        if self.run_id:
            self._request("POST", "/api/2.0/mlflow/runs/log-parameter", {"run_id": self.run_id, "key": key, "value": str(value)[:500]})

    def tag(self, key, value):
        if self.run_id:
            self._request("POST", "/api/2.0/mlflow/runs/set-tag", {"run_id": self.run_id, "key": key, "value": str(value)[:500]})

    def metric(self, key, value, step=0):
        if self.run_id:
            self._request(
                "POST",
                "/api/2.0/mlflow/runs/log-metric",
                {"run_id": self.run_id, "key": self._slug(key), "value": float(value), "timestamp": int(time.time() * 1000), "step": step},
            )

    def event(self, name, duration_ms, detail="", layer=""):
        event = {"name": name, "duration_ms": round(duration_ms, 2), "detail": detail[:500], "layer": layer}
        self.events.append(event)
        index = len(self.events)
        self.metric(f"step_{index:02d}_{name}_duration_ms", duration_ms, index)
        self.tag(f"trace.{index:02d}.name", name)
        self.tag(f"trace.{index:02d}.layer", layer)
        self.tag(f"trace.{index:02d}.detail", detail)

    def finish(self, success, error=None, metrics=None):
        if self.run_id:
            elapsed = (time.time() - self.started_at) * 1000
            self.metric("roundtrip_duration_ms", elapsed)
            self.metric("roundtrip_success", 1 if success else 0)
            if metrics:
                for key, value in metrics.items():
                    self.metric(key, value)
            self.tag("demo.status", "FINISHED" if success else "FAILED")
            if error:
                self.tag("demo.error", error)
            self._request(
                "POST",
                "/api/2.0/mlflow/runs/update",
                {"run_id": self.run_id, "status": "FINISHED" if success else "FAILED", "end_time": int(time.time() * 1000)},
            )
        return self.info()

    def info(self):
        if not self.run_id:
            return {"enabled": self.enabled, "available": False, "error": self.error}
        return {
            "enabled": True,
            "available": True,
            "tracking_uri": self.tracking_uri,
            "experiment": self.experiment_name,
            "experiment_id": self.experiment_id,
            "run_id": self.run_id,
            "url": f"{self.tracking_uri}/#/experiments/{self.experiment_id}/runs/{self.run_id}",
        }
