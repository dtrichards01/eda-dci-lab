#!/usr/bin/env python3
"""Submit several CR operations as ONE EDA transaction (optionally dry-run).

Input: multi-document YAML. Each document is a full CR to create or replace, or a stub with
`x-op: delete` (apiVersion, kind, metadata.name, metadata.namespace) to delete.

  eda-txn.py ops.yaml [--commit] [--desc TEXT]

Default is dry-run. Needs kubectl access to eda-system (Keycloak secret) and the EDA API URL in EDA_URL.
Secrets and tokens are never printed.
"""
import argparse, base64, json, os, ssl, subprocess, sys, time, urllib.parse, urllib.request

EDA = os.environ.get("EDA_URL", "https://100.124.186.55")
KC = EDA + "/core/httpproxy/v1/keycloak"
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=CTX))


def http(method, url, data=None, token=None, form=False):
    headers = {}
    body = None
    if token:
        headers["Authorization"] = "Bearer " + token
    if data is not None:
        if form:
            body = urllib.parse.urlencode(data).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            body = json.dumps(data).encode()
            headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with OPENER.open(req, timeout=120) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode(errors="replace")[:2000]}


def secret(key):
    out = subprocess.check_output(["kubectl", "-n", "eda-system", "get", "secret", "keycloak-admin-secret",
                                   "-o", "jsonpath={.data.%s}" % key])
    return base64.b64decode(out).decode()


def token():
    _, adm = http("POST", KC + "/realms/master/protocol/openid-connect/token", form=True, data={
        "grant_type": "password", "client_id": "admin-cli",
        "username": secret("username"), "password": secret("password")})
    adm = adm.get("access_token") or sys.exit("keycloak admin login failed")
    _, cl = http("GET", KC + "/admin/realms/eda/clients?clientId=eda", token=adm)
    _, cs = http("GET", KC + "/admin/realms/eda/clients/%s/client-secret" % cl[0]["id"], token=adm)
    _, tok = http("POST", KC + "/realms/eda/protocol/openid-connect/token", form=True, data={
        "grant_type": "password", "client_id": "eda", "client_secret": cs["value"], "scope": "openid",
        "username": "admin", "password": "admin"})
    return tok.get("access_token") or sys.exit("eda admin login failed")


def load_docs(path):
    try:
        import yaml
        return [d for d in yaml.safe_load_all(open(path)) if d]
    except ImportError:
        out = subprocess.check_output(["kubectl", "create", "--dry-run=client", "--validate=false",
                                       "-o", "json", "-f", path]).decode()
        dec, docs, i = json.JSONDecoder(), [], 0
        while i < len(out):
            if out[i].isspace():
                i += 1
                continue
            doc, i = dec.raw_decode(out, i)
            docs.extend(doc["items"] if doc.get("kind") == "List" else [doc])
        return docs


def gvk(doc):
    group, version = doc["apiVersion"].split("/")
    return {"group": group, "version": version, "kind": doc["kind"]}


def exists(doc):
    plural = subprocess.run(["kubectl", "api-resources", "--api-group", doc["apiVersion"].split("/")[0],
                             "--no-headers", "-o", "name"], capture_output=True, text=True).stdout.split()
    kind = doc["kind"].lower()
    res = next((p for p in plural if p.split(".")[0] in (kind + "s", kind + "es", kind[:-1] + "ies")), None)
    if not res:
        return False
    r = subprocess.run(["kubectl", "-n", doc["metadata"]["namespace"], "get", res, doc["metadata"]["name"]],
                       capture_output=True)
    return r.returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--commit", action="store_true")
    ap.add_argument("--desc", default="dcgw-3/4 border leaves of backbone-simulation")
    a = ap.parse_args()

    ops = []
    for doc in load_docs(a.file):
        md = doc["metadata"]
        for k in ("creationTimestamp", "resourceVersion", "uid", "managedFields", "generation"):
            md.pop(k, None)
        if doc.pop("x-op", None) == "delete":
            ops.append({"type": {"delete": {"gvk": gvk(doc), "name": md["name"], "namespace": md["namespace"]}}})
            print("delete ", doc["kind"], md["namespace"], md["name"])
        else:
            op = "replace" if exists(doc) else "create"
            ops.append({"type": {op: {"value": doc}}})
            print(op.ljust(8), doc["kind"], md["namespace"], md["name"])

    tok = token()
    body = {"crs": ops, "description": a.desc, "dryRun": not a.commit, "retain": True, "resultType": "normal"}
    code, resp = http("POST", EDA + "/core/transaction/v2", data=body, token=tok)
    if code >= 300:
        print("submit failed", code, json.dumps(resp)[:3000])
        sys.exit(1)
    tid = resp.get("id")
    print("transaction", tid, "dryRun" if not a.commit else "COMMIT")
    for _ in range(60):
        code, summ = http("GET", EDA + "/core/transaction/v2/result/summary/%s" % tid, token=tok)
        if summ.get("state") not in (None, "running", "pending", "queued"):
            break
        time.sleep(2)
    print(json.dumps(summ, indent=1)[:4000])
    sys.exit(0 if summ.get("success") else 2)


if __name__ == "__main__":
    main()
