---
id: 017
title: Complete AWS Staging Deployment
stage: general
date: 2026-06-04
surface: agent
model: GPT-5
feature: none
branch: main
user: User
command: deploy
labels: ["aws", "lambda", "terraform", "github-actions", "cicd"]
links:
  spec: null
  ticket: null
  adr: null
  pr: null
files:
  - .github/workflows/ci.yml
  - .github/workflows/deploy-staging.yml
  - docs/AWS_DEPLOYMENT_PLAN.md
  - frontend/Dockerfile.lambda
  - infrastructure/terraform/staging/main.tf
tests:
  - backend pytest: 97 passed
  - frontend vitest: 210 passed, 3 skipped
  - frontend production build: passed
  - terraform validate: passed
  - terraform plan: no changes
  - AWS API and frontend smoke tests: passed
---

## Prompt

The user asked to complete the AWS deployment using the controlled
`Rafayktk/ByteOps2.0` repository, deploy the frontend using the supplied Clerk
publishable key, activate GitHub Actions CI/CD, and resolve the listed staging
limitations. An exposed Clerk secret from IDE context is intentionally redacted
from this record.

## Response snapshot

Deployed the Next.js frontend on Lambda, created a branch-scoped GitHub OIDC
deployment role and end-to-end GitHub Actions deployment workflow, verified the
existing Lambda/SQS backend and managed Neon PostgreSQL, and documented the
remaining owner-controlled OAuth, Clerk secret rotation, alert email, and RDS
cost-approval actions.

## Outcome

- Impact: Staging frontend and backend are live with Terraform-managed AWS resources and GitHub OIDC CI/CD.
- Tests: Backend, frontend, Terraform, and live smoke tests passed.
- Files: Deployment workflows, Lambda packaging, Terraform, frontend build fixes, and deployment documentation updated.
- Next prompts: Rotate the exposed Clerk secret and provide an alert email or approve RDS recurring costs.
- Reflection: Managed Neon remains the safer database choice under the current monthly budget.

## Evaluation notes (flywheel)

- Failure modes observed: Frontend inherited build issues, malformed Secrets Manager update from PowerShell quoting, and local Terraform backend profile mismatch.
- Graders run and results (PASS/FAIL): Production build PASS; tests PASS; Terraform no-drift PASS; live URL smoke tests PASS.
- Prompt variant (if applicable): none
- Next experiment (smallest change to try): Replace the bootstrap GitHub AdministratorAccess attachment with a scoped deployment policy.
