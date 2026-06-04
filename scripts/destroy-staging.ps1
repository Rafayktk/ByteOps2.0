[CmdletBinding()]
param(
    [string]$Profile = "byteops-bootstrap",
    [string]$Region = "us-east-1",
    [string]$ExpectedAccountId = "574009336630",
    [switch]$PlanOnly,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tfDir = Join-Path $root "infrastructure\terraform\staging"

if (-not $PlanOnly -and -not $Force) {
    $confirmation = Read-Host "Type DESTROY BYTEOPS STAGING to permanently delete staging resources"
    if ($confirmation -cne "DESTROY BYTEOPS STAGING") {
        throw "Destroy cancelled."
    }
}

Set-Location $root
$actualAccountId = (aws sts get-caller-identity --profile $Profile --region $Region --output text --query Account).Trim()
if ($LASTEXITCODE -ne 0) { throw "AWS authentication failed" }
if ($actualAccountId -ne $ExpectedAccountId) {
    throw "AWS profile $Profile targets account $actualAccountId; expected $ExpectedAccountId"
}

terraform "-chdir=$tfDir" init -reconfigure "-backend-config=profile=$Profile"
if ($LASTEXITCODE -ne 0) { throw "Terraform initialization failed" }

$apiImage = aws lambda get-function --function-name byteops-staging-api --profile $Profile --region $Region --query Code.ImageUri --output text 2>$null
$workerImage = aws lambda get-function --function-name byteops-staging-worker --profile $Profile --region $Region --query Code.ImageUri --output text 2>$null
$frontendImage = aws lambda get-function --function-name byteops-staging-frontend --profile $Profile --region $Region --query Code.ImageUri --output text 2>$null

if (-not $apiImage) { $apiImage = "missing.invalid/api:none" }
if (-not $workerImage) { $workerImage = "missing.invalid/worker:none" }
if (-not $frontendImage) { $frontendImage = "missing.invalid/frontend:none" }

if ($PlanOnly) {
    terraform "-chdir=$tfDir" plan -destroy `
        -var "api_image_uri=$apiImage" `
        -var "worker_image_uri=$workerImage" `
        -var "frontend_image_uri=$frontendImage"
}
else {
    terraform "-chdir=$tfDir" destroy -auto-approve `
        -var "api_image_uri=$apiImage" `
        -var "worker_image_uri=$workerImage" `
        -var "frontend_image_uri=$frontendImage"
}
if ($LASTEXITCODE -ne 0) { throw "Terraform destroy failed" }

if ($PlanOnly) {
    Write-Host ""
    Write-Host "Destroy preview complete. No resources were deleted."
    return
}

Write-Host ""
Write-Host "Staging application resources were deleted."
Write-Host "The Terraform state S3 bucket and shared GitHub OIDC provider were intentionally retained."
Write-Host "Run scripts\deploy-staging.ps1 to recreate staging."
