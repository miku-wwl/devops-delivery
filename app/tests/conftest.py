from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from demo_api.config import Settings
from demo_api.main import create_app


@pytest.fixture
def make_client():
    """Build a TestClient for an app created with custom settings."""

    def _make(**overrides) -> TestClient:
        return TestClient(create_app(Settings(**overrides)))

    return _make


@pytest.fixture
def client(make_client) -> TestClient:
    return make_client(version="1.2.3", commit="abc1234")
