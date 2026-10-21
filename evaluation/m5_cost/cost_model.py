"""M5: monthly cost of NoiseSense at 1k, 10k and 100k users.

Answers the 602 criticism that "$0.49 is the cost of an empty system".

Every input is one of three kinds, labelled in INPUTS below:
  MEASURED  - from a test actually run (M1, M2, device tests)
  PRICE     - AWS list price, us-east-1, from the AWS Price List API
              (offers/v1.0/aws/<service>/current/us-east-1/index.json,
              downloaded 19 Oct 2026; publication dates noted per service)
              or, for the Cognito free tier, aws.amazon.com/cognito/pricing
  ASSUMED   - a usage assumption, stated so it can be challenged; the
              sensitivity table shows how much each one matters

Free tiers: only the permanent ones are applied (Lambda 1M requests and
400,000 GB-s, Cognito 10,000 MAU, DynamoDB 25 GB storage, SNS 1,000 emails
and 1M publishes, 100 GB data transfer out). The 12-month API Gateway free
tier is ignored, because a service is costed for its life, not its first year.

Usage:  python cost_model.py > m5_results.txt
"""

import math

# --------------------------------------------------------------- INPUTS
INPUTS = {
    # MEASURED
    "ingest_warm_ms":       (69.6,  "MEASURED", "M2: mean warm handler time, 8,249 invocations"),
    "ingest_cold_share":    (0.0022, "MEASURED", "M2: 18 cold of 8,267 invocations under load"),
    "ingest_cold_extra_ms": (932.0, "MEASURED", "M2: 518.6 ms init + 414 ms slower first handler"),
    "lambda_memory_gb":     (0.125, "MEASURED", "template.yaml: MemorySize 128 MB (M2 used ~93 MB)"),
    # ASSUMED
    "threshold_ms":         (80.0,  "ASSUMED", "threshold Lambda not measured; GetItem + compare, set near ingest"),
    "summary_scan_note":    (None,  "ASSUMED", "weekly summary costed separately: it scans the whole table"),
    "readings_per_hour":    (60,    "MEASURED", "one 60 s window per minute (device tests, 16 Oct)"),
    "item_bytes":           (220,   "ASSUMED", "one reading: keys + timestamp + dbA, laeq, label, confidence"),
    "history_calls_day":    (10,    "ASSUMED", "app opens/refreshes per active user per day"),
    "history_bytes":        (22_000, "ASSUMED", "GET /history: 100 items x ~220 B"),
    "alerts_per_user_day":  (2,     "ASSUMED", "LAeq alerts after the 19 Oct fix; no rate limit exists"),
    "log_bytes_ingest":     (520,   "ASSUMED", "START/END/REPORT lines + one print per invocation"),
    "log_bytes_threshold":  (400,   "ASSUMED", "START/END/REPORT lines"),
    "log_retention_months": (1,     "ASSUMED", "log storage billed for one month of retention"),
    "storage_months":       (12,    "ASSUMED", "readings kept 12 months; no TTL exists in the template"),
}
HOURS_MEASURED = {"light": 2, "typical": 8, "heavy": 24}  # ASSUMED, per active user per day
USER_TIERS = [1_000, 10_000, 100_000]
DAYS = 30.4

# --------------------------------------------------------------- PRICES
P = {
    "lambda_request":     0.20 / 1e6,       # AWSLambda 2026-10-16
    "lambda_gb_s":        0.0000166667,     # AWSLambda 2026-10-16, tier 1
    "apigw_http_request": 1.00 / 1e6,       # AmazonApiGateway 2026-10-13, first 300M
    "eventbridge_event":  1.00 / 1e6,       # AWSEvents 2026-09-24, custom events
    "ddb_wru":            0.625 / 1e6,      # AmazonDynamoDB 2026-09-11, on-demand
    "ddb_rru":            0.125 / 1e6,
    "ddb_storage_gb_mo":  0.25,             # beyond 25 GB free
    "logs_ingest_gb":     0.50,             # AmazonCloudWatch 2026-10-07
    "logs_store_gb_mo":   0.03,
    "sns_email":          2.00 / 100_000,   # AmazonSNS 2026-09-15, beyond 1,000 free
    "sns_publish":        0.50 / 1e6,       # beyond 1M free
    "kms_key_month":      1.00,             # awskms 2026-09-11
    "cognito_essentials": 0.015,            # per MAU beyond 10,000 (pricing page)
    "cognito_lite_t1":    0.0055,           # Lite: next 90,000 MAU
    "cognito_lite_t2":    0.0046,           # Lite: beyond 100,000
    "transfer_out_gb":    0.09,             # first 100 GB/month free
}
FREE = {"lambda_req": 1e6, "lambda_gb_s": 400_000, "cognito_mau": 10_000,
        "ddb_gb": 25, "sns_email": 1_000, "sns_publish": 1e6, "transfer_gb": 100}


def v(key):
    return INPUTS[key][0]


def cognito(mau, plan):
    billable = max(0, mau - FREE["cognito_mau"])
    if plan == "essentials":
        return billable * P["cognito_essentials"]
    t1 = min(billable, 90_000)
    return t1 * P["cognito_lite_t1"] + max(0, billable - 90_000) * P["cognito_lite_t2"]


PER_EXTRA_ITEM_MS = 5.0  # ASSUMED: added handler time per extra reading in a batch


def month(users, hours, cognito_plan="essentials", batch=1):
    """batch > 1 models a design NOT built: the outbox uploading `batch`
    readings per request (one BatchWriteItem, one EventBridge event, one
    threshold invocation per request). batch=1 is the system as deployed."""
    readings = users * hours * v("readings_per_hour") * DAYS
    uploads = readings / batch
    gets = users * v("history_calls_day") * DAYS * 2          # /history + /settings
    alerts = users * v("alerts_per_user_day") * DAYS

    # Lambda: ingest handles every request; threshold runs per upload event.
    ingest_ms = v("ingest_warm_ms") + v("ingest_cold_share") * v("ingest_cold_extra_ms")
    upload_ms = ingest_ms + (batch - 1) * PER_EXTRA_ITEM_MS
    ingest_inv = uploads + gets
    gb_s = (uploads * upload_ms + gets * ingest_ms
            + uploads * (v("threshold_ms") + (batch - 1) * 1.0)) / 1000 * v("lambda_memory_gb")
    invocations = ingest_inv + uploads
    lam = (max(0, invocations - FREE["lambda_req"]) * P["lambda_request"]
           + max(0, gb_s - FREE["lambda_gb_s"]) * P["lambda_gb_s"])

    # DynamoDB: 1 WRU per reading (<1 KB); threshold GetItem 0.5 RRU
    # (eventually consistent); /history query of ~22 KB = 6 x 4 KB at 0.5 each;
    # /settings GetItem 0.5.
    rru = readings * 0.5 + users * v("history_calls_day") * DAYS * (
        math.ceil(v("history_bytes") / 4096) * 0.5 + 0.5)
    stored_gb = users * hours * v("readings_per_hour") * DAYS * v("storage_months") * v("item_bytes") / 1e9
    ddb = (readings * P["ddb_wru"] + rru * P["ddb_rru"]
           + max(0, stored_gb - FREE["ddb_gb"]) * P["ddb_storage_gb_mo"])

    logs_gb = (ingest_inv * v("log_bytes_ingest") + uploads * v("log_bytes_threshold")) / 1e9
    out_gb = users * v("history_calls_day") * DAYS * v("history_bytes") / 1e9

    lines = {
        "API Gateway (HTTP API)": (uploads + gets) * P["apigw_http_request"],
        "Lambda (ingest + threshold)": lam,
        "EventBridge": uploads * P["eventbridge_event"],
        "DynamoDB (writes, reads, storage)": ddb,
        "CloudWatch Logs": logs_gb * P["logs_ingest_gb"]
                           + logs_gb * v("log_retention_months") * P["logs_store_gb_mo"],
        "SNS email alerts": max(0, alerts - FREE["sns_email"]) * P["sns_email"]
                            + max(0, alerts - FREE["sns_publish"]) * P["sns_publish"],
        "Data transfer out": max(0, out_gb - FREE["transfer_gb"]) * P["transfer_out_gb"],
        f"Cognito ({cognito_plan})": cognito(users, cognito_plan),
        "KMS (1 customer key)": P["kms_key_month"],
    }
    facts = {"readings": readings, "requests": uploads + gets,
             "stored_gb": stored_gb, "mean_rps": (uploads + gets) / (DAYS * 86_400)}
    return lines, facts


def weekly_scan_cost(users, hours):
    """The summary Lambda scans the whole table weekly. Cost and time, by
    month 12, if storage is not expired."""
    gb = users * hours * 60 * DAYS * v("storage_months") * v("item_bytes") / 1e9
    rru = gb * 1e9 / 4096 * 0.5
    return rru * P["ddb_rru"] * 4.35, gb


def main():
    print("M5 cost model, NoiseSense, us-east-1, list prices (USD per month)\n")
    print("Inputs:")
    for k, (val, kind, why) in INPUTS.items():
        if val is not None:
            print(f"  {kind:<8} {k:<22} {val!s:<8} {why}")
    print(f"  ASSUMED  hours measured/user/day: {HOURS_MEASURED}  (typical used below)\n")

    hours = HOURS_MEASURED["typical"]
    for plan in ("essentials", "lite"):
        print(f"--- Typical use ({hours} h/day measured), Cognito {plan} ---")
        results = {u: month(u, hours, plan) for u in USER_TIERS}
        names = list(results[USER_TIERS[0]][0])
        print(f"{'':36}" + "".join(f"{u:>12,}" for u in USER_TIERS))
        for n in names:
            print(f"{n:<36}" + "".join(f"{results[u][0][n]:>12,.2f}" for u in USER_TIERS))
        tot = {u: sum(results[u][0].values()) for u in USER_TIERS}
        print(f"{'TOTAL':<36}" + "".join(f"{tot[u]:>12,.2f}" for u in USER_TIERS))
        print(f"{'per user per month':<36}" + "".join(f"{tot[u] / u:>12,.4f}" for u in USER_TIERS))
        print(f"{'mean request rate (req/s)':<36}"
              + "".join(f"{results[u][1]['mean_rps']:>12,.1f}" for u in USER_TIERS))
        print(f"{'stored by month 12 (GB)':<36}"
              + "".join(f"{results[u][1]['stored_gb']:>12,.1f}" for u in USER_TIERS))
        print()

    print("--- Sensitivity: total at 100,000 users, Cognito essentials ---")
    base = sum(month(100_000, hours)[0].values())
    for label, h in HOURS_MEASURED.items():
        t = sum(month(100_000, h)[0].values())
        print(f"  {label:<8} {h:>2} h/day measured   ${t:>10,.0f}   ({t / base - 1:+.0%} vs typical)")
    saved = INPUTS["threshold_ms"]
    INPUTS["threshold_ms"] = (saved[0] * 3, *saved[1:])
    t = sum(month(100_000, hours)[0].values())
    print(f"  threshold Lambda 3x slower ({saved[0] * 3:.0f} ms)  ${t:>10,.0f}   ({t / base - 1:+.0%})")
    INPUTS["threshold_ms"] = saved
    saved = INPUTS["log_bytes_ingest"]
    INPUTS["log_bytes_ingest"] = (saved[0] * 3, *saved[1:])
    t = sum(month(100_000, hours)[0].values())
    print(f"  ingest logs 3x larger                ${t:>10,.0f}   ({t / base - 1:+.0%})")
    INPUTS["log_bytes_ingest"] = saved
    print()

    print("--- Design option NOT built: batch uploads from the outbox ---")
    print(f"  (assumes +{PER_EXTRA_ITEM_MS:.0f} ms handler time per extra reading in a batch)")
    print(f"{'':36}" + "".join(f"{u:>12,}" for u in USER_TIERS))
    for b in (1, 5, 15, 60):
        tots = [sum(month(u, hours, "lite", batch=b)[0].values()) for u in USER_TIERS]
        label = "as deployed (1 per request)" if b == 1 else f"{b} readings per request"
        print(f"  {label:<34}" + "".join(f"{t:>12,.0f}" for t in tots))
    print("  (totals with Cognito Lite; the per-item DynamoDB writes and storage do not shrink)")
    print()

    print("--- Capacity check against M1 (measured plateau ~139 req/s) ---")
    for u in USER_TIERS:
        r = month(u, hours)[1]["mean_rps"]
        print(f"  {u:>7,} users: mean {r:6.1f} req/s; if all measured at once, "
              f"{u / 60:7.1f} req/s ({u / 60 / 139:.0%} of the measured plateau)")
    print()

    print("--- Weekly summary scan (not in the totals above) ---")
    for u in USER_TIERS:
        cost, gb = weekly_scan_cost(u, hours)
        print(f"  {u:>7,} users: table {gb:8.1f} GB by month 12; scanning it weekly "
              f"costs ${cost:8.2f}/month in reads")


if __name__ == "__main__":
    main()
