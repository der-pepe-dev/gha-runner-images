# NAS beefy Linux runner (TrueNAS Docker app)

A GPU-capable, high-capacity **ephemeral** Linux runner for heavy/less-frequent jobs, run
as a TrueNAS Scale (25.10 Goldeye) Docker app so it **shares the GPU** like your other apps
(no exclusive VM passthrough). Opt-in via labels `nas,beefy,gpu`.

## Why Docker (not a VM) here

The GPU is used by other TrueNAS apps. A VM would need exclusive PCIe passthrough (can't
share). A Docker container shares the GPU via the nvidia runtime — so for GPU + Linux, the
app model is the right one. (Windows-beefy would still need an Incus VM, without GPU.)

## Model

The container runs a JIT loop (`entrypoint.sh`): mint a just-in-time runner config → run
**one** job → repeat with a fresh registration. The container filesystem is the ephemeral
boundary; the runner also wipes `_work` per job. The PAT lives only in the app's secret env
and is never exposed to a workflow (JIT config only).

Baked toolchain (mirrors the Proxmox Linux image): .NET 10 SDK, PowerShell 7, Node LTS,
build-essential + clang/zlib (Native AOT), cmake, ninja, mingw-w64, sqlite3, ffmpeg, python3
— on a CUDA `devel` base (nvcc + CUDA libs) so GPU jobs build and run.

## Deploy (TrueNAS 25.10 custom app / docker compose)

1. `cp runner.secret.env.example runner.secret.env` and set `GITHUB_TOKEN` (fine-grained
   org PAT: Self-hosted runners = Read+Write).
2. Build + start (Apps → Custom App → install via compose, or on the shell):
   ```bash
   docker compose build
   docker compose up -d
   ```
3. Ensure the app has the **GPU allocated** (TrueNAS app GPU setting, or the compose
   `deploy.resources` block — whichever your install honors). `nvidia-smi -L` runs at
   startup and logs the visible GPU.
4. The runner registers to the org with `nas,beefy,gpu` and picks up matching jobs.

Target it from a workflow:
```yaml
runs-on: [self-hosted, linux, x64, dotnet10, nas, beefy, gpu]
```

## Scale

Leave `RUNNER_NAME` unset and run N replicas — each gets a unique hostname-based name:
```bash
docker compose up -d --scale gha-nas-linux=3
```
For a single fixed-name runner, set `RUNNER_NAME` in the compose env.

## Notes

- CPU/RAM/disk "beefy" comes from the host — cap per-container if needed via compose limits.
- No-GPU variant: set build arg `CUDA_BASE=ubuntu:24.04` (drops CUDA, smaller image).
- This is separate from the Proxmox ephemeral fleet — a capacity add-on, opt-in by label.
