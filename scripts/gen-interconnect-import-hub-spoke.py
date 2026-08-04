#!/usr/bin/env python3
from pathlib import Path

EVPN = """    - name: accept-spoke-evpn-type-{n}
      action:
        policyResult: Accept
      match:
        families:
          - EVPN
        bgp:
          communitySet: dci-rt-hub-spoke-import
          evpnRouteTypes:
            - {n}
"""

evpn = "".join(EVPN.format(n=i) for i in range(1, 6))
text = f"""# Hub interconnect import: spoke stitch RTs 100 + 102.
apiVersion: routingpolicies.eda.nokia.com/v1
kind: Policy
metadata:
  name: import-dci-hub-spoke-stitch
  namespace: clab-srl-leaf-spine-dcgw
  labels:
    eda.nokia.com/dci: l3-stitch
spec:
  defaultAction:
    policyResult: Reject
  statements:
{evpn}
    - name: accept-spoke-ipvpn-stitch
      action:
        policyResult: Accept
      match:
        protocol: BGP_IPVPN
        bgp:
          communitySet: dci-rt-hub-spoke-import
"""
Path(__file__).resolve().parents[1] / "services/dci-policies/policies/import-dci-hub-spoke-stitch.yaml").write_text(text, encoding="utf-8")
