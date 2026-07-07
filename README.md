# Noise Exposure Backend (Proof-of-Concept)

Serverless, event-driven backend for a cloud-based mobile app that helps individuals
understand and review their personal environmental noise exposure. Built for the
**AWS Academy Learner Lab** (Module 602). This module delivers the **backend only**;
the mobile front end follows in Module 603.

See `../Build_Sequence.md` for the full staged plan and `../Architecture_Diagram.drawio`
for the architecture.

## Lab constraints (important)
- All execution roles use the pre-created **`LabRole`** — this template creates **no IAM roles**.
- Deploy in **us-east-1**.
- Session credentials rotate per lab session (refresh CI/CD secrets each session).

## Prerequisites
- AWS SAM CLI and Python 3.12 (both available in AWS CloudShell).
- Your `LabRole` ARN: `arn:aws:iam::<ACCOUNT_ID>:role/LabRole` (find it in the IAM console).

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

## Project structure
```
noise-exposure-backend/
├── template.yaml          # SAM/CloudFormation IaC (Stage 0: params + config marker)
├── samconfig.toml         # SAM deploy config (set LabRole ARN)
├── deploy.sh              # CloudShell deploy helper
├── .github/workflows/     # CI (Stage 0), CD added in Stage 7
├── src/                   # Lambda code, added from Stage 3
└── .gitignore
```

## Current status — Stage 0 (Foundations)
- [x] Repo structure + SAM skeleton with `EnvName` and `LabRoleArn` parameters.
- [x] CI workflow (cfn-lint) on push.
- [ ] Deploy the skeleton stack and confirm a clean create.
- [ ] Confirm CI passes on first commit.

Next: **Stage 1 — Data layer** (DynamoDB + S3).
