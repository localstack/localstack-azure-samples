import os
import socket

from flask import Flask, jsonify, render_template


app = Flask(__name__)


@app.route("/")
def index():
    return render_template(
        "index.html",
        app_name=os.environ.get("APP_NAME", "Custom Image Web App"),
        image_name=os.environ.get("IMAGE_NAME", "vacation-planner-webapp:v1"),
        hostname=socket.gethostname(),
    )


@app.route("/api/status")
def status():
    return jsonify(
        {
            "status": "ok",
            "app": os.environ.get("APP_NAME", "Custom Image Web App"),
            "image": os.environ.get("IMAGE_NAME", "vacation-planner-webapp:v1"),
            "hostname": socket.gethostname(),
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "80")))
