# EDA platform restore — cluster connection examples

The restore script uses **kubectl** (Kubernetes API), not the EDA UI URL.

## Quick start

Copy the script into your backup directory once, then run it interactively:

```bash
cp /mnt/c/Users/darrenri/Documents/eda-dci-lab/scripts/eda-platform-restore.sh ~/backups/
sed -i 's/\r$//' ~/backups/eda-platform-restore.sh   # strip CRLF if edited on Windows
chmod +x ~/backups/eda-platform-restore.sh

cd ~/backups
./eda-platform-restore.sh
```

No environment variables required. The wizard prompts for kubectl context, backup directory, namespace, toolbox pod, and backup file — with sensible defaults (Enter to accept).

## What you need

| Requirement | Purpose |
|-------------|---------|
| `kubectl` | Talk to the cluster API |
| `kubeconfig` | Credentials + cluster API address (`KUBECONFIG` or `~/.kube/config`) |
| Backup `.tar.gz` on disk | Copied into `eda-toolbox` before `edactl platform restore` |
| `eda-toolbox` pod running | `edactl` runs inside this pod |

The EDA UI (`https://100.124.186.55`) is only for humans after restore — the script never calls it.

## Run the script — do not source it

**Execute** the script directly. Never source it:

```bash
# WRONG — corrupts your shell, garbles prompts, may cause pop_var_context errors
. eda-platform-restore.sh
source eda-platform-restore.sh

# CORRECT
chmod +x eda-platform-restore.sh
./eda-platform-restore.sh
```

## Interactive wizard

When you run `./eda-platform-restore.sh`, the script walks through:

1. **kubectl context** — shows current context and a numbered list; Enter accepts current, or type a number/name
2. **Backup directory** — defaults to `~/backups` when run from there (or the script's directory if it lives in a `backups` folder)
3. **EDA namespace** — default `eda-system`
4. **Host safety check** — auto-skipped for `kind-*` contexts or WSL/local (host not `k0r4` and context not `admin@eda-compute-cluster`); otherwise informational warnings with continue prompt (default: yes)
5. **Toolbox pod** — verified early after cluster connect; auto-discovers `eda-toolbox` pod; Enter accepts or type an override
6. **Backup file** — numbered list of `.tar.gz` files in the backup directory
7. **Summary** — shows all choices and asks `Proceed? [Y/n]`

Example session (WSL KIND):

```
=== EDA platform restore ===

kubectl context
  Current: kind-eda-demo-wsl2
     1) kind-eda-demo-wsl2 *
Context [kind-eda-demo-wsl2]:

Cluster:    Kubernetes control plane is running at https://127.0.0.1:xxxxx

Toolbox pod: eda-toolbox-549c9ddd7f-t98lc

Backup directory [/home/darrenri/backups]:

EDA namespace [eda-system]:

Host safety checks: skipped (kind-* context)

Toolbox pod: eda-toolbox-549c9ddd7f-t98lc
Toolbox pod [eda-toolbox-549c9ddd7f-t98lc]:

Backups in /home/darrenri/backups:
   1) platformbackup-dci-all-srl-010826-0930.tar.gz  (1.2G)

Enter number or full backup file name: 1

=== Restore summary ===
  Context:    kind-eda-demo-wsl2
  Backup dir: /home/darrenri/backups
  Backup:     platformbackup-dci-all-srl-010826-0930.tar.gz (1.2G)
  Namespace:  eda-system
  Toolbox:    eda-toolbox-549c9ddd7f-t98lc
  ...

Proceed? [Y/n]:
```

## Talos DCI lab (k0r4)

```bash
cd /home/nokia/backups
./eda-platform-restore.sh
```

On k0r4 with context `admin@eda-compute-cluster`, host safety checks pass automatically.

## WSL KIND lab (`kind-eda-demo-wsl2`)

```bash
cd ~/backups
./eda-platform-restore.sh
```

`kind-*` contexts skip Talos hostname/context checks automatically. Pick `kind-eda-demo-wsl2` from the context prompt (or press Enter if it's already current).

**One-liner** with explicit env overrides:

```bash
SKIP_HOST_CHECK=1 KUBE_CONTEXT=kind-eda-demo-wsl2 BACKUP_DIR=~/backups ./eda-platform-restore.sh
```

## Non-interactive mode (`-y`)

For automation or CI, use `-y` to skip prompts. Environment variables still work as overrides:

```bash
KUBE_CONTEXT=kind-eda-demo-wsl2 BACKUP_DIR=~/backups ./eda-platform-restore.sh -y
./eda-platform-restore.sh -y platformbackup-dci-all-srl-010826-0930.tar.gz
```

With `-y`: uses env vars / defaults, auto-selects the latest backup if no file argument given, and proceeds without confirmation.

### Environment variable overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `KUBE_CONTEXT` | current context | kubectl context |
| `BACKUP_DIR` | `~/backups` or `/home/nokia/backups` | Directory with `.tar.gz` backups |
| `EDA_NAMESPACE` | `eda-system` | Toolbox pod namespace |
| `TOOLBOX_POD` | auto-discover | Explicit toolbox pod name |
| `TOOLBOX_LABEL` | `eda.nokia.com/app=eda-toolbox` | Label selector for discovery |
| `SKIP_HOST_CHECK` | auto for `kind-*` | Set to `1` to skip host/context warnings |
| `RESTORE_TIMEOUT` | `15m` | `edactl` timeout |
| `KUBECONFIG` | `~/.kube/config` | Path to kubeconfig |
| `EDA_UI_URL` | — | Display only (not used for API calls) |

## From your laptop (kubeconfig for Talos)

```bash
export KUBECONFIG=~/kubeconfigs/eda-talos.conf
cd /path/to/backups
./eda-platform-restore.sh
```

The wizard will prompt for context and show host/context warnings (default: continue).

## SSH pattern (no local kubeconfig)

```bash
ssh nokia@100.124.186.51 'cd /home/nokia/backups && ./eda-platform-restore.sh'
```

Backups stay on the SSH host; kubectl runs there too.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Garbled prompts (`'. Continue? [y/N] ykind-eda-demo-wsl2'`) | CRLF line endings (`\r`) in the script | `sed -i 's/\r$//' eda-platform-restore.sh` |
| `pop_var_context: head of shell_variables not a function context` | Script was **sourced** (`. script`) not executed | `exec bash`; run `./eda-platform-restore.sh` (not `. eda-platform-restore.sh`) |
| `No eda-toolbox pod in namespace eda-system` | CRLF made namespace `eda-system\r`, or EDA not installed | Fix CRLF; verify pod exists (see below) |
| Cannot reach cluster | Wrong context or kubeconfig | Re-run wizard and pick correct context from list |

**Verify toolbox pod before restore:**

```bash
kubectl --context kind-eda-demo-wsl2 get pods -n eda-system | grep -i toolbox
kubectl --context kind-eda-demo-wsl2 get pods -A | grep -i toolbox
```

Expected pod name pattern: `eda-toolbox-<hash>-<id>` (e.g. `eda-toolbox-549c9ddd7f-t98lc`).

Discovery order: `TOOLBOX_POD` env → `TOOLBOX_LABEL` selector → pod name containing `toolbox`.
