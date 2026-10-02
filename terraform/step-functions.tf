resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/vendedlogs/states/${var.project}"
  retention_in_days = 7
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project}-pipeline"
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"

  # templatefile() reads the JSON file and swaps ${VALIDATOR_ARN} etc. for real values
  definition = templatefile("${path.module}/../state-machine/pipeline.asl.json", {
    VALIDATOR_ARN   = aws_lambda_function.validator.arn
    TRANSFORMER_ARN = aws_lambda_function.transformer.arn
    TOPIC_ARN       = aws_sns_topic.alerts.arn
  })

  logging_configuration {
    level                  = "ERROR"
    include_execution_data = false
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
  }
}