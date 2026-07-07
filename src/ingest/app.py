"""Ingest / API Lambda.

Handles:
  POST /metrics  -> validate a noise reading and store it in DynamoDB
  GET  /history  -> return the authenticated user's recent readings
"""
import base64
import decimal
import json
import os
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = os.environ["TABLE_NAME"]
_table = boto3.resource("dynamodb").Table(TABLE_NAME)


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _user_id(event):
    """Extract the Cognito subject (unique user id) from the JWT claims."""
    try:
        return event["requestContext"]["authorizer"]["jwt"]["claims"]["sub"]
    except (KeyError, TypeError):
        return None


def _to_jsonable(obj):
    """DynamoDB returns Decimals; convert them so json.dumps works."""
    if isinstance(obj, list):
        return [_to_jsonable(o) for o in obj]
    if isinstance(obj, dict):
        return {k: _to_jsonable(v) for k, v in obj.items()}
    if isinstance(obj, decimal.Decimal):
        return float(obj)
    return obj


def handler(event, context):
    http = event.get("requestContext", {}).get("http", {})
    method = http.get("method")
    path = http.get("path", "")

    user_id = _user_id(event)
    if not user_id:
        return _response(401, {"message": "Unauthorized"})

    if method == "POST" and path.endswith("/metrics"):
        return _post_metrics(event, user_id)
    if method == "GET" and path.endswith("/history"):
        return _get_history(user_id)
    return _response(404, {"message": "Not found"})


def _post_metrics(event, user_id):
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return _response(400, {"message": "Invalid JSON body"})

    db_a = data.get("dbA")
    if not isinstance(db_a, (int, float)):
        return _response(400, {"message": "Field 'dbA' (number) is required"})

    timestamp = data.get("timestamp") or datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )

    item = {
        "PK": f"USER#{user_id}",
        "SK": f"TS#{timestamp}",
        "type": "reading",
        "timestamp": timestamp,
        "dbA": decimal.Decimal(str(db_a)),
    }
    # Optional fields (numbers stored as Decimal; strings as-is).
    for key in ("laeq", "lat", "long", "source"):
        value = data.get(key)
        if value is None:
            continue
        item[key] = decimal.Decimal(str(value)) if isinstance(value, (int, float)) else value

    _table.put_item(Item=item)
    return _response(201, {"message": "stored", "timestamp": timestamp})


def _get_history(user_id):
    result = _table.query(
        KeyConditionExpression=Key("PK").eq(f"USER#{user_id}") & Key("SK").begins_with("TS#"),
        ScanIndexForward=False,  # newest first
        Limit=100,
    )
    items = _to_jsonable(result.get("Items", []))
    return _response(200, {"count": len(items), "items": items})