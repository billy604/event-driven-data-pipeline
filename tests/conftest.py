import importlib.util
import pathlib

import pytest

SRC = pathlib.Path(__file__).resolve().parent.parent / "src"


@pytest.fixture(autouse=True)
def aws_env(monkeypatch):
    """Runs before EVERY test. Guarantees tests can never touch a real AWS account."""
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.delenv("AWS_PROFILE", raising=False)  # ignore your real SSO/profile
    # Environment variables the starter handler reads at import time
    monkeypatch.setenv("CLAIMS_TABLE", "test-claims")
    monkeypatch.setenv(
        "STATE_MACHINE_ARN", "arn:aws:states:us-east-1:123456789012:stateMachine:test"
    )


@pytest.fixture
def load_handler():
    """Returns a function that loads src/<name>/handler.py under a unique module name."""

    def _load(name: str):
        path = SRC / name / "handler.py"
        spec = importlib.util.spec_from_file_location(f"{name}_handler", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    return _load