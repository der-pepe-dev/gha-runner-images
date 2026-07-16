#!/usr/bin/env bash
# Image smoke test for the Linux GHA runner. The Packer build runs this AS THE RUNNER
# ACCOUNT (gha-runner) so it validates what an actual job's service account sees. Exits
# non-zero on any failure: a tool is absent, not resolvable through PATH, exits non-zero, or
# its version differs from the pinned expectation.
#
# It NEVER contacts a SonarQube server and NEVER downloads the Trivy vulnerability database —
# only executable/version smoke checks. Expected versions come from the environment:
#   EXPECTED_TRIVY, EXPECTED_SONARSCANNER   (set by the Packer provisioner from pinned vars)
set -uo pipefail

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1 || fail "$1 not found on PATH (whoami=$(whoami) PATH=$PATH)"; }

echo "smoke test as $(whoami)"

# Run from a dir this account can read: the build invokes us from the provisioning user's
# home, which the runner account can't enter — and Trivy tries to load ./trivy.yaml from CWD
# (fails with EACCES on an inaccessible dir). A world-accessible dir avoids that.
cd /tmp || exit 1

# .NET SDK — also supplies the Roslyn analyzers (no separate analyzer package).
have dotnet
dotnet --info >/dev/null 2>&1 || fail "dotnet --info exited non-zero"

# SonarScanner for .NET (dotnet-sonarscanner). Must be on PATH for the runner account and
# report the pinned version. Prefer `dotnet sonarscanner --version`; fall back to the direct
# `dotnet-sonarscanner --version` and finally the tool manifest — whichever the installed
# .NET supports — so the check is robust while still proving the pinned version is present.
have dotnet-sonarscanner
want="${EXPECTED_SONARSCANNER:-}"
ss_out="$(dotnet sonarscanner --version 2>&1)"
if [ -n "$want" ] && ! printf '%s' "$ss_out" | grep -qF "$want"; then
  ss_out="$(dotnet-sonarscanner --version 2>&1)"
fi
if [ -n "$want" ] && ! printf '%s' "$ss_out" | grep -qF "$want"; then
  ss_out="$(dotnet tool list --tool-path /opt/dotnet-tools 2>&1)"
fi
if [ -n "$want" ]; then
  printf '%s' "$ss_out" | grep -qF "$want" \
    || fail "dotnet-sonarscanner ${want} not confirmed (dotnet sonarscanner / dotnet-sonarscanner / tool list): ${ss_out}"
fi

# Trivy CLI — executable/version smoke only (no DB download).
have trivy
tv_out="$(trivy --version 2>&1)" || fail "trivy --version exited non-zero: ${tv_out}"
if [ -n "${EXPECTED_TRIVY:-}" ]; then
  printf '%s' "$tv_out" | grep -qF "$EXPECTED_TRIVY" \
    || fail "trivy version mismatch (want ${EXPECTED_TRIVY}): ${tv_out}"
fi

echo "smoke test OK: dotnet + dotnet-sonarscanner ${EXPECTED_SONARSCANNER:-?} + trivy ${EXPECTED_TRIVY:-?}"
