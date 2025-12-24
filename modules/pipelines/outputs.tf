output "codecommit_repo_http" {
  value = aws_codecommit_repository.repo.clone_url_http
}

output "pipelines" {
  value = { for k, p in aws_codepipeline.this : k => p.name }
}

output "tfstate_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}
