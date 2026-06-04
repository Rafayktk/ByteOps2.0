---
id: 015
title: Verify AWS Deployment Readiness
stage: general
date: 2026-06-04
surface: agent
model: GPT-5
feature: none
branch: main
user: BILAL JAWAID
command: verify AWS CLI deployment prerequisites
labels: ["aws", "iam", "deployment", "preflight"]
links:
  spec: null
  ticket: null
  adr: null
  pr: null
files:
  - history/prompts/general/015-verify-aws-deployment-readiness.general.prompt.md
tests:
  - aws sts get-caller-identity
  - aws iam list-attached-user-policies
  - aws iam get-account-summary
  - aws budgets describe-budgets
  - git remote -v
---

## Prompt

ootstrap
{                                                                               
    "UserId": "AIDAYLJM7MM3I5LKJYVK3",
    "Account": "574009336630",
    "Arn": "arn:aws:iam::574009336630:user/cl-iam-user"
}

PS C:\Users\User\Desktop\ByteOps> 
''i have doe this in cli now what to do before you will start''

## Response snapshot

Verified that AWS CLI profile `byteops-bootstrap` connects to account `574009336630` in `us-east-1`, the bootstrap IAM user has AdministratorAccess, account MFA is enabled, and no AWS Budget currently exists. Confirmed the repository still points to an upstream GitHub repository the user does not control and identified the remaining inputs required before resource creation.

## Outcome

- Impact: Established AWS deployment readiness and remaining prerequisites without creating resources.
- Tests: Read-only AWS identity, IAM, account, budget, and Git remote checks completed.
- Files: Added this prompt history record.
- Next prompts: Provide a controlled GitHub repository and deployment choices.
- Reflection: AdministratorAccess is sufficient for bootstrap but should be reduced after GitHub OIDC deployment roles are established.

## Evaluation notes (flywheel)

- Failure modes observed: GitHub Actions cannot be configured against the current upstream repository; GitHub CLI is not installed.
- Graders run and results (PASS/FAIL): AWS identity PASS; IAM permissions PASS; Git remote ownership prerequisite FAIL.
- Prompt variant (if applicable): none
- Next experiment (smallest change to try): Create or connect a GitHub repository controlled by the user.
