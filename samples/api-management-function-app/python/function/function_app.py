import hmac
import json
import os

import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# The header API Management adds from its secret named value. Nothing is answered without it, so
# the only way to this backend is through the gateway.
SECRET_HEADER = "X-Backend-Secret"

ITEMS = [
    {"id": 1, "sku": "APIM-001", "name": "Developer portal mug", "quantity": 42},
    {"id": 2, "sku": "APIM-002", "name": "Gateway sticker pack", "quantity": 500},
    {"id": 3, "sku": "APIM-003", "name": "Policy expression poster", "quantity": 7},
]


def json_response(body, status_code=200):
    return func.HttpResponse(
        json.dumps(body, indent=2), status_code=status_code, mimetype="application/json"
    )


def reject_without_secret(req):
    """401 unless the request carries the shared secret the gateway injects."""
    expected = os.environ.get("BACKEND_SECRET", "")
    supplied = req.headers.get(SECRET_HEADER, "")
    # Encoded before comparing: compare_digest refuses str operands that are not ASCII-only, and a
    # client can put any bytes in the header, so comparing the strings turns an intended 401 into an
    # unhandled 500.
    if expected and hmac.compare_digest(supplied.encode("utf-8"), expected.encode("utf-8")):
        return None
    return json_response(
        {
            "error": f"Missing or invalid {SECRET_HEADER} header. "
            "Call this API through API Management."
        },
        status_code=401,
    )


@app.route(route="items", methods=["GET"])
def list_items(req: func.HttpRequest) -> func.HttpResponse:
    rejected = reject_without_secret(req)
    if rejected is not None:
        return rejected
    return json_response({"items": ITEMS, "count": len(ITEMS)})


@app.route(route="items/{id}", methods=["GET"])
def get_item(req: func.HttpRequest) -> func.HttpResponse:
    rejected = reject_without_secret(req)
    if rejected is not None:
        return rejected
    wanted = req.route_params.get("id")
    for item in ITEMS:
        if str(item["id"]) == wanted:
            return json_response(item)
    return json_response({"error": f"No item with id {wanted}"}, status_code=404)


@app.route(route="whoami", methods=["GET"])
def whoami(req: func.HttpRequest) -> func.HttpResponse:
    """Echo the request as the backend received it, so the gateway's policies can be seen at work."""
    rejected = reject_without_secret(req)
    if rejected is not None:
        return rejected
    headers = {
        name.lower(): value
        for name, value in req.headers.items()
        # The secret itself is never echoed back.
        if name.lower() != SECRET_HEADER.lower()
    }
    return json_response(
        {
            "method": req.method,
            "url": req.url,
            "backend": os.environ.get("WEBSITE_HOSTNAME", "unknown"),
            "backend_secret_received": True,
            "headers": headers,
        }
    )
