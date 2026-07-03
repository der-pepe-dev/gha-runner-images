# Backlog

Durable, prioritized task list. Active work goes in `tasks/<task-name>.md`, not here.

## High priority

<!-- TODO -->

## Medium priority

## Low priority / someday

## NAS runner — future (noted 2026-07-03)

- **Shader-compiler tooling** (CPU, no GPU): if DePam or others compile shaders in CI, bake
  `glslang` + `shaderc` (glslc) + `spirv-tools` (Vulkan/GL/SPIR-V) and `dxc`
  (DirectXShaderCompiler Linux release, HLSL→DXIL for the mingw/Windows target) into the
  runner image. Shader *compilation* is CPU-only — belongs on a plain `nas` runner.
- **Split GPU vs non-GPU NAS images**: `gpu` image only for GPU *execution* (ML/CUDA,
  ffmpeg NVENC/NVDEC, headless render/pipeline tests); a plain `nas` image (build arg
  `CUDA_BASE=ubuntu:24.04`, labels `nas`) for CPU-heavy jobs (shader compile, DePam
  cross-compile). Route jobs by label so GPU jobs don't hog, and non-GPU jobs don't reserve
  the GPU.
- **NAS Windows runner**: skipped for now; if ever needed, an Incus VM (TrueNAS 25.10 = Incus)
  with a JIT loop, no GPU.

## macOS / "Hackintosh" runner — future (noted 2026-07-03)

- **For iOS/Mac/MAUI targets.** LICENSING: macOS EULA = Apple hardware only; a Hackintosh VM
  is outside it (homelab risk call). Clean alternative: an Apple-silicon Mac mini as a runner.
- **Host: Proxmox, not TrueNAS.** PVE has the mature macOS-KVM path (OSX-KVM / OpenCore: OSK
  key, cpu=host + macOS QEMU args, OVMF, virtio/vmxnet, optional GPU passthrough). Incus on
  TrueNAS fights the macOS-specific QEMU quirks.
- **Runner model: self-mint JIT** (PAT in the VM, entrypoint loops like the Docker NAS
  runner) — the Proxmox guest-agent inject is unreliable on macOS. Off-state snapshot (cold
  boot) rather than vmstate (macOS + RAM snapshot is finicky). Labels
  `self-hosted,macos,x64|arm64,nas` (+ `xcode` etc. as needed).
