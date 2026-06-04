[CmdletBinding()]
param(
    [string]$Profile = "byteops-bootstrap",
    [string]$Region = "us-east-1",
    [string]$EnvFile = ".env",
    [string]$ExpectedAccountId = "574009336630"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tfDir = Join-Path $root "infrastructure\terraform\staging"
$envPath = Join-Path $root $EnvFile
$accountId = $ExpectedAccountId
$registry = "$accountId.dkr.ecr.$Region.amazonaws.com"
$apiRepo = "$registry/byteops-staging-api"
$workerRepo = "$registry/byteops-staging-worker"
$frontendRepo = "$registry/byteops-staging-frontend"

function Invoke-Checked {
    param([scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE"
    }
}

function Read-DotEnv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Environment file not found: $Path"
    }

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $parts = $trimmed -split "=", 2
        if ($parts.Count -eq 2) {
            $values[$parts[0].Trim()] = $parts[1].Trim().Trim('"').Trim("'")
        }
    }
    return $values
}

function Set-ApplicationSecret {
    param(
        [hashtable]$Values,
        [string]$ApiUrl,
        [string]$FrontendUrl
    )

    $api = $ApiUrl.TrimEnd("/")
    $frontend = $FrontendUrl.TrimEnd("/")
    $Values["FRONTEND_URL"] = $frontend
    $Values["BACKEND_CORS_ORIGINS"] = $frontend
    foreach ($tool in @("gmail", "calendar", "github", "slack", "jira", "trello", "dropbox")) {
        $Values["$($tool.ToUpper())_REDIRECT_URI"] = "$api/api/auth/$tool/callback"
    }

    $temp = New-TemporaryFile
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($temp, ($Values | ConvertTo-Json -Compress), $utf8NoBom)
        Invoke-Checked { aws secretsmanager put-secret-value --secret-id byteops-staging/application --secret-string "file://$temp" --profile $Profile --region $Region --output text --query VersionId }
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

Set-Location $root
$values = Read-DotEnv $envPath
if (-not $values["NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY"]) {
    throw "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY is required in $envPath"
}
$publishableKey = $values["NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY"]

$actualAccountId = (aws sts get-caller-identity --profile $Profile --region $Region --output text --query Account).Trim()
if ($LASTEXITCODE -ne 0) { throw "AWS authentication failed" }
if ($actualAccountId -ne $ExpectedAccountId) {
    throw "AWS profile $Profile targets account $actualAccountId; expected $ExpectedAccountId"
}
Invoke-Checked { terraform "-chdir=$tfDir" init -reconfigure "-backend-config=profile=$Profile" }

$existingApiUrl = terraform "-chdir=$tfDir" output -raw api_url 2>$null
$existingFrontendUrl = terraform "-chdir=$tfDir" output -raw frontend_url 2>$null
$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$bootstrapTag = "bootstrap-$timestamp"
$finalTag = "$((git rev-parse --short=12 HEAD).Trim())-local-$timestamp"

if (-not $existingApiUrl) {
    Write-Host "Creating ECR repositories for bootstrap..."
    Invoke-Checked {
        terraform "-chdir=$tfDir" apply -auto-approve `
            -target=aws_ecr_repository.api `
            -target=aws_ecr_repository.worker `
            -target=aws_ecr_repository.frontend `
            -var "api_image_uri=$apiRepo`:$bootstrapTag" `
            -var "worker_image_uri=$workerRepo`:$bootstrapTag" `
            -var "frontend_image_uri=$frontendRepo`:$bootstrapTag"
    }
}

$password = aws ecr get-login-password --profile $Profile --region $Region
$password | docker login --username AWS --password-stdin $registry
if ($LASTEXITCODE -ne 0) { throw "ECR login failed" }

$buildApiUrl = if ($existingApiUrl) { $existingApiUrl.TrimEnd("/") } elseif ($values["NEXT_PUBLIC_API_URL"]) { $values["NEXT_PUBLIC_API_URL"].TrimEnd("/") } else { "http://localhost:8000" }
$imageTag = if ($existingApiUrl) { $finalTag } else { $bootstrapTag }

if ($existingApiUrl -and $existingFrontendUrl) {
    Set-ApplicationSecret -Values $values -ApiUrl $existingApiUrl -FrontendUrl $existingFrontendUrl
}

Write-Host "Building and pushing Lambda images..."
Invoke-Checked { docker build --platform linux/amd64 --provenance=false -f backend/Dockerfile.lambda -t "$apiRepo`:$imageTag" backend }
Invoke-Checked { docker build --platform linux/amd64 --provenance=false -f backend/Dockerfile.worker -t "$workerRepo`:$imageTag" backend }
Invoke-Checked { docker build --platform linux/amd64 --provenance=false --build-arg "NEXT_PUBLIC_API_URL=$buildApiUrl" --build-arg "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=$publishableKey" -f frontend/Dockerfile.lambda -t "$frontendRepo`:$imageTag" frontend }
Invoke-Checked { docker push "$apiRepo`:$imageTag" }
Invoke-Checked { docker push "$workerRepo`:$imageTag" }
Invoke-Checked { docker push "$frontendRepo`:$imageTag" }

Invoke-Checked {
    terraform "-chdir=$tfDir" apply -auto-approve `
        -var "api_image_uri=$apiRepo`:$imageTag" `
        -var "worker_image_uri=$workerRepo`:$imageTag" `
        -var "frontend_image_uri=$frontendRepo`:$imageTag"
}

$apiUrl = (terraform "-chdir=$tfDir" output -raw api_url).TrimEnd("/")
$frontendUrl = (terraform "-chdir=$tfDir" output -raw frontend_url).TrimEnd("/")
Set-ApplicationSecret -Values $values -ApiUrl $apiUrl -FrontendUrl $frontendUrl

if (-not $existingApiUrl) {
    Write-Host "Rebuilding final images with generated AWS URLs..."
    Invoke-Checked { docker tag "$apiRepo`:$bootstrapTag" "$apiRepo`:$finalTag" }
    Invoke-Checked { docker tag "$workerRepo`:$bootstrapTag" "$workerRepo`:$finalTag" }
    Invoke-Checked { docker build --platform linux/amd64 --provenance=false --build-arg "NEXT_PUBLIC_API_URL=$apiUrl" --build-arg "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=$publishableKey" -f frontend/Dockerfile.lambda -t "$frontendRepo`:$finalTag" frontend }
    Invoke-Checked { docker push "$apiRepo`:$finalTag" }
    Invoke-Checked { docker push "$workerRepo`:$finalTag" }
    Invoke-Checked { docker push "$frontendRepo`:$finalTag" }
    Invoke-Checked {
        terraform "-chdir=$tfDir" apply -auto-approve `
            -var "api_image_uri=$apiRepo`:$finalTag" `
            -var "worker_image_uri=$workerRepo`:$finalTag" `
            -var "frontend_image_uri=$frontendRepo`:$finalTag"
    }
}

Write-Host "Running live smoke tests..."
$frontBody = Invoke-WebRequest -Uri "$frontendUrl/" -UseBasicParsing -TimeoutSec 120
$health = Invoke-RestMethod -Uri "$apiUrl/health" -TimeoutSec 120
if ($frontBody.StatusCode -ne 200 -or $frontBody.Content -notmatch "ByteOps") { throw "Frontend smoke test failed" }
if ($health.status -ne "healthy") { throw "API health smoke test failed" }

Write-Host ""
Write-Host "Deployment complete."
Write-Host "Frontend: $frontendUrl/"
Write-Host "API:      $apiUrl/"
