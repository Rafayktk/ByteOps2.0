---
id: 019
title: OAuth Callbacks And Lifecycle Scripts
stage: general
date: 2026-06-05
surface: agent
model: GPT-5
feature: none
branch: main
user: User
command: diagnose OAuth and create lifecycle scripts
labels: ["oauth", "terraform", "aws", "deployment", "destroy"]
links:
  spec: null
  ticket: null
  adr: null
  pr: null
files:
  - scripts/deploy-staging.ps1
  - scripts/destroy-staging.ps1
  - infrastructure/terraform/staging/main.tf
  - docs/AWS_DEPLOYMENT_PLAN.md
tests:
  - PowerShell scripts parsed successfully
  - Terraform validation passed
  - deploy script completed end to end
  - destroy script PlanOnly completed without deletion
  - live OAuth callback configuration inspected
---

## Prompt

these are showing these when we try to open check whats the error and also one
morething so i have to add these urls somewhere and also on emore thing can u
make me a script that when i ever i want to deleet all resources i run that
script and when i want to deploy i run that script and everything works fine?

## Response snapshot

Confirmed the external OAuth applications need the generated AWS callback URLs
registered in their provider consoles. Added guarded local PowerShell deploy
and destroy scripts, made ECR and Secrets Manager safely removable by
Terraform, synchronized generated URLs into Secrets Manager, and documented
provider configuration.

## Outcome

- Impact: Staging can be recreated or removed from local scripts.
- Tests: Script syntax, Terraform validation, and non-destructive preflight passed.
- Files: Lifecycle scripts, Terraform deletion behavior, and OAuth documentation updated.
- Next prompts: Register callback URLs in provider consoles.
- Reflection: Terraform state and the shared OIDC provider remain as bootstrap resources.

## Evaluation notes (flywheel)

- Failure modes observed: External OAuth callback URLs were not registered and Secrets Manager retained a localhost frontend URL.
- Graders run and results (PASS/FAIL): Syntax PASS; Terraform validation PASS; live configuration inspection PASS.
- Prompt variant (if applicable): none
- Next experiment (smallest change to try): Add provider-specific OAuth connection smoke tests after callbacks are registered.
