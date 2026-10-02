# ---------- Trust policies: WHO may assume the roles ----------
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "sfn_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

# ---------- Starter Lambda ----------
resource "aws_iam_role" "starter" {
  name               = "${var.project}-starter"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

data "aws_iam_policy_document" "starter" {
  # The Lambda service polls SQS *using this role* (event source mapping)
  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.ingest.arn]
  }
  # Claim a file, or release the claim if starting the workflow fails
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.claims.arn]
  }
  # Start THIS workflow only
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.pipeline.arn]
  }
  # Write to its own log group only (we create the group ourselves, with retention)
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.starter.arn}:*"]
  }
}

resource "aws_iam_role_policy" "starter" {
  name   = "starter-permissions"
  role   = aws_iam_role.starter.id
  policy = data.aws_iam_policy_document.starter.json
}

# ---------- Validator Lambda ----------
resource "aws_iam_role" "validator" {
  name               = "${var.project}-validator"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

data "aws_iam_policy_document" "validator" {
  # Read the file, and delete it after quarantining (S3 has no "move")
  statement {
    actions   = ["s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.data.arn}/incoming/*"]
  }
  # Write ONLY to rejected/. It cannot touch processed/.
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data.arn}/rejected/*"]
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.validator.arn}:*"]
  }
}

resource "aws_iam_role_policy" "validator" {
  name   = "validator-permissions"
  role   = aws_iam_role.validator.id
  policy = data.aws_iam_policy_document.validator.json
}

# ---------- Transformer Lambda ----------
resource "aws_iam_role" "transformer" {
  name               = "${var.project}-transformer"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

data "aws_iam_policy_document" "transformer" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data.arn}/incoming/*"]
  }
  # Write ONLY to processed/. It cannot write back to incoming/ (no trigger loop possible).
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data.arn}/processed/*"]
  }
  # Bucket-level action, so it uses the BUCKET ARN plus a prefix condition.
  # Without it, a missing object returns 403 instead of 404, which is confusing to debug.
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["incoming/*", "processed/*"]
    }
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.transformer.arn}:*"]
  }
}

resource "aws_iam_role_policy" "transformer" {
  name   = "transformer-permissions"
  role   = aws_iam_role.transformer.id
  policy = data.aws_iam_policy_document.transformer.json
}

# ---------- Step Functions state machine ----------
resource "aws_iam_role" "sfn" {
  name               = "${var.project}-sfn"
  assume_role_policy = data.aws_iam_policy_document.sfn_trust.json
}

data "aws_iam_policy_document" "sfn" {
  statement {
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.validator.arn,
      aws_lambda_function.transformer.arn,
    ]
  }
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
  # AWS log-delivery APIs do not support resource-level permissions, so "*" is
  # unavoidable here. This is a documented AWS limitation, not laziness.
  statement {
    actions = [
      "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies", "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sfn" {
  name   = "sfn-permissions"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn.json
}