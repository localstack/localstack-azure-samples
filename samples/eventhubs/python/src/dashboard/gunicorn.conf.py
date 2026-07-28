"""Gunicorn configuration for the operations dashboard.

The dashboard polls Event Hubs and Blob Storage on every refresh, so a single worker with
a few threads is the right shape: the work is I/O bound and the state is per-request.
"""

import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8000')}"
workers = 1
threads = 4
timeout = 120
accesslog = "-"
errorlog = "-"
loglevel = "info"
