resource "aws_glue_catalog_database" "orders" {
  name = replace("${var.project}_db", "-", "_") # Glue/Athena names prefer underscores
}

resource "aws_glue_catalog_table" "orders" {
  database_name = aws_glue_catalog_database.orders.name
  name          = "orders"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"               = "parquet"
    "projection.enabled"           = "true"
    "projection.order_date.type"   = "date"
    "projection.order_date.format" = "yyyy-MM-dd"
    "projection.order_date.range"  = "2025-01-01,NOW"
    # $${...} = literal ${...} for Athena (Terraform would otherwise interpolate it)
    "storage.location.template" = "s3://${aws_s3_bucket.data.bucket}/processed/orders/order_date=$${order_date}/"
  }

  # order_date comes from the FOLDER NAME, not from inside the Parquet file
  partition_keys {
    name = "order_date"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data.bucket}/processed/orders/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "order_id"
      type = "string"
    }
    columns {
      name = "customer_id"
      type = "string"
    }
    columns {
      name = "product"
      type = "string"
    }
    columns {
      name = "quantity"
      type = "int"
    }
    columns {
      name = "unit_price"
      type = "double"
    }
    columns {
      name = "total"
      type = "double"
    }
  }
}

resource "aws_athena_workgroup" "pipeline" {
  name          = "${var.project}-wg"
  force_destroy = true # DEMO ONLY: lets terraform destroy remove it even with query history

  configuration {
    enforce_workgroup_configuration = true
    bytes_scanned_cutoff_per_query  = 1073741824 # 1 GB hard cap per query

    result_configuration {
      output_location = "s3://${aws_s3_bucket.data.bucket}/athena-results/"
    }
  }
}