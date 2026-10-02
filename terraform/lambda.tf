# ================= Starter =================
data "archive_file" "starter" {
  type        = "zip"
  source_dir  = "${path.module}/../src/starter"
  output_path = "${path.module}/build/starter.zip"
}

resource "aws_lambda_function" "starter" {
  function_name    = "${var.project}-starter"
  role             = aws_iam_role.starter.arn
  handler          = "handler.handler" # file handler.py, function named handler
  runtime          = "python3.12"
  architectures    = ["arm64"]
  timeout          = 30
  filename         = data.archive_file.starter.output_path
  source_code_hash = data.archive_file.starter.output_base64sha256

  environment {
    variables = {
      CLAIMS_TABLE      = aws_dynamodb_table.claims.name
      STATE_MACHINE_ARN = aws_sfn_state_machine.pipeline.arn
    }
  }

  # Create our log group (with retention) before the function can create its own
  depends_on = [aws_cloudwatch_log_group.starter]
}

resource "aws_cloudwatch_log_group" "starter" {
  name              = "/aws/lambda/${var.project}-starter"
  retention_in_days = 7
}

resource "aws_lambda_event_source_mapping" "starter" {
  event_source_arn        = aws_sqs_queue.ingest.arn
  function_name           = aws_lambda_function.starter.arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]

  # Lambda checks the role can read the queue when this is created
  depends_on = [aws_iam_role_policy.starter]
}

# ================= Validator =================
data "archive_file" "validator" {
  type        = "zip"
  source_dir  = "${path.module}/../src/validator"
  output_path = "${path.module}/build/validator.zip"
}

resource "aws_lambda_function" "validator" {
  function_name    = "${var.project}-validator"
  role             = aws_iam_role.validator.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.validator.output_path
  source_code_hash = data.archive_file.validator.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.validator]
}

resource "aws_cloudwatch_log_group" "validator" {
  name              = "/aws/lambda/${var.project}-validator"
  retention_in_days = 7
}

# ================= Transformer =================
data "archive_file" "transformer" {
  type        = "zip"
  source_dir  = "${path.module}/../src/transformer"
  output_path = "${path.module}/build/transformer.zip"
}

resource "aws_lambda_function" "transformer" {
  function_name    = "${var.project}-transformer"
  role             = aws_iam_role.transformer.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  timeout          = 60
  memory_size      = 512
  layers           = [var.pandas_layer_arn] # must be the arm64 build
  filename         = data.archive_file.transformer.output_path
  source_code_hash = data.archive_file.transformer.output_base64sha256

  environment {
    variables = {
      BUCKET = aws_s3_bucket.data.bucket
    }
  }

  depends_on = [aws_cloudwatch_log_group.transformer]
}

resource "aws_cloudwatch_log_group" "transformer" {
  name              = "/aws/lambda/${var.project}-transformer"
  retention_in_days = 7
}