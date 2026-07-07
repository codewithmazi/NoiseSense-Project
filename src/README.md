# src/

Lambda source code lives here. Added from **Stage 3** onward.

Planned handlers (one folder each):
- `ingest/` — Ingest/API Lambda: validate metrics, write to DynamoDB, publish `MetricsReceived`, serve reads (Stage 3–4).
- `threshold/` — Threshold Lambda: compare against WHO-based thresholds, publish alerts to SNS (Stage 4).
- `summary/` — Summary Lambda: compute weekly summary and risk level (Stage 5).
- `maprender/` — Map-Render Lambda: geohash aggregation + Leaflet/GeoJSON map to S3 (Stage 8, stretch).

Every function will reference the pre-created **LabRole** (no IAM roles are created by the template).
