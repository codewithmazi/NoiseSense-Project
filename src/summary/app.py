"""Summary Lambda.

This function is invoked by the weekly Step Functions workflow. It reads the past week's readings,
computes a per-user weekly summary and risk level, stores each summary in
DynamoDB, writes an aggregate to S3, and returns a human-readable message that
the workflow publishes via SNS.

This uses a table Scan with a filter. A production version would use a time-based query or a GSI.
"""
import decimal
import json
import os
from datetime import datetime, timedelta, timezone

import boto3
from boto3.dynamodb.conditions import Attr

TABLE_NAME = os.environ["TABLE_NAME"]
BUCKET_NAME = os.environ.get("BUCKET_NAME")

_table = boto3.resource("dynamodb").Table(TABLE_NAME)
_s3 = boto3.client("s3")


def _risk_level(avg_dba):
    """Risk rating based on the weekly average dB(A)."""
    if avg_dba is None:
        return "Unknown"
    if avg_dba < 55:
        return "Low"
    if avg_dba <= 70:
        return "Moderate"
    return "High"


def handler(event, context):
    now = datetime.now(timezone.utc)
    cutoff = "TS#" + (now - timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ")
    week_label = now.strftime("%Y-W%W")

    # Collects the past week's readings (paginated scan).
    scan_kwargs = {"FilterExpression": Attr("type").eq("reading") & Attr("Timestamp").gte(cutoff)}
    readings = []
    resp = _table.scan(**scan_kwargs)
    readings.extend(resp.get("Items", []))
    while "LastEvaluatedKey" in resp:
        resp = _table.scan(ExclusiveStartKey=resp["LastEvaluatedKey"], **scan_kwargs)
        readings.extend(resp.get("Items", []))

    # Group readings by user.
    by_user = {}
    for r in readings:
        by_user.setdefault(r["User"], []).append(float(r.get("dbA", 0)))

    summaries = []
    for user, values in by_user.items():
        avg = sum(values) / len(values)
        peak = max(values)
        risk = _risk_level(avg)
        _table.put_item(
            Item={
                "User": user,
                "Timestamp": f"SUMMARY#{week_label}",
                "type": "summary",
                "week": week_label,
                "count": len(values),
                "avgDbA": decimal.Decimal(str(round(avg, 1))),
                "maxDbA": decimal.Decimal(str(round(peak, 1))),
                "risk": risk,
                "generatedAt": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            }
        )
        summaries.append(
            {
                "user": user,
                "avgDbA": round(avg, 1),
                "maxDbA": round(peak, 1),
                "risk": risk,
                "count": len(values),
            }
        )

    # Write an aggregate snapshot to S3.
    if BUCKET_NAME:
        _s3.put_object(
            Bucket=BUCKET_NAME,
            Key=f"summaries/{week_label}.json",
            Body=json.dumps({"week": week_label, "summaries": summaries}, indent=2).encode("utf-8"),
            ContentType="application/json",
        )

    message = f"Weekly noise exposure summary ({week_label}): {len(summaries)} user(s) processed."
    if summaries:
        highest = max(summaries, key=lambda s: s["avgDbA"])
        message += f" Highest weekly average {highest['avgDbA']} dB(A) (risk: {highest['risk']})."

    return {"message": message, "usersProcessed": len(summaries), "week": week_label}