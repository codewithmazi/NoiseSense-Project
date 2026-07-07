# src/

Lambda source code lives here.

Planned handlers (one folder each):
- `ingest/` — Ingest/API Lambda: validate metrics, write to DynamoDB, publish `MetricsReceived`, serve reads.
- `threshold/` — Threshold Lambda: compare against WHO-based thresholds, publish alerts to SNS.
- `summary/` — Summary Lambda: compute weekly summary and risk level.
- `maprender/` — Map-Render Lambda: tbd

Every function will reference the pre-created **LabRole** (no IAM roles are created by the template).
