import requests, urllib3, sys

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

FQDN = "auto-a.site-a.vcf.lab"
BASE = f"https://{FQDN}"

if len(sys.argv) != 4:
    print("Usage: vcfa-token.py <username> <password> <org>", file=sys.stderr)
    sys.exit(1)

USER, PASS, TENANT = sys.argv[1], sys.argv[2], sys.argv[3]

s = requests.Session()
s.verify = False

r = s.post(f"{BASE}/cloudapi/1.0.0/sessions", auth=(f"{USER}@{TENANT}", PASS),
           headers={"Accept": "application/json;version=40.0"})
jwt = r.headers.get("x-vmware-vcloud-access-token")
if not jwt:
    print(f"Login failed: {r.status_code} {r.text}", file=sys.stderr)
    sys.exit(1)

rr = s.post(f"{BASE}/oauth/tenant/{TENANT}/register",
            json={"client_name": "lab-setup"},
            headers={"Authorization": f"Bearer {jwt}", "Content-Type": "application/json",
                     "Accept": "application/json;version=40.0"})
if rr.status_code not in [200, 201]:
    print(f"Registration failed: {rr.text}", file=sys.stderr)
    sys.exit(1)

cid = rr.json()["client_id"]

tr = s.post(f"{BASE}/oauth/tenant/{TENANT}/token",
            data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                  "assertion": jwt, "client_id": cid, "scope": "openid offline_access"},
            headers={"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"})
if tr.status_code == 200:
    print(tr.json()["refresh_token"])
else:
    print(f"Token exchange failed: {tr.status_code} {tr.text}", file=sys.stderr)
    sys.exit(1)
