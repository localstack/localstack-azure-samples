"""The origin behind Azure Front Door: a small catalog API plus a health endpoint.

Every response says which of the two Function Apps answered and what path the origin was asked
for, so the Front Door behaviours the sample demonstrates -- origin selection, route matching, URL
rewriting -- can be read straight off the body. The caching behaviour is the origin's to decide:
the catalog sets a ``Cache-Control`` Front Door can honour, everything else says ``no-store``.
"""

import json
import os
from urllib.parse import urlparse

import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

#: Which Function App this is, from an app setting the deployment script sets. The two apps are
#: identical apart from this value, which is what makes origin selection observable.
ORIGIN_NAME = os.environ.get("ORIGIN_NAME", "unknown")

CATALOG = {
    "1": {"sku": "AFD-001", "name": "Edge cache mug", "price": 12.5},
    "2": {"sku": "AFD-002", "name": "Origin group hoodie", "price": 48.0},
    "3": {"sku": "AFD-003", "name": "Rules engine notebook", "price": 7.25},
}

#: The headers Front Door adds on its way to the origin. Echoed by /whoami so a reader can see
#: what arrives at an origin that sits behind an edge.
FRONT_DOOR_HEADERS = (
    "host",
    "via",
    "x-azure-clientip",
    "x-azure-socketip",
    "x-azure-fdid",
    "x-azure-requestchain",
    "x-forwarded-for",
    "x-forwarded-host",
    "x-forwarded-proto",
)


def json_response(body: dict, status_code: int = 200, cache_control: str = "no-store"):
    return func.HttpResponse(
        json.dumps(body, indent=2),
        status_code=status_code,
        mimetype="application/json",
        headers={"Cache-Control": cache_control},
    )


def origin_path(req: func.HttpRequest) -> str:
    """The path this Function App was asked for, which is not always the one the client sent."""
    return urlparse(req.url).path


@app.route(route="health", methods=["GET", "HEAD"])
def health(req: func.HttpRequest) -> func.HttpResponse:
    """Front Door's health probe target.

    The probe is a HEAD request, so this route has to accept HEAD as well as GET: an origin that
    answers the probe with 405 is taken out of rotation and its route starts returning 503.
    """
    return json_response({"status": "healthy", "origin": ORIGIN_NAME})


@app.route(route="whoami", methods=["GET"])
def whoami(req: func.HttpRequest) -> func.HttpResponse:
    """What the origin received, including the headers Front Door added."""
    headers = {
        name: value for name, value in req.headers.items() if name.lower() in FRONT_DOOR_HEADERS
    }
    return json_response(
        {
            "origin": ORIGIN_NAME,
            "path": origin_path(req),
            "method": req.method,
            "front_door_headers": headers,
        }
    )


@app.route(route="status", methods=["GET"])
def status(req: func.HttpRequest) -> func.HttpResponse:
    """The target of the sample's second, more specific route."""
    return json_response({"origin": ORIGIN_NAME, "path": origin_path(req), "status": "ok"})


@app.route(route="catalog/{item}", methods=["GET"])
def catalog(req: func.HttpRequest) -> func.HttpResponse:
    """A cacheable response: Front Door stores it for as long as this ``Cache-Control`` allows."""
    wanted = req.route_params.get("item")
    item = CATALOG.get(wanted)
    if item is None:
        return json_response({"error": f"No catalog item {wanted}"}, status_code=404)
    return json_response(
        {"origin": ORIGIN_NAME, "path": origin_path(req), "item": item},
        cache_control="public, max-age=300",
    )
