# NAS Linux GPU runner (TrueNAS Docker app)

A GPU-capable, high-capacity **ephemeral** Linux runner for heavy/less-frequent jobs, run
as a TrueNAS Scale (25.10 Goldeye) Docker app so it **shares the GPU** like your other apps
(no exclusive VM passthrough). Opt-in via labels `nas,gpu`.

## Why Docker (not a VM) here

The GPU is used by other TrueNAS apps. A VM would need exclusive PCIe passthrough (can't
share). A Docker container shares the GPU via the nvidia runtime — so for GPU + Linux, the
app model is the right one.

## Model

**No orchestrator.** The container is self-contained: `entrypoint.sh` mints a just-in-time
runner config, runs **one** job, and exits. With `restart: always`, Docker starts a fresh
container for the next job — so each job gets a pristine filesystem (cleaner than an
in-container loop). Unlike the Proxmox fleet, no snapshot-rollback or orchestrator is needed
— the container *is* the ephemeral boundary.

**PAT note.** The container self-mints, so the fine-grained org PAT lives in the app's secret
env — a job in that container could read it. Acceptable for **trusted private-repo** jobs
(the norm here). It is only a JIT config on the wire, never passed to the workflow. If you
ever need the PAT fully off the runner, front it with a small minter sidecar that hands the
container only the JIT config.

Baked toolchain (mirrors the Proxmox Linux image): .NET 10 SDK, PowerShell 7, Node LTS,
build-essential + clang/zlib (Native AOT), cmake, ninja, mingw-w64, sqlite3, ffmpeg, python3
— on a CUDA `devel` base (nvcc + CUDA libs) so GPU jobs build and run.

## Deploy (TrueNAS 25.10 custom app / docker compose)

1. In the TrueNAS app config, set **`GITHUB_TOKEN`** as an app **Environment Variable**
   (Apps → Custom App → Environment Variables) — a fine-grained org PAT with Self-hosted
   runners = Read+Write. No file needed; the app injects it into the container.
   (For a plain `docker compose` CLI deploy instead, `cp runner.secret.env.example
   runner.secret.env`, set the token there, and re-enable the `env_file:` line in the compose.)
2. Build + start (Apps → Custom App → install via compose, or on the shell with the token
   exported):
   ```bash
   GITHUB_TOKEN=github_pat_xxx docker compose up -d --build
   ```
3. Ensure the app has the **GPU allocated** (TrueNAS app GPU setting, or the compose
   `deploy.resources` block — whichever your install honors). `nvidia-smi -L` runs at
   startup and logs the visible GPU.
4. The runner registers to the org with `nas,gpu` and picks up matching jobs.

Target it from a workflow:
```yaml
runs-on: [self-hosted, linux, x64, dotnet10, nas, gpu]
```

## Scale

The default runs a single runner named `gha-linux-eph00`. To scale to N, remove the
`RUNNER_NAME` line (each replica self-names by hostname) and run replicas:
```bash
docker compose up -d --scale gha-nas-linux=3
```

## Notes

- High CPU/RAM/disk comes from the host — cap per-container if needed via compose limits.
- No-GPU variant: set build arg `CUDA_BASE=ubuntu:24.04` (drops CUDA, smaller image).
- This is separate from the Proxmox ephemeral fleet — a capacity add-on, opt-in by label.
