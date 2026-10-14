
from datetime import UTC, datetime

from flask import Flask, jsonify, render_template

app = Flask(__name__)


@app.route("/")
def home():
    return render_template("index.html")


@app.route("/health")
def health():
    return jsonify({
        "status": "healthy",
        "application": "docker-flask-project"
    }), 200


@app.route("/api/info")
def application_info():
    return jsonify({
        "application": "Docker Hands-On Demo",
        "version": "1.0.0",
        "environment": "Docker Lab",
        "message": "Application is running successfully!",
        "timestamp": datetime.now(UTC).isoformat()
    }), 200


@app.errorhandler(404)
def not_found(error):
    return jsonify({
        "error": "Not Found",
        "message": "The requested endpoint does not exist."
    }), 404


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
