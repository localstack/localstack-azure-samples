"""
Minimal HTTP-triggered function without azure.functions dependency.
Returns plain text so it works in both Azure and LocalStack without needing the
'azure-functions' package during local build/publish.

Enhancements for demos:
- Echoes the WEBSITE_HOSTNAME so multi-origin routing can be observed easily.
- If header 'x-echo' is present in the request, it is echoed back in the body.
"""

import os


def main(req):
    # Try to read the {name} from route params first
    name = None
    try:
        if hasattr(req, 'route_params') and req.route_params:
            name = req.route_params.get('name')
    except Exception:
        name = None

    # Fallback to query string (?name=foo)
    if not name:
        try:
            if hasattr(req, 'params') and req.params:
                name = req.params.get('name')
        except Exception:
            name = None

    if not name:
        name = 'world'

    # Detect which host/app served the request to distinguish origins
    host = os.environ.get('WEBSITE_HOSTNAME') or 'unknown-host'

    # Optionally echo a header for debugging
    echoed = None
    try:
        if hasattr(req, 'headers') and req.headers:
            echoed = req.headers.get('x-echo') or req.headers.get('X-Echo')
    except Exception:
        echoed = None

    body = f"hello {name} from {host}"
    if echoed:
        body += f" (echoed-header={echoed})"

    # Returning a string lets the runtime create a 200 OK text/plain response.
    return body
