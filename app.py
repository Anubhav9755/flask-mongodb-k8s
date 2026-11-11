import logging
import os
from datetime import datetime

from flask import Flask, request, jsonify
from pymongo import MongoClient
from pymongo.errors import PyMongoError

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("flask-app")

app = Flask(__name__)


def connect():
    uri = os.environ.get("MONGODB_URI")
    if uri:
        return MongoClient(uri, serverSelectionTimeoutMS=2000)

    host = os.environ.get("MONGO_HOST", "localhost")
    port = int(os.environ.get("MONGO_PORT", "27017"))
    user = os.environ.get("MONGO_USERNAME")
    password = os.environ.get("MONGO_PASSWORD")

    if user and password:
        return MongoClient(
            host=host,
            port=port,
            username=user,
            password=password,
            authSource="admin",
            serverSelectionTimeoutMS=2000,
        )
    return MongoClient(host=host, port=port, serverSelectionTimeoutMS=2000)


client = connect()
db = client[os.environ.get("MONGO_DB", "flask_db")]
collection = db.data


@app.route("/")
def index():
    return f"Welcome to the Flask app! The current time is: {datetime.now()}"


@app.route("/data", methods=["GET", "POST"])
def data():
    try:
        if request.method == "POST":
            body = request.get_json(silent=True)
            if not isinstance(body, dict):
                return jsonify({"error": "Request body must be a JSON object"}), 400
            collection.insert_one(body)
            return jsonify({"status": "Data inserted"}), 201

        docs = list(collection.find({}, {"_id": 0}))
        return jsonify(docs), 200
    except PyMongoError as exc:
        log.error("database error: %s", exc)
        return jsonify({"error": "Database error"}), 503


@app.route("/healthz")
def healthz():
    return jsonify({"status": "ok"}), 200


@app.route("/ready")
def ready():
    try:
        client.admin.command("ping")
        return jsonify({"status": "ready"}), 200
    except PyMongoError:
        return jsonify({"status": "mongodb not reachable"}), 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
