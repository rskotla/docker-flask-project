
from app import app


def test_homepage_returns_success():
    client = app.test_client()

    response = client.get("/")

    assert response.status_code == 200


def test_health_endpoint():
    client = app.test_client()

    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json()["status"] == "healthy"


def test_api_info_endpoint():
    client = app.test_client()

    response = client.get("/api/info")

    assert response.status_code == 200
    assert response.get_json()["application"] == "Docker Hands-On Demo"


def test_unknown_endpoint_returns_404():
    client = app.test_client()

    response = client.get("/does-not-exist")

    assert response.status_code == 404
