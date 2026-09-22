# Northstar edge-proxy — fetches vendor pricing feeds on behalf of the storefront.
# Internet-facing: mounted behind the public API gateway at /proxy/vendor-feed.
#
# This file is the M15 fixture for planted-finding shape #2: a MEDIUM-CVSS CVE
# (CVE-2023-32681, requests 2.19.1) on a path the app genuinely reaches. `requests`
# is imported and called from the function that handles the public route below —
# see reachability-check evidence in platform/secfixtures/ground-truth.md.
import requests
from fastapi import FastAPI, Query

app = FastAPI()


@app.get("/proxy/vendor-feed")
def fetch_vendor_feed(url: str = Query(..., description="vendor feed URL, storefront-supplied")):
    """Public route: the storefront passes a vendor URL and we fetch it server-side."""
    resp = requests.get(url, timeout=5)
    return {"status": resp.status_code, "body": resp.text[:2048]}
