import os

import awswrangler as wr  # from the AWS-managed "AWSSDKPandas" Lambda layer
import pandas as pd

OUT_BUCKET = os.environ["BUCKET"]


def handler(event, context):
    bucket, key = event["bucket"], event["key"]
    df = wr.s3.read_csv(f"s3://{bucket}/{key}")

    df["order_date"] = pd.to_datetime(df["order_date"]).dt.strftime("%Y-%m-%d")
    df["total"] = df["quantity"] * df["unit_price"]
    df = df.drop_duplicates(subset=["order_id"])

    stem = key.split("/")[-1].removesuffix(".csv")
    written = []
    for day, part in df.groupby("order_date"):
        # Deterministic filename = reprocessing overwrites, never duplicates
        out = f"s3://{OUT_BUCKET}/processed/orders/order_date={day}/{stem}.parquet"
        wr.s3.to_parquet(df=part.drop(columns=["order_date"]), path=out)
        written.append(out)
    return {"rows": len(df), "files": written, "key": key}