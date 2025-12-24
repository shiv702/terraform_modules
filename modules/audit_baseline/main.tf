locals {
  cloudtrail_bucket_name = lower(replace("${var.name_prefix}-${var.aws_account_id}-cloudtrail-logs", "_", "-"))
  config_bucket_name     = lower(replace("${var.name_prefix}-${var.aws_account_id}-config-logs", "_", "-"))
  sns_topic_name         = "${var.name_prefix}-security-topic"
}

# ------------------- SNS -------------------
resource "aws_sns_topic" "security" {
  name = local.sns_topic_name
  tags = merge(var.tags, { Name = local.sns_topic_name })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = var.sns_email_subscriptions

  topic_arn = aws_sns_topic.security.arn
  protocol  = "email"
  endpoint  = each.value
}

# ------------------- KMS -------------------
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "kms" {
  statement {
    sid = "EnableRootPermissions"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid = "AllowCloudTrailUse"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid = "AllowConfigUse"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "logs" {
  description         = "KMS key for CloudTrail/Config log buckets"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms.json
  tags                = merge(var.tags, { Name = "${var.name_prefix}-kms-logs" })
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name_prefix}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

# ------------------- S3 buckets -------------------
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = local.cloudtrail_bucket_name
  force_destroy = false
  tags          = merge(var.tags, { Name = local.cloudtrail_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  statement {
    sid = "AWSCloudTrailAclCheck"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
  }

  statement {
    sid = "AWSCloudTrailWrite"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.aws_account_id}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json
}

# Config bucket
resource "aws_s3_bucket" "config" {
  bucket        = local.config_bucket_name
  force_destroy = false
  tags          = merge(var.tags, { Name = local.config_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "config" {
  bucket = aws_s3_bucket.config.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

data "aws_iam_policy_document" "config_bucket_policy" {
  statement {
    sid = "AWSConfigAclCheck"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config.arn]
  }

  statement {
    sid = "AWSConfigWrite"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.config.arn}/AWSLogs/${var.aws_account_id}/Config/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config_bucket_policy.json
}

# ------------------- CloudTrail -------------------
resource "aws_cloudwatch_log_group" "cloudtrail" {
  count             = (var.enable_cloudtrail && var.cloudtrail_enable_cw_logs) ? 1 : 0
  name              = "/aws/cloudtrail/${var.name_prefix}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.logs.arn
  tags              = merge(var.tags, { Name = "${var.name_prefix}-cloudtrail-log-group" })
}

data "aws_iam_policy_document" "cloudtrail_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudtrail_cw" {
  count              = (var.enable_cloudtrail && var.cloudtrail_enable_cw_logs) ? 1 : 0
  name               = "${var.name_prefix}-cloudtrail-cw-role"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "cloudtrail_cw" {
  count = (var.enable_cloudtrail && var.cloudtrail_enable_cw_logs) ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "cloudtrail_cw" {
  count  = (var.enable_cloudtrail && var.cloudtrail_enable_cw_logs) ? 1 : 0
  name   = "${var.name_prefix}-cloudtrail-cw-policy"
  role   = aws_iam_role.cloudtrail_cw[0].id
  policy = data.aws_iam_policy_document.cloudtrail_cw[0].json
}

resource "aws_cloudtrail" "this" {
  count = var.enable_cloudtrail ? 1 : 0

  name                          = "${var.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  enable_log_file_validation    = true
  is_multi_region_trail         = var.cloudtrail_multi_region
  include_global_service_events = true
  kms_key_id                    = aws_kms_key.logs.arn

  cloud_watch_logs_group_arn = var.cloudtrail_enable_cw_logs ? aws_cloudwatch_log_group.cloudtrail[0].arn : null
  cloud_watch_logs_role_arn  = var.cloudtrail_enable_cw_logs ? aws_iam_role.cloudtrail_cw[0].arn : null

  tags = merge(var.tags, { Name = "${var.name_prefix}-trail" })

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# ------------------- AWS Config -------------------
resource "aws_iam_role" "config" {
  count              = var.enable_config ? 1 : 0
  name               = "${var.name_prefix}-config-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

# Attach AWS managed policy AWS_ConfigRole (recommended replacement for AWSConfigRole)
resource "aws_iam_role_policy_attachment" "config_managed" {
  count      = var.enable_config ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "this" {
  count    = var.enable_config ? 1 : 0
  name     = "${var.name_prefix}-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [aws_iam_role_policy_attachment.config_managed]
}

resource "aws_config_delivery_channel" "this" {
  count          = var.enable_config ? 1 : 0
  name           = "${var.name_prefix}-delivery"
  s3_bucket_name = aws_s3_bucket.config.bucket
  sns_topic_arn  = aws_sns_topic.security.arn

  depends_on = [aws_s3_bucket_policy.config]
}

resource "aws_config_configuration_recorder_status" "this" {
  count      = var.enable_config ? 1 : 0
  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

# Managed rules (dynamic for_each)
resource "aws_config_config_rule" "managed" {
  for_each = var.enable_config ? var.config_managed_rules : {}

  name = each.key

  source {
    owner             = "AWS"
    source_identifier = each.value.identifier
  }

  input_parameters = length(keys(try(each.value.input_parameters, {}))) > 0 ? jsonencode(each.value.input_parameters) : null

  dynamic "scope" {
    for_each = try(each.value.scope, null) == null ? [] : [each.value.scope]
    content {
      compliance_resource_types = try(scope.value.compliance_resource_types, null)
      compliance_resource_id    = try(scope.value.compliance_resource_id, null)
      tag_key                   = try(scope.value.tag_key, null)
      tag_value                 = try(scope.value.tag_value, null)
    }
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# ------------------- Basic CloudWatch alarms -> SNS (signals from CloudTrail logs) -------------------
locals {
  cw_alarm_patterns = {
    unauthorized_api_calls = {
      pattern = <<-PATTERN
{ ($.errorCode = "*UnauthorizedOperation") || ($.errorCode = "AccessDenied*") }
PATTERN
      metric_name = "${var.name_prefix}-UnauthorizedAPICalls"
    }

    console_signin_without_mfa = {
      pattern = <<-PATTERN
{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") && ($.userIdentity.type != "AssumedRole") }
PATTERN
      metric_name = "${var.name_prefix}-ConsoleNoMFA"
    }
  }
}


resource "aws_cloudwatch_log_metric_filter" "trail" {
  for_each = (var.enable_cloudtrail && var.cloudtrail_enable_cw_logs) ? local.cw_alarm_patterns : {}

  name           = each.key
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.value.metric_name
    namespace = "Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "trail" {
  for_each = (var.enable_cloudtrail && var.cloudtrail_enable_cw_logs) ? local.cw_alarm_patterns : {}

  alarm_name          = "${var.name_prefix}-${each.key}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.trail[each.key].metric_transformation[0].name
  namespace           = "Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Security alarm from CloudTrail metric filter: ${each.key}"
  alarm_actions       = [aws_sns_topic.security.arn]
  treat_missing_data  = "notBreaching"
}
