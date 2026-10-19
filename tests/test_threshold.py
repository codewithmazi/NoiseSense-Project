"""Unit tests for the threshold Lambda. No AWS access: boto3 is stubbed.

Run from the repo root:  python -m unittest discover -s tests -v
"""

import importlib
import os
import sys
import types
import unittest
from pathlib import Path


class _FakeTable:
    def __init__(self):
        self.items = {}
        self.fail = False

    def get_item(self, Key):
        if self.fail:
            raise RuntimeError("DynamoDB unavailable")
        item = self.items.get((Key["PK"], Key["SK"]))
        return {"Item": item} if item else {}


class _FakeSns:
    def __init__(self):
        self.published = []

    def publish(self, **kwargs):
        self.published.append(kwargs)


def _load(table=None):
    """Import src/threshold/app.py with boto3 replaced by fakes."""
    sns, table = _FakeSns(), table or _FakeTable()
    fake = types.ModuleType("boto3")
    fake.client = lambda name: sns
    fake.resource = lambda name: types.SimpleNamespace(Table=lambda n: table)
    sys.modules["boto3"] = fake
    os.environ.update(ALERT_TOPIC_ARN="arn:test", THRESHOLD_DBA="70", TABLE_NAME="t")
    path = str(Path(__file__).resolve().parents[1] / "src" / "threshold")
    if path not in sys.path:
        sys.path.insert(0, path)
    sys.modules.pop("app", None)
    module = importlib.import_module("app")
    return module, sns, table


def _event(**detail):
    base = {"userId": "u1", "timestamp": "2026-10-19T18:00:00Z"}
    return {"detail": {**base, **detail}}


class ThresholdTests(unittest.TestCase):
    def test_reported_case_quiet_minute_with_one_loud_moment_does_not_alert(self):
        # The case Ron reported: the app showed 56.7, the email said 78.8.
        app, sns, _ = _load()
        result = app.handler(_event(laeq=56.7, dbA=78.8), None)
        self.assertFalse(result["alerted"])
        self.assertEqual(sns.published, [])

    def test_alerts_on_the_average_the_app_shows(self):
        app, sns, _ = _load()
        result = app.handler(_event(laeq=72.4, dbA=88.0), None)
        self.assertTrue(result["alerted"])
        message = sns.published[0]["Message"]
        self.assertIn("average level (LAeq) over that minute was 72.4 dB(A)", message)
        self.assertIn("loudest single moment in the minute was 88.0 dB(A)", message)

    def test_users_own_threshold_takes_precedence(self):
        table = _FakeTable()
        table.items[("USER#u1", "SETTINGS")] = {"thresholdDbA": 55}
        app, sns, _ = _load(table)
        result = app.handler(_event(laeq=60.0, dbA=65.0), None)
        self.assertTrue(result["alerted"], "60 is above the user's 55")
        self.assertIn("your alert level of 55 dB(A)", sns.published[0]["Message"])

    def test_a_raised_user_threshold_suppresses_default_alerts(self):
        table = _FakeTable()
        table.items[("USER#u1", "SETTINGS")] = {"thresholdDbA": 85}
        app, sns, _ = _load(table)
        self.assertFalse(app.handler(_event(laeq=75.0), None)["alerted"])

    def test_default_threshold_when_user_has_none(self):
        app, sns, _ = _load()
        app.handler(_event(laeq=71.0), None)
        self.assertIn("the default alert level of 70 dB(A)", sns.published[0]["Message"])

    def test_settings_read_failure_falls_back_rather_than_failing(self):
        table = _FakeTable()
        table.fail = True
        app, sns, _ = _load(table)
        result = app.handler(_event(laeq=71.0), None)
        self.assertTrue(result["alerted"])
        self.assertEqual(result["threshold"], 70.0)

    def test_older_clients_without_laeq_still_use_dba_and_say_so(self):
        app, sns, _ = _load()
        app.handler(_event(dbA=75.0), None)
        message = sns.published[0]["Message"]
        self.assertIn("The level over that minute was 75.0 dB(A)", message)
        self.assertNotIn("loudest single moment", message)

    def test_exactly_at_the_threshold_does_not_alert(self):
        app, sns, _ = _load()
        self.assertFalse(app.handler(_event(laeq=70.0), None)["alerted"])

    def test_event_without_any_level_is_not_evaluated(self):
        app, sns, _ = _load()
        self.assertFalse(app.handler(_event(), None)["evaluated"])


if __name__ == "__main__":
    unittest.main()
