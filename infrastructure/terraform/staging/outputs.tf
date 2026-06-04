output "api_url" {
  value = aws_lambda_function_url.api.function_url
}

output "api_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "worker_repository_url" {
  value = aws_ecr_repository.worker.repository_url
}

output "frontend_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "frontend_url" {
  value = aws_lambda_function_url.frontend.function_url
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}

output "application_secret_name" {
  value = aws_secretsmanager_secret.app.name
}

output "jobs_queue_url" {
  value = aws_sqs_queue.jobs.url
}
