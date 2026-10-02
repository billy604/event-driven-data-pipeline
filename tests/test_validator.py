import boto3
import pytest
from moto import mock_aws

BUCKET = "test-bucket"
HEADER = "order_id,customer_id,product,quantity,unit_price,order_date\n"


@pytest.fixture
def env(load_handler):
    with mock_aws():
        s3 = boto3.client("s3")
        s3.create_bucket(Bucket=BUCKET)
        yield load_handler("validator"), s3


def put(s3, key, body):
    s3.put_object(Bucket=BUCKET, Key=key, Body=body.encode())


def run(validator, key):
    return validator.handler({"bucket": BUCKET, "key": key}, None)


def test_valid_file_passes_and_stays_in_place(env):
    validator, s3 = env
    put(s3, "incoming/ok.csv", HEADER + "1001,C-17,Keyboard,2,25.50,2026-09-27\n")

    result = run(validator, "incoming/ok.csv")

    assert result["valid"] is True
    assert "Contents" in s3.list_objects_v2(Bucket=BUCKET, Prefix="incoming/")


def test_missing_column_is_quarantined_not_raised(env):
    validator, s3 = env
    body = "order_id,customer_id,product,quantity,order_date\n2001,C-40,Mouse,1,2026-09-28\n"
    put(s3, "incoming/bad.csv", body)

    result = run(validator, "incoming/bad.csv")  # must NOT raise: expected failure

    assert result["valid"] is False
    assert result["rejected_key"] == "rejected/bad.csv"
    assert "Contents" not in s3.list_objects_v2(Bucket=BUCKET, Prefix="incoming/")
    assert "Contents" in s3.list_objects_v2(Bucket=BUCKET, Prefix="rejected/")


def test_bad_number_reports_the_line(env):
    validator, s3 = env
    put(s3, "incoming/bad.csv", HEADER + "1,C-1,Pen,two,1.50,2026-09-27\n")

    result = run(validator, "incoming/bad.csv")

    assert result["valid"] is False
    assert result["errors"] == ["Line 2: bad numeric value"]


def test_stops_collecting_after_ten_errors(env):
    validator, s3 = env
    rows = "".join(f"{i},C-1,Pen,x,1.00,2026-09-27\n" for i in range(50))
    put(s3, "incoming/huge_bad.csv", HEADER + rows)

    result = run(validator, "incoming/huge_bad.csv")

    assert len(result["errors"]) == 10


def test_empty_file_is_rejected(env):
    validator, s3 = env
    put(s3, "incoming/empty.csv", "")

    result = run(validator, "incoming/empty.csv")

    assert result["valid"] is False

def test_row_with_extra_fields_is_rejected(env):
    validator, s3 = env
    # Last row has no newline before the next row's data, so it has 11 fields
    row = "1004,C-31,Webcam,1,59.00,2026-09-289101,C-99,LoadTest,1,1.00,2026-09-28\n"
    put(s3, "incoming/glued.csv", HEADER + row)

    result = run(validator, "incoming/glued.csv")

    assert result["valid"] is False
    assert result["errors"] == ["Line 2: wrong number of fields"]
    assert "Contents" in s3.list_objects_v2(Bucket=BUCKET, Prefix="rejected/")