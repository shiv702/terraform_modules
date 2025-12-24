output "sns_topic_arn" {
  value = aws_sns_topic.security.arn
}

output "cloudtrail_arn" {
  value = try(aws_cloudtrail.this[0].arn, null)
}

output "config_recorder_name" {
  value = try(aws_config_configuration_recorder.this[0].name, null)
}

output "cloudtrail_bucket" {
  value = aws_s3_bucket.cloudtrail.bucket
}

output "config_bucket" {
  value = aws_s3_bucket.config.bucket
}
