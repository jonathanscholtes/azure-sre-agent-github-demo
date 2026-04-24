"""
Synthetic load generator for the SRE demo.

Runs as an Azure Container Apps Job on a cron schedule.
Generates healthy traffic to provide Application Insights telemetry for the SRE agent.
"""
import json
import os
import sys
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "").rstrip("/")
LOAD_COUNT = int(os.environ.get("LOAD_COUNT", "10"))


def post(path: str, body: dict | None = None) -> dict:
    url = f"{API_URL}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")
        return {"error": e.code, "detail": body_text}


def main():
    if not API_URL:
        print("ERROR: API_URL environment variable is not set", file=sys.stderr)
        sys.exit(1)

    print(f"Target: {API_URL}")

    result = post(f"/api/demo/simulate-load?orders={LOAD_COUNT}")
    print(f"Healthy load: {result.get('created', 0)} orders processed")
    print("Done.")


if __name__ == "__main__":
    main()
