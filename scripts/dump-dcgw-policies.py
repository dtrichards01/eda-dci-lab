import json
import sys

path = sys.argv[1]
with open(path) as f:
    d = json.load(f)
print("TOP KEYS:", list(d.keys())[:30])
rp_key = next((k for k in d if "routing-policy" in k), None)
rp = d.get(rp_key, {}) if rp_key else {}
if isinstance(rp, dict):
    policies = rp.get("policy", [])
else:
    policies = []
print("POLICY COUNT:", len(policies))
for p in policies:
    name = p.get("name", "")
    if any(x in name for x in ["ibgp-export", "import-policy-dcgw", "export-dc", "export-wan", "ibgp-import", "tag"]):
        print("===", name, "===")
        print(json.dumps(p, indent=2))
# also search for tag-set in full config
text = json.dumps(d)
if "tag-10" in text:
    print("FOUND tag-10 in config")
if "tag-20" in text:
    print("FOUND tag-20 in config")
