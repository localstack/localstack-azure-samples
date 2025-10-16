# Minimal HTTP-triggered function without azure.functions dependency.
# Returns plain text so it works in both Azure and LocalStack without needing the
# 'azure-functions' package during local build/publish.

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

    # Returning a string lets the runtime create a 200 OK text/plain response.
    return f"hello {name}"
