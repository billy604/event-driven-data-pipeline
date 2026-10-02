import json

import boto3
import pytest
from moto import mock_aws


class FakeStepFunctions:
    """Hand-written stand-in for the boto3 Step Functions client."""

    class exceptions:
        class ExecutionAlreadyExists(Exception):
            pass

    def __init__(self):
        self.started = []
        self.should_fail = False

    def start_execution(self, **kwargs):
        if self.should_fail:
            raise RuntimeError("Step Functions is down")
        self.started.append(kwargs)


def make_event(key="incoming/good_orders.csv", etag="etag-1", message_id="msg-1"):
    """Builds an SQS event whose body is an S3 notification (a JSON string inside JSON)."""
    s3_event = {
        "Records": [
            {"s3": {"bucket": {"name": "test-bucket"}, "object": {"key": key, "eTag": etag}}}
        ]
    }
    return {"Records": [{"messageId": message_id, "body": json.dumps(s3_event)}]}


@pytest.fixture
def starter(load_handler):
    with mock_aws():
        boto3.client("dynamodb").create_table(
            TableName="test-claims",
            KeySchema=[{"AttributeName": "file_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "file_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        module = load_handler("starter")  # loaded INSIDE the mock
        module.sfn = FakeStepFunctions()  # swap the real client for our fake
        yield module


def test_new_file_starts_one_execution(starter):
    result = starter.handler(make_event(), None)

    assert result == {"batchItemFailures": []}
    assert len(starter.sfn.started) == 1
    sent = json.loads(starter.sfn.started[0]["input"])
    assert sent == {"bucket": "test-bucket", "key": "incoming/good_orders.csv"}


def test_duplicate_delivery_is_skipped(starter):
    starter.handler(make_event(message_id="msg-1"), None)
    starter.handler(make_event(message_id="msg-2"), None)  # same file, delivered again

    assert len(starter.sfn.started) == 1


def test_changed_content_counts_as_a_new_file(starter):
    starter.handler(make_event(etag="v1"), None)
    starter.handler(make_event(etag="v2"), None)  # same name, corrected content

    assert len(starter.sfn.started) == 2


def test_url_encoded_keys_are_decoded(starter):
    starter.handler(make_event(key="incoming/my+orders.csv"), None)

    sent = json.loads(starter.sfn.started[0]["input"])
    assert sent["key"] == "incoming/my orders.csv"


def test_s3_test_event_is_ignored(starter):
    # S3 sends this once when you configure notifications. It has no "Records".
    event = {"Records": [{"messageId": "msg-1", "body": json.dumps({"Event": "s3:TestEvent"})}]}

    result = starter.handler(event, None)

    assert result == {"batchItemFailures": []}
    assert starter.sfn.started == []


def test_failed_start_releases_claim_so_retry_works(starter):
    """The 'claim leakage' bug: without the compensating release, the retry would be
    treated as a duplicate and the file would be silently lost."""
    starter.sfn.should_fail = True
    first = starter.handler(make_event(), None)
    assert first == {"batchItemFailures": [{"itemIdentifier": "msg-1"}]}

    starter.sfn.should_fail = False  # the outage ends; SQS redelivers the message
    retry = starter.handler(make_event(), None)

    assert retry == {"batchItemFailures": []}
    assert len(starter.sfn.started) == 1  # the file was NOT lost


def test_one_bad_message_does_not_fail_the_whole_batch(starter):
    good = make_event(message_id="good")["Records"][0]
    bad = {"messageId": "bad", "body": "this is not json"}

    result = starter.handler({"Records": [bad, good]}, None)

    assert result == {"batchItemFailures": [{"itemIdentifier": "bad"}]}
    assert len(starter.sfn.started) == 1  # the good one still went through