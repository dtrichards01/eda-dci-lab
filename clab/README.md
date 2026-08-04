# CLAB deploy — `srl-leaf-spine-dcgw`

Run Containerlab from **this directory** (`eda-dci-lab/clab`). Do not copy the YAML elsewhere unless you also copy `configs/` beside it.

## Why this layout

Containerlab resolves `binds:` paths **relative to the topology file’s directory**. With:

```
clab/
  clab-leaf-spine-dcgw-srl-only.yaml
  configs/
    client-config.sh
    base-configs/mh-dc1a.sh …
```

binds like `configs/client-config.sh` and `exec: bash /client-config.sh …` work without extra paths. Client `exec:` runs automatically on container start.

## Deploy (Talos host)

```bash
cd ~/eda-dci-lab/clab

# One-time: telemetry stack (not in this repo — copy from old 3-tier-dci if needed)
# cp -r ~/3-tier-dci/configs/telemetry configs/telemetry

clab deploy -t clab-leaf-spine-dcgw-srl-only.yaml
```

Destroy / redeploy:

```bash
cd ~/eda-dci-lab/clab
clab destroy -t clab-leaf-spine-dcgw-srl-only.yaml
clab deploy -t clab-leaf-spine-dcgw-srl-only.yaml
```

## Client script names (YAML vs your `base-configs/`)

The topology binds these paths (relative to this directory):

| CLAB node | Bind path | Repo script |
|-----------|-----------|-------------|
| client-10-dc1-mh (all-active DC1) | `configs/base-configs/mh-dc1a.sh` | `mh-dc1a.sh` |
| client-11-dc2-mh (all-active DC2) | `configs/base-configs/mh-dc2a.sh` | `mh-dc2a.sh` |
| client-12-dc1-mh (single-active DC1) | `configs/base-configs/mh-dc1b.sh` | `mh-dc1b.sh` |
| client-13-dc2-mh (single-active DC2) | `configs/base-configs/mh-dc2b.sh` | `mh-dc2b.sh` |
| clients 1–9 | `configs/client-config.sh` | `client-config.sh` |

Repo names (`mh-dc1a` = all-active DC1, `mh-dc1b` = single-active DC1, etc.) come from your earlier MH examples — not `mh-client-1` / `mh-dc1.sh`.

If you have scripts under `clab/base-configs/` instead of `clab/configs/base-configs/`, fix before deploy:

```bash
cd ~/eda-dci-lab/clab
mkdir -p configs/base-configs

# Map your filenames → names the YAML expects (adjust if your scripts differ):
cp base-configs/mh-client-1.sh configs/base-configs/mh-dc1a.sh
cp base-configs/mh-client-3.sh configs/base-configs/mh-dc2a.sh
cp base-configs/mh-client-4.sh configs/base-configs/mh-dc1b.sh
cp base-configs/mh-client-6.sh configs/base-configs/mh-dc2b.sh
chmod +x configs/base-configs/*.sh configs/client-config.sh

# Or sync the whole tree from Windows repo (replaces local names):
# scp -r .../eda-dci-lab/clab/configs/ ~/eda-dci-lab/clab/configs/
```

`sh-client-2.sh` / `sh-client-5.sh` are **not** used by this YAML — SH clients (8–9) use `client-config.sh` with IPs in `exec:`.

Verify:

```bash
ls -l configs/client-config.sh configs/base-configs/mh-dc1a.sh
```


| Item | Path in YAML | Repo file |
|------|----------------|-----------|
| Native / SH clients | `configs/client-config.sh` → `/client-config.sh` | `configs/client-config.sh` |
| MH all-active DC1 | `configs/base-configs/mh-dc1a.sh` → `/base-configs/mh-dc1a.sh` | `configs/base-configs/mh-dc1a.sh` |
| MH all-active DC2 | `mh-dc2a.sh` | same pattern |
| MH single-active | `mh-dc1b.sh`, `mh-dc2b.sh` | same pattern |
| SRL license | `/home/nokia/darren/license/...` | host path on Talos — edit YAML if yours differs |
| Telemetry (gnmic/prometheus/grafana) | `configs/telemetry/...` | copy from `~/3-tier-dci/configs/telemetry` or remove those nodes |

## After CLAB

1. Register topology with EDA (integrate / fabric workflow).
2. **Topology CRs** (if clab-connector missed ISL/edge links after re-import):

```bash
cd ~/eda-dci-lab
python3 clab/eda-topology/gen_clab_eda_cr.py   # if YAML changed
bash scripts/apply-topology-cr.sh
```

3. Apply DCI services: `bash ~/eda-dci-lab/scripts/apply-all.sh`

EDA scripts configure **fabric** (edges, vnets, interconnect). They do not replace client `exec:` — clients are already configured when CLAB starts them.

## Migrating from `~/3-tier-dci`

You can stop maintaining a second copy of the topology YAML. Keep `3-tier-dci` only if it still holds fabric bootstrap or telemetry configs you have not moved yet. Preferred end state:

- **CLAB topology + client scripts** → `~/eda-dci-lab/clab/`
- **EDA services + apply scripts** → `~/eda-dci-lab/services/` + `scripts/`
