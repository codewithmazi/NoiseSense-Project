"""Ingest / API Lambda.

Handles:
  POST /metrics  -> validate a noise reading and store it in DynamoDB
  GET  /history  -> return the authenticated user's recent readings
  GET  /settings  -> return the user's exposure threshold
  PUT  /settings  -> update the user's exposure threshold
"""
import base64
import decimal
import json
import os
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = os.environ["TABLE_NAME"]
EVENT_BUS_NAME = os.environ.get("EVENT_BUS_NAME")

# Used only when a user has not set their own threshold (603: FR-05).
DEFAULT_THRESHOLD_DBA = float(os.environ.get("DEFAULT_THRESHOLD_DBA", "70"))

# Sort-key value for a user's settings record.
SETTINGS_SK = "SETTINGS"

# Accepted threshold range. Below 40 dB(A) is quieter than a library and would
# alert constantly; above 100 dB(A) is beyond what an uncalibrated phone
# microphone reports meaningfully (Kardous & Shaw, 2014).
THRESHOLD_MIN_DBA = 40.0
THRESHOLD_MAX_DBA = 100.0

_table = boto3.resource("dynamodb").Table(TABLE_NAME)
_events = boto3.client("events")


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
    if method == "GET" and path.endswith("/settings"):
        return _get_settings(user_id)
    if method == "PUT" and path.endswith("/settings"):
        return _put_settings(event, user_id)
    return _response(404, {"message": "Not found"})


def _parse_body(event):
    """Decode and parse a JSON request body. Returns (data, error_response)."""
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    try:
        return json.loads(raw), None
    except json.JSONDecodeError:
        return None, _response(400, {"message": "Invalid JSON body"})


def _post_metrics(event, user_id):
    data, error = _parse_body(event)
    if error:
        return error

    db_a = data.get("dbA")
    if isinstance(db_a, bool) or not isinstance(db_a, (int, float)):
        return _response(400, {"message": "Field 'dbA' (number) is required"})

    # The client should always supply its own timestamp: it is the idempotency
    # key for offline replay (603: FR-06). Falling back to server time means a
    # retried submission would be stored twice, so the absence is reported.
    client_timestamped = bool(data.get("timestamp"))
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
    # 'confidence' and 'classLabel' carry the on-device classifier output
    # (603: FR-09); without them the model's result would be silently dropped.
    for key in ("laeq", "lat", "long", "source", "classLabel", "confidence"):
        value = data.get(key)
        if value is None:
            continue
        item[key] = decimal.Decimal(str(value)) if isinstance(value, (int, float)) else value

    # Conditional write makes a replayed reading a detectable no-op rather than
    # a silent overwrite, and stops a retry raising a second alert (603: FR-06).
    try:
        _table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(SK)",
        )
    except _table.meta.client.exceptions.ConditionalCheckFailedException:
        print(f"duplicate reading ignored (user={user_id}, ts={timestamp})")
        return _response(
            200,
            {
                "message": "duplicate ignored",
                "timestamp": timestamp,
                "clientTimestamped": client_timestamped,
            },
        )

    _publish_event(user_id, timestamp, float(db_a))
    return _response(
        201,
        {
            "message": "stored",
            "timestamp": timestamp,
            "clientTimestamped": client_timestamped,
        },
    )


def _publish_event(user_id, timestamp, db_a):
    """Best-effort: publish a MetricsReceived event. The reading is already stored,
    so a publish failure is logged but does not fail the request."""
    if not EVENT_BUS_NAME:
        print("WARN: EVENT_BUS_NAME not set; skipping event publish")
        return
    try:
        resp = _events.put_events(
            Entries=[
                {
                    "Source": "noise.ingest",
                    "DetailType": "MetricsReceived",
                    "Detail": json.dumps(
                        {"userId": user_id, "timestamp": timestamp, "dbA": db_a}
                    ),
                    "EventBusName": EVENT_BUS_NAME,
                }
            ]
        )
        failed = resp.get("FailedEntryCount", 0)
        if failed:
            print(
                f"WARN: EventBridge rejected {failed} entry/entries: "
                f"{json.dumps(resp.get('Entries', []))}"
            )
        else:
            print(
                f"published MetricsReceived (userId={user_id}, dbA={db_a}) "
                f"to bus {EVENT_BUS_NAME}"
            )
    except Exception as exc:  
        print(f"WARN: failed to publish MetricsReceived event: {exc}")


def _get_history(user_id):
    result = _table.query(
        KeyConditionExpression=Key("PK").eq(f"USER#{user_id}") & Key("SK").begins_with("TS#"),
        ScanIndexForward=False,  # gets latest data first
        Limit=100,
    )
    items = _to_jsonable(result.get("Items", []))
    return _response(200, {"count": len(items), "items": items})


def _get_settings(user_id):
    """Return the user's threshold, falling back to the stack default.

    'isDefault' lets the client show whether the user has actually chosen a
    value, rather than presenting the fallback as a deliberate setting.
    """
    result = _table.get_item(
        Key={"PK": f"USER#{user_id}", "SK": SETTINGS_SK}
    )
    stored = result.get("Item")
    if not stored or stored.get("thresholdDbA") is None:
        return _response(
            200, {"thresholdDbA": DEFAULT_THRESHOLD_DBA, "isDefault": True}
        )
    return _response(
        200,
        {
            "thresholdDbA": float(stored["thresholdDbA"]),
            "isDefault": False,
            "updatedAt": stored.get("updatedAt"),
        },
    )


def _put_settings(event, user_id):
    """Set the user's exposure threshold (603: FR-05)."""
    data, error = _parse_body(event)
    if error:
        return error

    threshold = data.get("thresholdDbA")
    if isinstance(threshold, bool) or not isinstance(threshold, (int, float)):
        return _response(
            400, {"message": "Field 'thresholdDbA' (number) is required"}
        )
    if not THRESHOLD_MIN_DBA <= float(threshold) <= THRESHOLD_MAX_DBA:
        return _response(
            400,
            {
                "message": (
                    f"'thresholdDbA' must be between {THRESHOLD_MIN_DBA} and "
                    f"{THRESHOLD_MAX_DBA} dB(A)"
                )
            },
        )

    updated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    _table.put_item(
        Item={
            "PK": f"USER#{user_id}",
            "SK": SETTINGS_SK,
            "type": "settings",
            "thresholdDbA": decimal.Decimal(str(threshold)),
            "updatedAt": updated_at,
        }
    )
    return _response(
        200,
        {
            "message": "updated",
            "thresholdDbA": float(threshold),
            "updatedAt": updated_at,
        },
    )