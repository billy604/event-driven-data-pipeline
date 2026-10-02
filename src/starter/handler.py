import hashlib
import json
import os
import time
import urllib.parse

import boto3
from botocore.exceptions import ClientError

ddb = boto3.client("dynamodb")
sfn = boto3.client("stepfunctions")

TABLE = os.environ["CLAIMS_TABLE"]
STATE_MACHINE = os.environ["STATE_MACHINE_ARN"]


def claim(file_id: str) -> bool:
    """Atomically claim a file. Returns False if someone already did."""
    try:
        ddb.put_item(
            TableName=TABLE,
            Item={
                "file_id": {"S": file_id},
                "expires_at": {"N": str(int(time.time()) + 7 * 86400)},
            },
            ConditionExpression="attribute_not_exists(file_id)",
        )
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return False
        raise


def release(file_id: str) -> None:
    """Undo a claim so a retry can try again."""
    ddb.delete_item(TableName=TABLE, Key={"file_id": {"S": file_id}})


def handler(event, context):
    failures = []

    for record in event["Records"]:
        try:
            body = json.loads(record["body"])  # body is a JSON *string*

            # S3's one-time "s3:TestEvent" has no "Records", so it falls through harmlessly
            for s3rec in body.get("Records", []):
                bucket = s3rec["s3"]["bucket"]["name"]
                # Keys arrive URL-encoded ("my file.csv" -> "my+file.csv")
                key = urllib.parse.unquote_plus(s3rec["s3"]["object"]["key"])
                etag = s3rec["s3"]["object"].get("eTag", "")

                # ETag changes with content, so a corrected re-upload is a new file
                file_id = f"{bucket}/{key}#{etag}"

                if not claim(file_id):
                    print(f"Duplicate, skipping: {file_id}")
                    continue

                try:
                    sfn.start_execution(
                        stateMachineArn=STATE_MACHINE,
                        name=hashlib.sha256(file_id.encode()).hexdigest(),
                        input=json.dumps({"bucket": bucket, "key": key}),
                    )
                except sfn.exceptions.ExecutionAlreadyExists:
                    print(f"Execution already exists, skipping: {file_id}")
                except Exception:
                    release(file_id)  # compensating action: undo the claim
                    raise

        except Exception as exc:  # noqa: BLE001 - deliberate catch-all: report the failure to SQS for retry
            print(f"Failed {record['messageId']}: {exc}")
            failures.append({"itemIdentifier": record["messageId"]})

    return {"batchItemFailures": failures}