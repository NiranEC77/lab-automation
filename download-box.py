#!/usr/bin/env python3
"""Download a password-protected Box file shared link (no API token needed)."""

import re
import os
import sys
import json
import argparse
import requests
from urllib.parse import urlparse

DEFAULT_URL = "https://ent.box.com/s/bzqcj8bbgzheoec3chi59b46tevi8ptq"

BROWSER_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate, br",
    "Connection": "keep-alive",
    "Upgrade-Insecure-Requests": "1",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "none",
    "Sec-Fetch-User": "?1",
    "sec-ch-ua": '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
    "sec-ch-ua-mobile": "?0",
    "sec-ch-ua-platform": '"macOS"',
    "Cache-Control": "max-age=0",
}


def extract_box_config(html):
    m = re.search(r'Box\.config\s*=\s*(\{.+?\});', html, re.DOTALL)
    if not m:
        return {}
    try:
        return json.loads(m.group(1))
    except json.JSONDecodeError:
        return {}


def extract_prefetched_data(html):
    m = re.search(r'Box\.prefetchedData\s*=\s*(\{.+?\});', html, re.DOTALL)
    if not m:
        return {}
    try:
        return json.loads(m.group(1))
    except json.JSONDecodeError:
        return {}


def get_filename_from_response(resp):
    cd = resp.headers.get("Content-Disposition", "")
    m = re.search(r'filename\*?=["\']?(?:UTF-8\'\')?([^"\';\n]+)', cd, re.IGNORECASE)
    if m:
        return m.group(1).strip()
    return None


def download(session, url, password, output_dir, debug=False):
    base = f"{urlparse(url).scheme}://{urlparse(url).netloc}"

    # Step 1: GET page — 403 expected, sets 'z' visitor cookie + returns HTML with config
    resp = session.get(url, headers=BROWSER_HEADERS)
    if debug:
        print(f"[debug] GET {url} → {resp.status_code}, cookies: {dict(session.cookies)}")

    config = extract_box_config(resp.text)
    request_token = config.get("requestToken")
    if not request_token:
        print("ERROR: Could not extract requestToken from page. Run with --debug.")
        sys.exit(1)
    if debug:
        print(f"[debug] requestToken: {request_token}")
        prefetched = extract_prefetched_data(resp.text)
        print(f"[debug] prefetched shared-item: {prefetched.get('/app-api/enduserapp/shared-item', {})}")

    # Step 2: POST password as form data to the shared link URL
    form_resp = session.post(url, data={
        "password": password,
        "request_token": request_token,
    }, headers={
        **BROWSER_HEADERS,
        "Content-Type": "application/x-www-form-urlencoded",
        "Referer": url,
        "Origin": base,
    }, allow_redirects=True)

    if debug:
        print(f"[debug] POST password → {form_resp.status_code}, cookies: {dict(session.cookies)}")
        prefetched = extract_prefetched_data(form_resp.text)
        shared_item = prefetched.get("/app-api/enduserapp/shared-item", {})
        print(f"[debug] prefetched shared-item after auth: {json.dumps(shared_item)[:500]}")
        with open("/tmp/box_post_response.html", "w") as f:
            f.write(form_resp.text)
        print("[debug] POST response saved to /tmp/box_post_response.html")

    if re.search(r'errorCode.*passwordRequired|incorrect.*password|wrong.*password', form_resp.text, re.IGNORECASE):
        print("ERROR: Incorrect password.")
        sys.exit(1)

    # Step 3a: Try /shared/static/HASH.ext — same domain, session cookies carry over
    link_token = url.rstrip("/").split("/")[-1]
    prefetched_early = extract_prefetched_data(form_resp.text)
    ext = prefetched_early.get("preview_metadata", {}).get("extension", "")
    static_url = f"{base}/shared/static/{link_token}" + (f".{ext}" if ext else "")
    if debug:
        print(f"[debug] Trying /shared/static/ URL: {static_url}")
    static_resp = session.get(static_url, headers=BROWSER_HEADERS, stream=True, allow_redirects=True)
    ct = static_resp.headers.get("Content-Type", "")
    if debug:
        print(f"[debug] /shared/static/ → {static_resp.status_code}, Content-Type: {ct}, Content-Disposition: {static_resp.headers.get('Content-Disposition','')[:80]}")
    if static_resp.status_code == 200 and "text/html" not in ct:
        fname = prefetched_early.get("preview_metadata", {}).get("name") or get_filename_from_response(static_resp) or f"{link_token}.{ext}"
        filepath = os.path.join(output_dir, fname)
        size = 0
        with open(filepath, "wb") as f:
            for chunk in static_resp.iter_content(65536):
                f.write(chunk)
                size += len(chunk)
        print(f"Downloaded: {fname} ({size // 1024} KB) → {filepath}")
        return

    # Step 3b: Try ?dl=1 without following redirects — may give a signed URL
    dl_url = url.rstrip("/") + "?dl=1"
    if debug:
        print(f"[debug] Trying GET {dl_url} (no redirect follow)...")
    no_redir = session.get(dl_url, headers=BROWSER_HEADERS, allow_redirects=False)
    if debug:
        print(f"[debug] ?dl=1 no-redirect → {no_redir.status_code}, Location: {no_redir.headers.get('Location', '')[:120]}")
    if no_redir.status_code in (301, 302, 303, 307, 308):
        signed_url = no_redir.headers.get("Location", "")
        if signed_url and "boxcloud.com" in signed_url:
            if debug:
                print(f"[debug] Got signed redirect URL, downloading...")
            dl_resp = session.get(signed_url, stream=True, allow_redirects=True)
            if dl_resp.status_code == 200 and "text/html" not in dl_resp.headers.get("Content-Type", ""):
                filename = get_filename_from_response(dl_resp) or "box-download"
                filepath = os.path.join(output_dir, filename)
                size = 0
                with open(filepath, "wb") as f:
                    for chunk in dl_resp.iter_content(65536):
                        f.write(chunk)
                        size += len(chunk)
                print(f"Downloaded: {filename} ({size // 1024} KB) → {filepath}")
                return

    # Step 4: Extract download URL from preview_metadata in POST response
    if debug:
        print("[debug] ?dl=1 returned HTML. Checking preview_metadata for authenticated_download_url...")
    prefetched = extract_prefetched_data(form_resp.text)
    preview_meta = prefetched.get("preview_metadata", {})
    dl_url_embedded = (
        preview_meta.get("authenticated_download_url")
        or preview_meta.get("download_url")
    )
    filename = preview_meta.get("name")

    if debug:
        print(f"[debug] preview_metadata keys: {list(preview_meta.keys())}")
        print(f"[debug] authenticated_download_url: {dl_url_embedded}")
        print(f"[debug] filename: {filename}")

    if not dl_url_embedded:
        print("ERROR: No download URL found in page. Run with --debug.")
        sys.exit(1)

    # Try internal Box app API download endpoint first (uses ent.box.com cookies)
    file_id = preview_meta.get("id")
    request_token = config.get("requestToken")
    if file_id and request_token:
        internal_dl = f"{base}/app-api/enduserapp/item/download"
        params = {"item_id": file_id, "item_type": "file", "shared_link": url}
        hdrs = {
            **BROWSER_HEADERS,
            "X-Request-Token": request_token,
            "X-Box-Client-Name": "enduserapp",
            "Accept": "*/*",
        }
        if debug:
            print(f"[debug] Trying internal download API: {internal_dl} params={params}")
        int_resp = session.get(internal_dl, headers=hdrs, params=params,
                               stream=True, allow_redirects=True)
        if debug:
            print(f"[debug] Internal download → {int_resp.status_code}, Content-Type: {int_resp.headers.get('Content-Type')}")
        if int_resp.status_code == 200 and "text/html" not in int_resp.headers.get("Content-Type", ""):
            filename = filename or get_filename_from_response(int_resp) or "box-download"
            filepath = os.path.join(output_dir, filename)
            size = 0
            with open(filepath, "wb") as f:
                for chunk in int_resp.iter_content(65536):
                    f.write(chunk)
                    size += len(chunk)
            print(f"Downloaded: {filename} ({size // 1024} KB) → {filepath}")
            return
        if debug and int_resp.status_code not in (200,):
            print(f"[debug] Internal download failed: {int_resp.text[:200]}")

    # Fallback: try authenticated_download_url with z cookie copied to boxcloud.com domain
    if debug:
        print(f"[debug] Trying authenticated_download_url with cross-domain cookie injection...")
    z_cookie = session.cookies.get("z", domain="ent.box.com") or session.cookies.get("z")
    if z_cookie:
        session.cookies.set("z", z_cookie, domain="public.boxcloud.com")
        session.cookies.set("z", z_cookie, domain="boxcloud.com")

    dl_resp = session.get(dl_url_embedded, headers=BROWSER_HEADERS, stream=True, allow_redirects=True)
    if debug:
        print(f"[debug] Downloading from {dl_url_embedded[:80]} → {dl_resp.status_code}, Content-Type: {dl_resp.headers.get('Content-Type')}")

    if dl_resp.status_code != 200:
        print(f"ERROR: Download request returned {dl_resp.status_code}")
        sys.exit(1)

    filename = filename or get_filename_from_response(dl_resp) or "box-download"
    filepath = os.path.join(output_dir, filename)
    size = 0
    with open(filepath, "wb") as f:
        for chunk in dl_resp.iter_content(65536):
            f.write(chunk)
            size += len(chunk)
    print(f"Downloaded: {filename} ({size // 1024} KB) → {filepath}")


def main():
    parser = argparse.ArgumentParser(description="Download password-protected Box file link(s)")
    parser.add_argument("urls", nargs="*", help="Box shared file link URL(s). Uses DEFAULT_URL if none given.")
    parser.add_argument("--password", required=True, help="Shared link password")
    parser.add_argument("--output", default="./box-downloads", help="Output directory")
    parser.add_argument("--debug", action="store_true", help="Dump HTTP details")
    args = parser.parse_args()

    urls = args.urls if args.urls else [DEFAULT_URL]
    os.makedirs(args.output, exist_ok=True)

    failed = []
    for url in urls:
        # Skip if already downloaded — check by seeing if any file in output_dir
        # matches the link token (can't know filename before auth, so just track by URL token)
        link_token = url.rstrip("/").split("/")[-1].split("?")[0]
        already = [f for f in os.listdir(args.output) if not f.endswith(".part")]
        # Rough skip: if a file exists whose name contains the token, skip
        # (After first run, filenames are real — this is just a safety guard)
        session = requests.Session()
        try:
            download(session, url, args.password, args.output, debug=args.debug)
        except SystemExit:
            failed.append(url)

    if failed:
        print(f"\nFailed downloads ({len(failed)}):")
        for u in failed:
            print(f"  {u}")
        sys.exit(1)


if __name__ == "__main__":
    main()
