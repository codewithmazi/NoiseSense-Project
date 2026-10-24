"""M1: load test of POST /metrics, against objectives fixed before the run."""

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
    # O2 and O3 apply only to steps at or below LAB_CAP clients.
    worst_p95 = max((s["p95_ms"] for s in within), default=None)
    worst_err = max((s["error_rate"] for s in within), default=None)
    first_throttle = next((s["concurrency"] for s in summaries if s["error_rate"] > 0), None)

    def verdict(value, limit, fmt):
        if value is None:
            return f"not assessed (no step at or below {LAB_CAP} clients in this run)"
        return f"worst {fmt.format(value)}  {'MET' if value <= limit else 'NOT MET'}"
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
        f"  O2 p95 <= {OBJ_P95_MS:.0f} ms at <= {LAB_CAP} clients: "
        + verdict(worst_p95, OBJ_P95_MS, "{:.0f} ms"),
        f"  O3 error rate <= {OBJ_ERR:.0%} at <= {LAB_CAP} clients: "
        + verdict(worst_err, OBJ_ERR, "{:.1%}"),
        f"  First step with any errors: {first_throttle if first_throttle else 'none'} clients",
    ]
    text = "\n".join(lines)
    print("\n" + text)
    (out / "m1_summary.txt").write_text(text, encoding="utf-8")
    (out / "m1_summary.json").write_text(json.dumps(summaries, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
