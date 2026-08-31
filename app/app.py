from flask import Flask

app = Flask(__name__)


@app.route("/")
def home():
    return {
        "message": "Hello from a Docker container running on AWS ECS!",
        "status": "healthy"
    }


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
