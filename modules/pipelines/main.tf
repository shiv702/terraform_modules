locals {
  artifact_bucket_name = lower(replace("${var.name_prefix}-${var.aws_account_id}-codepipeline-artifacts", "_", "-"))
  state_bucket_name    = lower(replace("${var.name_prefix}-${var.aws_account_id}-tfstate", "_", "-"))
  lock_table_name      = "${var.name_prefix}-tfstate-lock"
  repo_name            = "${var.name_prefix}-foundation-iac"
}

data "aws_partition" "current" {}

# S3 bucket for pipeline artifacts
resource "aws_s3_bucket" "artifacts" {
  bucket        = local.artifact_bucket_name
  force_destroy = false
  tags          = merge(var.tags, { Name = local.artifact_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

# Terraform remote state bucket + DynamoDB lock table (used by CodeBuild)
resource "aws_s3_bucket" "tfstate" {
  bucket        = local.state_bucket_name
  force_destroy = false
  tags          = merge(var.tags, { Name = local.state_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_dynamodb_table" "lock" {
  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(var.tags, { Name = local.lock_table_name })
}

# ---------- Shared CodeCommit repo ----------
resource "aws_codecommit_repository" "repo" {
  repository_name = local.repo_name
  description     = "Shared Terraform IaC repo (Audit + Networking pipelines)"
  tags            = merge(var.tags, { Name = local.repo_name })
}

# ---------- IAM roles ----------
data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service", identifiers = ["codepipeline.amazonaws.com"] }
  }
}

resource "aws_iam_role" "codepipeline" {
  for_each           = var.pipeline_defs
  name               = "${var.name_prefix}-${each.key}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service", identifiers = ["codebuild.amazonaws.com"] }
  }
}

resource "aws_iam_role" "codebuild" {
  for_each           = var.pipeline_defs
  name               = "${var.name_prefix}-${each.key}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codebuild_policy" {
  for_each = var.pipeline_defs

  statement {
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }

  statement {
    actions = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*"
    ]
  }

  statement {
    actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:UpdateItem", "dynamodb:DescribeTable"]
    resources = [aws_dynamodb_table.lock.arn]
  }

  # Quick-start permissions: allow Terraform to manage resources in this account.
  # Tighten this for production.
  statement {
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  for_each = var.pipeline_defs
  name     = "${var.name_prefix}-${each.key}-codebuild-inline"
  role     = aws_iam_role.codebuild[each.key].id
  policy   = data.aws_iam_policy_document.codebuild_policy[each.key].json
}

data "aws_iam_policy_document" "codepipeline_policy" {
  for_each = var.pipeline_defs

  statement {
    actions = ["s3:GetObject","s3:GetObjectVersion","s3:PutObject","s3:ListBucket"]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }

  statement {
    actions = [
      "codecommit:GetBranch","codecommit:GetCommit","codecommit:UploadArchive",
      "codecommit:GetUploadArchiveStatus","codecommit:CancelUploadArchive"
    ]
    resources = [aws_codecommit_repository.repo.arn]
  }

  statement {
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  for_each = var.pipeline_defs
  name     = "${var.name_prefix}-${each.key}-codepipeline-inline"
  role     = aws_iam_role.codepipeline[each.key].id
  policy   = data.aws_iam_policy_document.codepipeline_policy[each.key].json
}

# ---------- CodeBuild projects ----------
locals {
  buildspec_plan = <<YAML
version: 0.2
phases:
  install:
    commands:
      - echo "Installing Terraform..."
      - TF_VERSION="1.12.2"
      - curl -sSLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip
      - unzip -o /tmp/terraform.zip -d /usr/local/bin
      - terraform -version
  pre_build:
    commands:
      - cd ${TF_WORKING_DIR}
      - terraform init -input=false -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" -backend-config="region=${AWS_REGION}" -backend-config="dynamodb_table=${TF_LOCK_TABLE}"
  build:
    commands:
      - terraform validate
      - terraform plan -input=false ${TF_TARGET_ARGS}
YAML

  buildspec_apply = <<YAML
version: 0.2
phases:
  install:
    commands:
      - echo "Installing Terraform..."
      - TF_VERSION="1.12.2"
      - curl -sSLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip
      - unzip -o /tmp/terraform.zip -d /usr/local/bin
      - terraform -version
  pre_build:
    commands:
      - cd ${TF_WORKING_DIR}
      - terraform init -input=false -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" -backend-config="region=${AWS_REGION}" -backend-config="dynamodb_table=${TF_LOCK_TABLE}"
  build:
    commands:
      - terraform validate
      - terraform plan -input=false -out=tfplan ${TF_TARGET_ARGS}
      - terraform apply -input=false -auto-approve tfplan
YAML
}

resource "aws_codebuild_project" "plan" {
  for_each = var.pipeline_defs

  name         = "${var.name_prefix}-${each.key}-tf-plan"
  service_role = aws_iam_role.codebuild[each.key].arn

  artifacts { type = "CODEPIPELINE" }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable { name = "TF_WORKING_DIR", value = each.value.working_dir }
    environment_variable { name = "TF_STATE_BUCKET", value = aws_s3_bucket.tfstate.bucket }
    environment_variable { name = "TF_LOCK_TABLE", value = aws_dynamodb_table.lock.name }
    environment_variable { name = "TF_STATE_KEY", value = "${each.key}/terraform.tfstate" }

    environment_variable {
      name  = "TF_TARGET_ARGS"
      value = join(" ", [for t in each.value.tf_targets : "-target=${t}"])
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = local.buildspec_plan
  }

  tags = var.tags
}

resource "aws_codebuild_project" "apply" {
  for_each = var.pipeline_defs

  name         = "${var.name_prefix}-${each.key}-tf-apply"
  service_role = aws_iam_role.codebuild[each.key].arn

  artifacts { type = "CODEPIPELINE" }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable { name = "TF_WORKING_DIR", value = each.value.working_dir }
    environment_variable { name = "TF_STATE_BUCKET", value = aws_s3_bucket.tfstate.bucket }
    environment_variable { name = "TF_LOCK_TABLE", value = aws_dynamodb_table.lock.name }
    environment_variable { name = "TF_STATE_KEY", value = "${each.key}/terraform.tfstate" }

    environment_variable {
      name  = "TF_TARGET_ARGS"
      value = join(" ", [for t in each.value.tf_targets : "-target=${t}"])
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = local.buildspec_apply
  }

  tags = var.tags
}

# ---------- CodePipelines ----------
resource "aws_codepipeline" "this" {
  for_each = var.pipeline_defs

  name     = "${var.name_prefix}-${each.key}-pipeline"
  role_arn = aws_iam_role.codepipeline[each.key].arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        RepositoryName        = aws_codecommit_repository.repo.repository_name
        BranchName            = var.branch
        PollForSourceChanges  = "false"
      }
    }
  }

  stage {
    name = "Plan"
    action {
      name            = "TerraformPlan"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]
      configuration = {
        ProjectName = aws_codebuild_project.plan[each.key].name
      }
    }
  }

  stage {
    name = "Approve"
    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
    }
  }

  stage {
    name = "Apply"
    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]
      configuration = {
        ProjectName = aws_codebuild_project.apply[each.key].name
      }
    }
  }

  tags = var.tags
}
