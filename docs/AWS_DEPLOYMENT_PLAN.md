# ByteOps AWS Serverless Deployment and CI/CD Plan

## Current Deployment Status

As of June 4, 2026, the staging backend foundation is deployed in AWS account
`574009336630`, region `us-east-1`.

| Item | Status |
|---|---|
| FastAPI Lambda | Deployed and healthy |
| Backend URL | `https://bcsrqykmzu2344bp5urt2emhni0ohvhx.lambda-url.us-east-1.on.aws/` |
| Frontend URL | `https://2fv3xemmk47tcunkp35asu325m0zwaiz.lambda-url.us-east-1.on.aws/` |
| Worker Lambda | Deployed and consuming SQS jobs |
| SQS and DLQ | Deployed; smoke test passed with both queues empty afterward |
| EventBridge schedules | Enabled hourly for sync and workflows |
| Secrets Manager | Populated from local `.env`; values are not in Terraform state |
| Terraform state | Encrypted, versioned S3 state with locking |
| CloudWatch alarms | Deployed |
| ECR vulnerability scans | API and worker release images completed with no findings |
| AWS Budget | Deployed at `$25/month`; no email notification until an alert email is provided |
| PostgreSQL | Using managed Neon PostgreSQL, not a local database |
| Frontend | Deployed on Lambda with the AWS Lambda Web Adapter |
| GitHub Actions activation | Active through OIDC for `Rafayktk/ByteOps2.0` `main`; CI and staging deployment runs verified |

The frontend Lambda loads its Clerk secret from Secrets Manager during startup.
Its Function URL uses buffered responses because Next.js SSR did not produce a
valid response body through the initial streaming configuration. Deployment
smoke tests require non-empty frontend HTML containing `ByteOps`.

The generated backend URL is suitable for staging tests. OAuth providers must
be updated to allow the generated callback URLs before OAuth flows will work.

### Remaining Owner Actions

- Rotate the Clerk secret key that was exposed outside Secrets Manager, then update `.env` and `byteops-staging/application`.
- Add the generated frontend URL to the Clerk application's allowed URLs.
- Add the generated backend callback URLs to each enabled OAuth provider.
- Provide an alert email to activate SNS and AWS Budget email delivery.
- Approve the higher recurring cost before replacing Neon with RDS/RDS Proxy. The current VPC has only public subnets, so private Lambda-to-RDS access also requires private subnets and a NAT strategy.

### Generated OAuth Callback URLs

- Gmail: `https://bcsrqykmzu2344bp5urt2emhni0ohvhx.lambda-url.us-east-1.on.aws/api/auth/gmail/callback`
- Calendar: `https://bcsrqykmzu2344bp5urt2emhni0ohvhx.lambda-url.us-east-1.on.aws/api/auth/calendar/callback`
- GitHub: `https://bcsrqykmzu2344bp5urt2emhni0ohvhx.lambda-url.us-east-1.on.aws/api/auth/github/callback`
- Slack: `https://bcsrqykmzu2344bp5urt2emhni0ohvhx.lambda-url.us-east-1.on.aws/api/auth/slack/callback`
- Jira: `https://bcsrqykmzu2344bp5urt2emhni0ohvhx.lambda-url.us-east-1.on.aws/api/auth/jira/callback`
- Dropbox: `https://bcsrqykmzu2344bp5urt2emhni0ohvhx.lambda-url.us-east-1.on.aws/api/auth/dropbox/callback`
- Trello: `https://bcsrqykmzu2344bp5urt2emhni0ohvhx.lambda-url.us-east-1.on.aws/api/auth/trello/callback`

These URLs must also be registered in each provider's developer console. AWS
cannot configure OAuth applications owned by external provider accounts.

| Provider | Where to add the callback URL |
|---|---|
| Google Gmail and Calendar | Google Cloud Console -> APIs & Services -> Credentials -> OAuth 2.0 Client -> Authorized redirect URIs. Add both Gmail and Calendar callback URLs. |
| Atlassian Jira | Atlassian Developer Console -> app -> Authorization -> OAuth 2.0 (3LO) -> Callback URL. Add the Jira callback URL. |
| GitHub | GitHub Settings -> Developer settings -> OAuth Apps -> app -> Authorization callback URL. |
| Slack | Slack API Apps -> app -> OAuth & Permissions -> Redirect URLs. |
| Dropbox | Dropbox App Console -> app -> OAuth 2 -> Redirect URIs. |
| Trello | Trello Power-Up/API application settings. Register the Trello callback URL where the application was created. |

Google reports `redirect_uri_mismatch` and Atlassian reports
`redirect_uri is not registered for client` until these exact HTTPS URLs are
saved. They are case-sensitive and must not contain a trailing slash.

## Local Staging Lifecycle Scripts

Run these from the repository root using the locally configured
`byteops-bootstrap` AWS CLI profile:

```powershell
.\scripts\deploy-staging.ps1
.\scripts\destroy-staging.ps1 -PlanOnly
.\scripts\destroy-staging.ps1
```

`deploy-staging.ps1` validates AWS access, creates missing ECR bootstrap
repositories, builds and pushes all Lambda images, applies Terraform, updates
Secrets Manager from the ignored local `.env`, synchronizes generated callback
URLs, and runs live frontend/API smoke tests.

`destroy-staging.ps1` requires typing `DESTROY BYTEOPS STAGING` before running
Terraform destroy. It deletes staging Lambda, ECR images/repositories, SQS,
Secrets Manager, schedules, alarms, budget, and staging IAM roles. It
intentionally retains the Terraform state S3 bucket and shared GitHub OIDC
provider so staging can be recreated. After destroy, GitHub Actions deployment
cannot assume its staging role until `deploy-staging.ps1` recreates it locally.
Use `-PlanOnly` to preview everything Terraform would delete without changing
AWS.

## 1. Goal

For a detailed resource-by-resource explanation of the deployed staging
environment, see [AWS_DEPLOYMENT_DETAILS.md](./AWS_DEPLOYMENT_DETAILS.md).

Deploy ByteOps using a serverless-first AWS architecture:

- FastAPI backend on AWS Lambda
- Scheduled and asynchronous work through EventBridge Scheduler, SQS, and worker Lambdas
- Existing relational data model on PostgreSQL
- Next.js frontend on an AWS-hosted server runtime
- Infrastructure managed with Terraform
- CI/CD orchestrated by GitHub Actions
- AWS access bootstrapped from a locally configured AWS CLI profile

## 2. Architecture Decision Summary

| Area | Decision |
|---|---|
| Backend API | Lambda container image running FastAPI through AWS Lambda Web Adapter |
| API entry point | API Gateway REST API with Lambda response streaming enabled |
| Background jobs | SQS queues consumed by worker Lambdas |
| Scheduled jobs | EventBridge Scheduler publishes work to SQS |
| Database | PostgreSQL with RDS Proxy; do not migrate to DynamoDB initially |
| Frontend | Next.js runtime deployment, not a static S3 website |
| S3 | Terraform state, optional build artifacts/uploads, and future large objects |
| Lambda images | ECR repositories |
| Infrastructure | Terraform |
| CI/CD engine | GitHub Actions, which runs tests, builds artifacts, and executes Terraform |
| GitHub AWS authentication | GitHub OIDC roles, not IAM-user access keys |

## 3. Why These Services Fit ByteOps

### Lambda Is Suitable, With Required Refactoring

The current FastAPI application can run in Lambda as a container image. Lambda Web Adapter allows the existing HTTP application shape to be retained, and API Gateway supports Lambda response streaming for the current SSE chat endpoint.

However, the following code cannot remain tied to a web-process lifecycle:

- APScheduler starts during FastAPI startup.
- Immediate syncs use `asyncio.create_task`.
- OAuth callbacks use FastAPI background tasks.
- Approval waits are held in process memory for up to five minutes.
- Database tables are automatically created during application startup.

These paths must move to EventBridge, SQS, persistent state, and explicit database migrations before production deployment.

### SQS Is Required

SQS will decouple API requests from sync and workflow execution:

- OAuth callbacks enqueue an initial sync job.
- Manual sync requests enqueue jobs and return HTTP `202`.
- EventBridge Scheduler enqueues periodic sync/workflow jobs.
- Worker Lambdas process jobs with retries and dead-letter queues.
- Workers must be idempotent because SQS/Lambda processing is at least once.

### DynamoDB Is Not Required Initially

The application currently uses SQLAlchemy relationships, foreign keys, PostgreSQL enums, and JSONB across users, conversations, messages, workflows, notifications, tool connections, and agent runs. Replacing this with DynamoDB would be a major application and query-model rewrite.

Use PostgreSQL initially. DynamoDB may be added later for a narrow purpose such as:

- Idempotency keys for SQS jobs
- Distributed approval/job state
- High-volume ephemeral event status

PostgreSQL can also hold those records, so DynamoDB should only be added after a measured need.

### S3 Is Required, But Not as the Website Host

The Next.js frontend uses Clerk middleware and requires a server runtime, so it cannot be deployed as a purely static S3 website without significant application changes.

Use S3 for:

- Encrypted, versioned Terraform state with state locking
- Optional CI build artifacts
- Future user uploads or large generated files
- Optional long-term log/archive exports

## 4. Recommended AWS Architecture

```text
Users
  |
Route 53 + ACM
  |
  |-- app.example.com --> CloudFront --> Next.js runtime
  |
  `-- api.example.com --> API Gateway REST API
                              |
                              `--> FastAPI API Lambda container
                                      |
                                      |--> RDS Proxy --> PostgreSQL
                                      |--> Secrets Manager
                                      `--> SQS queues
                                             |
                                             `--> Worker Lambda(s)
                                                    |
                                                    `--> PostgreSQL/external APIs

EventBridge Scheduler --> SQS queues --> Worker Lambda(s)

GitHub Actions --OIDC--> AWS deploy roles
  |-- Terraform plan/apply
  |-- Build Lambda images
  `-- Push immutable images to ECR
```

### Frontend Runtime Decision

The frontend cannot be hosted only in S3. During implementation, use one of these runtime options:

1. **Preferred serverless-first option:** Next.js container on Lambda using Lambda Web Adapter behind CloudFront.
2. **Fallback option:** Next.js on ECS Fargate if Lambda compatibility or cold-start testing is unacceptable.

AWS Amplify managed SSR is not the first choice because the repository currently uses Next.js 16 while AWS documentation currently lists managed SSR support through Next.js 15.

## 5. AWS Resources To Implement

### API and Compute

| Resource | Purpose |
|---|---|
| API Gateway REST API | Public backend endpoint and response streaming |
| FastAPI API Lambda | Handles short synchronous API and SSE requests |
| Sync worker Lambda | Processes Gmail/Calendar/tool synchronization jobs |
| Workflow worker Lambda | Processes scheduled and manually triggered workflows |
| Migration Lambda or one-off deployment job | Runs Alembic migrations before application release |
| Lambda aliases | Stable `staging` and `production` targets with rollback |
| Provisioned concurrency, optional | Reduce cold starts for latency-sensitive API routes |

### Messaging and Scheduling

| Resource | Purpose |
|---|---|
| Sync SQS queue | Buffers immediate and scheduled sync jobs |
| Workflow SQS queue | Buffers workflow execution jobs |
| Dead-letter queue per source queue | Captures repeatedly failing jobs |
| EventBridge Scheduler | Replaces the in-process APScheduler |
| Optional DynamoDB idempotency table | Add only if PostgreSQL-based idempotency is insufficient |

### Data and Storage

| Resource | Purpose |
|---|---|
| RDS PostgreSQL or Aurora PostgreSQL | Existing relational application database |
| RDS Proxy | Protects PostgreSQL from Lambda connection bursts |
| Secrets Manager | Application secrets, OAuth credentials, and database credentials |
| S3 Terraform state bucket | Encrypted/versioned Terraform state and lock files |
| Optional application S3 bucket | Future uploads, large objects, or archives |
| ECR repositories | API, worker, migration, and frontend Lambda container images |

### Frontend, DNS, and Security

| Resource | Purpose |
|---|---|
| Frontend Lambda and Function URL/origin integration | Runs Next.js SSR and Clerk middleware |
| CloudFront distribution | Frontend CDN and custom domain |
| Route 53 records | Frontend and API DNS |
| ACM certificates | HTTPS |
| AWS WAF, recommended for production | Managed protection for CloudFront/API Gateway |
| IAM execution/deploy roles | Least-privilege runtime and deployment access |

### Operations

| Resource | Purpose |
|---|---|
| CloudWatch log groups | API, worker, migration, and frontend logs |
| CloudWatch alarms | Lambda errors/throttles/duration, API 5xx, SQS age/depth, DLQ messages, database health |
| SNS topic | Alarm notifications |
| AWS Budgets | Monthly spend alerts |
| CloudTrail | AWS API audit trail |

## 6. Required Application Refactoring

### API Lambda

- Package FastAPI as a Lambda container image with AWS Lambda Web Adapter.
- Remove APScheduler startup/shutdown from FastAPI lifespan.
- Remove automatic table creation from application startup.
- Configure API Gateway response streaming and verify the SSE chat endpoint end to end.
- Set Lambda timeouts based on route behavior, never above Lambda's 15-minute maximum.
- Keep API work short; enqueue long work to SQS.

### Background Jobs

- Replace `asyncio.create_task` sync execution with SQS publishing.
- Replace FastAPI OAuth background tasks with SQS publishing.
- Replace hourly APScheduler jobs with EventBridge Scheduler.
- Create SQS worker handlers using partial batch failure responses.
- Add idempotency keys and safe retry behavior.
- Configure DLQs and alarms.

### Approval Flow

The current approval flow stores `asyncio.Event` objects in process memory and waits for up to five minutes. This is not reliable on Lambda.

Refactor approval handling to:

1. Persist an approval request with an expiry.
2. Return/stream an `approval_required` event and end the current invocation.
3. Let the approval API update persistent state.
4. Enqueue a continuation job when approved.
5. Let the worker resume execution from persisted state.

Use PostgreSQL first; Step Functions or Lambda durable functions can be evaluated later if workflow orchestration becomes more complex.

### Database

- Add and use Alembic migrations.
- Run migrations once during deployment, before shifting traffic.
- Use RDS Proxy for Lambda database connections.
- Tune SQLAlchemy pooling for Lambda rather than long-running servers.
- Encrypt OAuth tokens at the application level before storage.

### Frontend

- Test Next.js 16 and Clerk middleware on the selected Lambda runtime approach.
- Keep `NEXT_PUBLIC_*` values as build-time inputs.
- Configure CloudFront behavior for dynamic routes and static assets.
- Use S3 only for static/user objects where appropriate, not as the sole website host.

## 7. CI/CD: GitHub Actions and Terraform

### Can Terraform Be the CI/CD System?

Terraform is infrastructure as code, not a CI/CD runner. It declares and updates AWS resources, but it does not watch GitHub, run tests, manage approvals, or trigger itself.

Use:

- **GitHub Actions as the CI/CD orchestrator**
- **Terraform inside GitHub Actions to provision and update AWS**

This gives one controlled pipeline while keeping AWS infrastructure reproducible.

### Recommended Deployment Pattern

1. GitHub Actions runs backend/frontend tests and security checks.
2. GitHub Actions builds immutable Lambda container images.
3. Images are tagged with the Git commit SHA and pushed to ECR.
4. GitHub Actions runs `terraform plan` using the new image digest.
5. An approved `terraform apply` updates Lambda versions/aliases and infrastructure.
6. The migration job runs before production traffic moves.
7. Smoke tests verify API health, SSE streaming, frontend, SQS workers, and OAuth callbacks.
8. Rollback moves Lambda aliases to the previous known-good versions.

### Workflows

| Workflow | Trigger | Actions |
|---|---|---|
| `ci.yml` | Pull requests and pushes | Backend lint/tests, frontend lint/tests/build, dependency and secret scans |
| `terraform-plan.yml` | Infrastructure/application pull requests | Validate, format, scan, and publish Terraform plan |
| `deploy-staging.yml` | Merge to `main` | Build/push images, Terraform apply, migrate, deploy aliases, smoke test |
| `deploy-production.yml` | Manual dispatch or release tag | Require approval, deploy approved commit, migrate, smoke test |
| `rollback.yml` | Manual dispatch | Move aliases back to selected known-good Lambda versions |

### GitHub Authentication To AWS

GitHub Actions must use OIDC to assume environment-specific AWS IAM roles. Do not place the IAM user's `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` in GitHub secrets.

Create:

- GitHub OIDC provider
- Pull-request Terraform plan role
- Staging deployment role
- Production deployment role restricted to the protected `production` GitHub Environment

## 8. Local AWS CLI Access

Yes, `aws configure` can connect the local CLI using an IAM user's access key and secret key. Those are long-lived credentials, so use them only for initial bootstrap if IAM Identity Center SSO is unavailable.

### IAM User Bootstrap Option

Run locally:

```powershell
aws configure --profile byteops-bootstrap
aws sts get-caller-identity --profile byteops-bootstrap
```

When deployment work starts, provide only:

- The configured profile name, for example `byteops-bootstrap`
- The AWS region
- The AWS account ID returned by `aws sts get-caller-identity`

Do **not** paste the access key, secret key, console password, root credentials, or MFA codes into chat or repository files.

The bootstrap IAM user needs permission to create the initial Terraform state bucket, GitHub OIDC provider/roles, and application infrastructure. After GitHub OIDC deployment roles work, reduce or remove the bootstrap user's permissions.

### Safer Alternative

AWS IAM Identity Center SSO with `aws configure sso` is preferred because it uses temporary credentials. The rest of the plan works with either local bootstrap method.

## 9. Secrets and Configuration

### Store In Secrets Manager

- Database credentials/URL
- Clerk secret key, issuer, and webhook secret
- LLM provider API key
- OAuth client secrets
- Any shared encryption keys

### Store As Lambda Environment Variables

- Secret ARNs, not secret values
- CORS origins and frontend URL
- Queue URLs
- Non-sensitive OAuth callback URLs
- Application environment and log level

### Store As GitHub Variables

- AWS region
- GitHub OIDC deploy role ARNs
- ECR repository names
- Terraform state bucket/key
- Public frontend/API URLs
- `NEXT_PUBLIC_API_URL`
- `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`

## 10. Environment Design

### Staging

- Separate Terraform state and resource names
- Smaller PostgreSQL instance
- Lower Lambda memory/provisioned concurrency
- Automatic deployment from `main`
- Full SQS/DLQ/EventBridge behavior enabled

### Production

- Prefer a separate AWS account; otherwise use strongly isolated resources
- Protected GitHub `production` Environment with approval
- Database Multi-AZ/deletion protection/backups
- Lambda aliases and rollback workflow
- WAF, stricter alarms, and budget alerts

## 11. Deployment Phases

### Phase 0: Bootstrap Decisions

- [ ] Confirm AWS region and account
- [ ] Confirm local AWS CLI profile name
- [ ] Confirm domain/subdomains
- [ ] Confirm staging and production account strategy
- [ ] Confirm launch OAuth integrations and budget alert amount

### Phase 1: Serverless Readiness

- [ ] Add Lambda Web Adapter backend image
- [ ] Remove API-process scheduler and table creation
- [ ] Add Alembic migrations
- [ ] Replace immediate/background syncs with SQS publishing
- [ ] Add EventBridge schedules and worker handlers
- [ ] Refactor approval waits into persistent asynchronous continuation
- [ ] Verify SSE response streaming through API Gateway

### Phase 2: Terraform Foundation

- [ ] Bootstrap encrypted/versioned S3 Terraform state
- [ ] Create GitHub OIDC provider and least-privilege roles
- [ ] Create API Gateway, Lambda, ECR, SQS, DLQs, and EventBridge resources
- [ ] Create PostgreSQL, RDS Proxy, Secrets Manager, DNS, and certificates
- [ ] Create CloudWatch alarms, SNS notifications, and budgets

### Phase 3: CI/CD

- [ ] Add CI and security workflows
- [ ] Add Terraform plan/apply workflows
- [ ] Add staging, production, and rollback workflows
- [ ] Configure GitHub Environments and approvals
- [ ] Verify immutable image and Lambda version deployment

### Phase 4: Launch

- [ ] Deploy staging and test frontend, API, SSE, queues, schedules, and OAuth
- [ ] Test DLQ, retry, idempotency, migration, and rollback behavior
- [ ] Register production OAuth callback URLs
- [ ] Deploy production and run smoke tests

## 12. Definition of Done

- [ ] FastAPI runs on Lambda and all synchronous endpoints pass smoke tests.
- [ ] SSE chat streaming works through API Gateway.
- [ ] No scheduler or required background task depends on Lambda process lifetime.
- [ ] Sync and workflow jobs run through SQS with retries, idempotency, and DLQs.
- [ ] Approval continuations survive Lambda termination and deployment.
- [ ] PostgreSQL connections go through RDS Proxy.
- [ ] Database migrations run once and can be rolled back safely.
- [ ] Terraform owns AWS resources and uses encrypted/versioned S3 state.
- [ ] GitHub Actions uses OIDC and contains no permanent AWS credentials.
- [ ] Production deployments require approval and support alias rollback.
- [ ] CloudWatch and budget alarms reach the chosen destination.

## 13. Main Risks

| Risk | Mitigation |
|---|---|
| SSE or long-running agent requests exceed Lambda/API limits | Test streaming early; cap execution time and move long work to SQS |
| In-memory approval flow breaks on Lambda | Persist approval state and continue through queued jobs |
| Lambda concurrency overwhelms PostgreSQL | Use RDS Proxy, reserved concurrency, and query/pool tuning |
| SQS delivers duplicate jobs | Add idempotency keys and partial batch responses |
| Frontend Next.js 16 runtime compatibility | Test Lambda runtime first; retain ECS Fargate fallback |
| IAM-user credentials leak | Keep keys only in local AWS CLI profile; use GitHub OIDC for CI/CD |

## 14. Inputs Needed Before Deployment Starts

Provide these values after configuring AWS CLI:

1. Local AWS CLI profile name
2. AWS region
3. AWS account ID
4. Domain/subdomains, or confirmation to use generated AWS URLs initially
5. Alert email
6. Monthly budget alert threshold
7. Required OAuth integrations for first launch
8. Staging/production account strategy

Do not provide raw AWS access keys.

## 15. Official References

- [AWS Lambda response streaming](https://docs.aws.amazon.com/lambda/latest/dg/configuration-response-streaming.html)
- [API Gateway Lambda response streaming](https://docs.aws.amazon.com/apigateway/latest/developerguide/response-streaming-lambda-configure.html)
- [AWS Lambda timeout limits](https://docs.aws.amazon.com/lambda/latest/dg/configuration-timeout.html)
- [Using Lambda with SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)
- [AWS Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [GitHub Actions OIDC for AWS](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
