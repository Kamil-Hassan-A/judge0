#!/bin/bash
# Judge0 Docker entrypoint.
#
# Step 1: Fix CRLF line endings in judge0.conf (may be Windows-edited).
# scripts/load-config sources this file directly in bash; \r causes
# "command not found" errors for every variable assignment line.
if [ -f /judge0.conf ]; then
    sudo sed -i 's/\r//' /judge0.conf
fi

# Step 2: Bootstrap cgroup v2 controllers at runtime.
# On cgroup v1 systems /sys/fs/cgroup/cgroup.controllers is absent
# and this block is skipped entirely.
CGROUP_PATH="/sys/fs/cgroup"
if [ -f "$CGROUP_PATH/cgroup.controllers" ]; then
    echo "[judge0-bootstrap] cgroup v2 detected — enabling controllers"

    # Enable cpu/memory/pids at the root level (best-effort; may already be set)
    sudo bash -c "echo '+cpu +memory +pids' > $CGROUP_PATH/cgroup.subtree_control" 2>/dev/null || true

    # Create /sys/fs/cgroup/isolate and delegate controllers into it.
    # isolate's config has: cg_root = /sys/fs/cgroup/isolate
    sudo mkdir -p "$CGROUP_PATH/isolate"
    sudo bash -c "echo '+cpu +memory +pids' > $CGROUP_PATH/isolate/cgroup.subtree_control" 2>/dev/null || true

    echo "[judge0-bootstrap] Controllers active: $(cat $CGROUP_PATH/cgroup.controllers)"
else
    echo "[judge0-bootstrap] cgroup v1 detected — skipping v2 bootstrap"
fi

# Step 3: Ensure lock_root exists and is writable (lives in tmpfs on each boot).
sudo mkdir -p /run/isolate/locks
sudo chmod 1777 /run/isolate/locks

# Step 4: Start cron daemon for Judge0 scheduled tasks.
sudo cron

# Step 5: Hand off to CMD (./scripts/server or ./scripts/workers).
exec "$@"
