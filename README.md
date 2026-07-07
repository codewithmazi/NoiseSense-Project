# Noise Exposure Backend (Proof-of-Concept)

Serverless, event-driven backend for a cloud-based mobile app that helps individuals
understand and review their personal environmental noise exposure. This module delivers the **backend only**;
the mobile front end follows in Module 603.

See `../Build_Sequence.md` for the full staged plan and `../Architecture_Diagram.drawio`
for the architecture.

## Lab constraints (important)
- All execution roles use the pre-created **`LabRole`** — this template creates **no IAM roles**.
- To be deployed in **us-east-1**.
- Session credentials rotate per lab session (CI/CD will be refreshed secrets each session).

## Prerequisites
- AWS SAM CLI and Python 3.12

## Deploy (from CloudShell / Cloud9)
```bash
chmod +x deploy.sh
./deploy.sh arn:aws:iam::<ACCOUNT_ID>:role/LabRole dev
```
Or with the SAM CLI directly:
```bash
sam build
sam deploy --guided   # first time; then `sam deploy`
```

## Validate locally / in CI
```bash
pip install cfn-lint
cfn-lint template.yaml
```
GitHub Actions runs this automatically on push (`.github/workflows/ci.yml`).
