#!/bin/sh
# Delega el controlador memory a darktux para usar cbuild sin root.
[ -d /sys/fs/cgroup ] || exit 0
grep -q cgroup2 /proc/mounts 2>/dev/null || exit 0

mkdir -p /sys/fs/cgroup/user
echo +memory > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true

chown darktux:darktux /sys/fs/cgroup/user 2>/dev/null || true
chown darktux:darktux /sys/fs/cgroup/user/cgroup.procs \
    /sys/fs/cgroup/user/cgroup.subtree_control \
    /sys/fs/cgroup/user/cgroup.threads 2>/dev/null || true
