"""Threshold Lambda.

Triggered by EventBridge on each MetricsReceived event. Compares the reading
against the user's own alert threshold and, if it is exceeded, publishes an
alert to SNS.

Which level is compared, and why
--------------------------------
A reading carries two levels for its one-minute window:
  * laeq - the energy average over the minute. This is what the app shows
           in history and what the cumulative dose is built from.
  * dbA  - the loudest 125 ms moment in the minute.
Alerts compare laeq. An earlier version compared dbA, the peak, so a single
door slam in an otherwise quiet minute raised an alert quoting a level the
user never saw in the app (an email said 78.8 dB(A) for a minute the app
showed as 56.7). Alerting on peaks was also the 602 design that the 603
report argues against in favour of cumulative, energy-based exposure.
dbA is used only when laeq is absent, for readings from older clients, and
the email says which figure it is quoting.

Whose threshold
---------------
The user's saved threshold (PK=USER#<id>, SK=SETTINGS, written by PUT
/settings) takes precedence; the stack-wide THRESHOLD_DBA is the fallback for
users who have not chosen one. An earlier version used only the fallback, so
the Settings slider changed the app but not when alerts fired (FR-05).
"""

import os

import boto3

ALERT_TOPIC_ARN = os.environ["ALERT_TOPIC_ARN"]
DEFAULT_THRESHOLD_DBA = float(os.environ.get("THRESHOLD_DBA", "70"))
TABLE_NAME = os.environ.get("TABLE_NAME", "")
SETTINGS_SK = "SETTINGS"

_sns = boto3.client("sns")
_table = boto3.resource("dynamodb").Table(TABLE_NAME) if TABLE_NAME else None


def _user_threshold(user_id):
    """The user's saved threshold, or the stack default.

    Any failure to read it falls back to the default rather than failing the
    invocation: a failed invocation would be retried and then dead-lettered,
    and an alert judged against the default is better than no judgement.
    """
    if _table is None or not user_id or user_id == "unknown":
        return DEFAULT_THRESHOLD_DBA, True
    try:
        item = _table.get_item(
            Key={"PK": f"USER#{user_id}", "SK": SETTINGS_SK}
        ).get("Item")
    except Exception as exc:  # noqa: BLE001 - fall back, never fail the event
        print(f"WARN: could not read settings for {user_id}: {exc}")
        return DEFAULT_THRESHOLD_DBA, True
    if not item or item.get("thresholdDbA") is None:
        return DEFAULT_THRESHOLD_DBA, True
    return float(item["thresholdDbA"]), False


def handler(event, context):
    detail = event.get("detail", {})
    user_id = detail.get("userId", "unknown")
    timestamp = detail.get("timestamp", "")
    laeq = detail.get("laeq")
    peak = detail.get("dbA")

    level = laeq if laeq is not None else peak
    if level is None:
        return {"evaluated": False, "reason": "no level in event"}
    level = float(level)
    measure = "average level (LAeq)" if laeq is not None else "level"

    threshold, is_default = _user_threshold(user_id)
    if level <= threshold:
        return {"evaluated": True, "alerted": False, "level": level, "threshold": threshold}

    whose = "the default alert level" if is_default else "your alert level"
    lines = [
        f"Noise exposure alert for the minute starting {timestamp} (UTC).",
        "",
        f"The {measure} over that minute was {level:.1f} dB(A), above "
        f"{whose} of {threshold:.0f} dB(A).",
    ]
    if laeq is not None and peak is not None:
        lines.append(
            f"The loudest single moment in the minute was {float(peak):.1f} dB(A)."
        )
    lines += [
        "",
        "Levels are measured on your phone and are not calibrated, so treat "
        "them as a guide.",
    ]
    _sns.publish(
        TopicArn=ALERT_TOPIC_ARN,
        Subject="Noise exposure alert",
        Message="\n".join(lines),
        MessageAttributes={
            "userId": {"DataType": "String", "StringValue": str(user_id)}
        },
    )
    return {"evaluated": True, "alerted": True, "level": level, "threshold": threshold}
