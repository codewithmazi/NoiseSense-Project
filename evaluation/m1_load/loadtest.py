"""M1: load test of POST /metrics, against objectives fixed before the run.

PRE-REGISTERED OBJECTIVE (NFR performance efficiency; set 19 Oct 2026 before
any load was applied, so the result cannot be fitted to the target):

  O1  Sustain >= 20 requests/s on POST /metrics.
      Why 20: each user uploads one reading a minute, so 20 req/s is 1,200
      users uploading at once, comfortably above the 1k-user tier in M5.
  O2  p95 end-to-end latency <= 1,000 ms at up to 10 concurrent clients,
      measured from the client, so it includes the network from the UK.
      Why 1 s and not tighter: uploads run in the background from the
      outbox, so no user waits on them; the binding constraint is
      throughput, and the latency bound only guards against queueing.
  O3  Error rate <= 1% at up to 10 concurrent clients.
      Above 10 the Learner Lab's 10-concurrent-execution Lambda cap is
      expected to throttle (HTTP 503/429). Those are recorded, not hidden:
      finding where throttling starts is part of the measurement.

Method
------
Closed loop: N worker threads each send a request, wait for the reply, and
send the next, for a fixed time per step. Steps rise through the concurrency
levels. Each worker keeps one HTTPS connection alive, as the app does.
Throughput then follows Little's law, X = N / R: with N requests in flight
and mean response time R, at most N/R complete per second.

Payload: dbA 50, below the alert threshold, so no SNS alert email is sent per
request. Timestamps are synthetic and unique (counting up from 2020-01-01),
because the sort key is second-precision: real "now" timestamps from parallel
workers would collide and be stored once, so most writes would be skipped.
2020 timestamps also stay out of recent history and the weekly summary.

Every request triggers the threshold Lambda through EventBridge, which shares
the account's 10-execution cap with ingest. That is the system as deployed,
so it is measured as such.

Usage
-----
Set LOADTEST_EMAIL, LOADTEST_PASSWORD (a dedicated synthetic test account),
CLIENT_ID, API_BASE_URL, and optionally REGION (default us-east-1), then:
    python loadtest.py --steps 1,2,5,10,15,20 --seconds 30 --out results
"""

import argparse
import csv
import itertools
import json
import os
import statistics
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests

OBJ_RPS, OBJ_P95_MS, OBJ_ERR = 20.0, 1000.0, 0.01
LAB_CAP = 10
_counter = itertools.count()
_counter_lock = threading.Lock()
_BASE = datetime(2020, 1, 1, tzinfo=timezone.utc)


def next_timestamp():
    with _counter_lock:
        n = next(_counter)
    return (_BASE + timedelta(seconds=n)).strftime("%Y-%m-%dT%H:%M:%SZ")


def access_token(region, client_id, email, password):
    r = requests.post(
        f"https://cognito-idp.{region}.amazonaws.com/",
        headers={
            "X-Amz-Target": "AWSCognitoIdentityProviderService.InitiateAuth",
            "Content-Type": "application/x-amz-json-1.1",
        },
        data=json.dumps({
            "AuthFlow": "USER_PASSWORD_AUTH",
            "ClientId": client_id,
            "AuthParameters": {"USERNAME": email, "PASSWORD": password},
        }),
        timeout=15,
    )
    r.raise_for_status()
    return r.json()["AuthenticationResult"]["AccessToken"]


def run_step(url, token, concurrency, seconds):
    rows, lock = [], threading.Lock()
    deadline = time.perf_counter() + seconds

    def worker():
        s = requests.Session()
        s.headers.update({"Authorization": f"Bearer {token}",
                          "Content-Type": "application/json"})
        while time.perf_counter() < deadline:
            body = json.dumps({"timestamp": next_timestamp(), "dbA": 50.0, "laeq": 49.0})
            t0 = time.perf_counter()
            try:
                r = s.post(url, data=body, timeout=15)
                status, note = r.status_code, (r.text[:120] if r.status_code >= 300 else "")
            except requests.RequestException as e:
                status, note = 0, type(e).__name__
            ms = (time.perf_counter() - t0) * 1000
            with lock:
                rows.append((concurrency, round(t0, 4), round(ms, 1), status, note))

    threads = [threading.Thread(target=worker) for _ in range(concurrency)]
    start = time.perf_counter()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return rows, time.perf_counter() - start


def pct(values, p):
    if not values:
        return float("nan")
    v = sorted(values)
    k = (len(v) - 1) * p / 100
    lo, hi = int(k), min(int(k) + 1, len(v) - 1)
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def summarise(concurrency, rows, elapsed):
    ok = [r[2] for r in rows if 200 <= r[3] < 300]
    errors = [r for r in rows if not 200 <= r[3] < 300]
    codes = {}
    for r in errors:
        codes[r[3]] = codes.get(r[3], 0) + 1
    n = len(rows)
    return {
        "concurrency": concurrency,
        "requests": n,
        "ok": len(ok),
        "rps_ok": len(ok) / elapsed,
        "p50_ms": pct(ok, 50), "p95_ms": pct(ok, 95), "p99_ms": pct(ok, 99),
        "mean_ms": statistics.mean(ok) if ok else float("nan"),
        "error_rate": len(errors) / n if n else 0.0,
        "error_codes": codes,
        "littles_law_rps": concurrency / (statistics.mean(ok) / 1000) if ok else 0.0,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", default="1,2,5,10,15,20")
    ap.add_argument("--seconds", type=int, default=30)
    ap.add_argument("--pause", type=int, default=5, help="idle seconds between steps")
    ap.add_argument("--out", default="results")
    a = ap.parse_args()

    env = os.environ
    region = env.get("REGION", "us-east-1")
    url = env["API_BASE_URL"].rstrip("/") + "/metrics"
    token = access_token(region, env["CLIENT_ID"], env["LOADTEST_EMAIL"], env["LOADTEST_PASSWORD"])
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc)

    all_rows, summaries = [], []
    for c in [int(x) for x in a.steps.split(",")]:
        print(f"step: {c} concurrent clients for {a.seconds} s ...", flush=True)
        rows, elapsed = run_step(url, token, c, a.seconds)
        s = summarise(c, rows, elapsed)
        summaries.append(s)
        all_rows += rows
        print(f"   {s['requests']} requests, {s['rps_ok']:.1f} ok/s, p95 {s['p95_ms']:.0f} ms, "
              f"errors {s['error_rate']:.1%} {s['error_codes'] or ''}", flush=True)
        time.sleep(a.pause)

    with open(out / "m1_requests.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["concurrency", "t_start_s", "latency_ms", "status", "note"])
        w.writerows(all_rows)

    peak = max(s["rps_ok"] for s in summaries)
    within = [s for s in summaries if s["concurrency"] <= LAB_CAP]
    worst_p95 = max(s["p95_ms"] for s in within)
    worst_err = max(s["error_rate"] for s in within)
    first_throttle = next((s["concurrency"] for s in summaries if s["error_rate"] > 0), None)
    lines = [
        f"M1 load test of POST /metrics, run {started:%Y-%m-%d %H:%M} UTC from the client machine",
        f"Endpoint: {url}",
        "",
        f"{'conc':>4} {'reqs':>6} {'ok/s':>7} {'p50':>6} {'p95':>6} {'p99':>6} "
        f"{'N/R':>7} {'err':>6}  error codes",
    ]
    for s in summaries:
        lines.append(
            f"{s['concurrency']:>4} {s['requests']:>6} {s['rps_ok']:>7.1f} {s['p50_ms']:>6.0f} "
            f"{s['p95_ms']:>6.0f} {s['p99_ms']:>6.0f} {s['littles_law_rps']:>7.1f} "
            f"{s['error_rate']:>6.1%}  {s['error_codes'] or ''}")
    lines += [
        "",
        "Latencies in ms, successful requests only. N/R = Little's-law throughput from",
        "concurrency and mean latency; it should match ok/s if the loop is not starved.",
        "",
        "Against the pre-registered objective:",
        f"  O1 throughput >= {OBJ_RPS:.0f} req/s: peak {peak:.1f}  "
        f"{'MET' if peak >= OBJ_RPS else 'NOT MET'}",
        f"  O2 p95 <= {OBJ_P95_MS:.0f} ms at <= {LAB_CAP} clients: worst {worst_p95:.0f} ms  "
        f"{'MET' if worst_p95 <= OBJ_P95_MS else 'NOT MET'}",
        f"  O3 error rate <= {OBJ_ERR:.0%} at <= {LAB_CAP} clients: worst {worst_err:.1%}  "
        f"{'MET' if worst_err <= OBJ_ERR else 'NOT MET'}",
        f"  First step with any errors: {first_throttle if first_throttle else 'none'} clients",
    ]
    text = "\n".join(lines)
    print("\n" + text)
    (out / "m1_summary.txt").write_text(text, encoding="utf-8")
    (out / "m1_summary.json").write_text(json.dumps(summaries, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
