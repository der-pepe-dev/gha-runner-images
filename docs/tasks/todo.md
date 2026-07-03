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
