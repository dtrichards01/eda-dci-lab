#!/usr/bin/env python3
"""Copy live CLAB YAML and add AllActive L2 anycast test client on e1-10."""
from pathlib import Path

src = Path("/home/nokia/3-tier-dci/clab-s-spine-spine-leaf-srl-only.yaml")
dst = Path("/home/nokia/3-tier-dci/clab-s-spine-spine-leaf-srl-only-avtep-client.yaml")
text = src.read_text()
if "client-10-avtep" in text:
    print("client-10-avtep already in source; writing copy anyway")
node = """
    client-10-avtep:
      kind: linux
      mgmt-ipv4: 172.65.10.126
      labels: { role: client, site: dc1, vnet: vnet-mh-l2-avtep, mh-mode: all-active }
"""
if "client-10-avtep:" not in text:
    if "    gnmic:" not in text:
        raise SystemExit("gnmic stanza not found")
    text = text.replace("    gnmic:", node + "\n    gnmic:", 1)
links = """
    - endpoints: ["client-10-avtep:eth1", "srl-leaf-3:e1-10"]
    - endpoints: ["client-10-avtep:eth2", "srl-leaf-4:e1-10"]
"""
if "client-10-avtep:eth1" not in text:
    if not text.endswith("\n"):
        text += "\n"
    text += links
dst.write_text(text)
print(f"wrote {dst} bytes={dst.stat().st_size}")
