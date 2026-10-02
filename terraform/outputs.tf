output "bucket_name" {
  value       = aws_s3_bucket.data.bucket
  description = "Upload CSVs to s3://<this>/incoming/"
}

output "ingest_queue_url" {
  value = aws_sqs_queue.ingest.url
}

output "dlq_arn" {
  value       = aws_sqs_queue.dlq.arn
  description = "Source ARN for DLQ redrive"
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}

output "athena_workgroup" {
  value = aws_athena_workgroup.pipeline.name
}

output "glue_database" {
  value = aws_glue_catalog_database.orders.name
}