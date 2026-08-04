# EDA platform restore — cluster connection examples

The restore script uses **kubectl** (Kubernetes API), not the EDA UI URL.

## What you need

| Requirement | Purpose |
|-------------|---------|
| `kubectl` | Talk to the cluster API |
| `kubeconfig` | Credentials + cluster API address (`KUBECONFIG` or `~/.kube/config`) |
| `KUBE_CONTEXT` | Which cluster/context when kubeconfig has several |
| Backup `.tar.gz` on disk | Copied into `eda-toolbox` before `edactl platform restore` |
| `eda-toolbox` pod running | `edactl` runs inside this pod |

The EDA UI (`https://100.124.186.55`) is only for humans after restore — the script never calls it.

## Talos DCI lab (k0r4)

```bash
cd /home/nokia/backups
./eda-platform-restore.sh
```

Defaults: context `admin@eda-compute-cluster`, host `k0r4`.

## From your laptop (kubeconfig for Talos)

```bash
export KUBECONFIG=~/kubeconfigs/eda-talos.conf
export KUBE_CONTEXT=admin@eda-compute-cluster
export SKIP_HOST_CHECK=1
export BACKUP_DIR=/path/to/backups   # tarball must be on THIS machine
export EDA_UI_URL=https://100.124.186.55   # optional label only

./eda-platform-restore.sh
```

## Another EDA / KIND lab

```bash
export KUBECONFIG=~/.kube/config
export KUBE_CONTEXT=kind-eda-demo-wsl2
export SKIP_HOST_CHECK=1
export EXPECTED_CONTEXT=   # disable context warning
export BACKUP_DIR=/home/clab/backups
export EDA_NAMESPACE=eda-system

./eda-platform-restore.sh
```

## SSH pattern (no local kubeconfig)

```bash
ssh nokia@100.124.186.51 'cd /home/nokia/backups && ./eda-platform-restore.sh'
```

Backups stay on the SSH host; kubectl runs there too.
