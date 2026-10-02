import csv
import io

import boto3

s3 = boto3.client("s3")
REQUIRED = ["order_id", "customer_id", "product", "quantity", "unit_price", "order_date"]


def handler(event, context):
    bucket, key = event["bucket"], event["key"]
    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")
    reader = csv.DictReader(io.StringIO(body))

    errors = []
    if reader.fieldnames is None or any(c not in reader.fieldnames for c in REQUIRED):
        errors.append(f"Missing columns. Found: {reader.fieldnames}")
    else:
        for line_no, row in enumerate(reader, start=2):  # line 1 is the header
            if None in row or None in row.values():
                # Too many or too few fields: the transformer's parser would crash on this
                errors.append(f"Line {line_no}: wrong number of fields")
            else:
                try:
                    int(row["quantity"])
                    float(row["unit_price"])
                except (ValueError, TypeError):
                    errors.append(f"Line {line_no}: bad numeric value")
            if len(errors) >= 10:  # stop early; we don't need every error
                break

    if errors:  # expected business failure: quarantine, don't raise
        rejected_key = key.replace("incoming/", "rejected/", 1)
        s3.copy_object(Bucket=bucket, Key=rejected_key,
                       CopySource={"Bucket": bucket, "Key": key})
        s3.delete_object(Bucket=bucket, Key=key)
        return {"valid": False, "bucket": bucket, "key": key,
                "rejected_key": rejected_key, "errors": errors}

    return {"valid": True, "bucket": bucket, "key": key}