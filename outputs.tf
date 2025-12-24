output "vpc_id" {
  value = module.network.vpc_id
}

output "subnet_ids" {
  value = module.network.subnet_ids
}

output "cloudtrail_arn" {
  value = module.audit.cloudtrail_arn
}

output "config_recorder_name" {
  value = module.audit.config_recorder_name
}

output "sns_topic_arn" {
  value = module.audit.sns_topic_arn
}
