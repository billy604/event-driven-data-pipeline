resource "aws_s3_bucket" "data" {
  bucket = "${var.project}-${data.aws_caller_identity.me.account_id}"
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    id     = "expire-incoming"
    status = "Enabled"
    filter { prefix = "incoming/" }
    expiration { days = 7 }
  }
  rule {
    id     = "expire-processed"
    status = "Enabled"
    filter { prefix = "processed/" }
    expiration { days = 30 }
  }
}

resource "aws_s3_bucket_notification" "data" {
  bucket = aws_s3_bucket.data.id
  queue {
    queue_arn     = aws_sqs_queue.ingest.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "incoming/"
    filter_suffix = ".csv"
  }
  depends_on = [aws_sqs_queue_policy.ingest]
}