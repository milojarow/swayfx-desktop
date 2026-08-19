#!/usr/bin/env bash
# disk-monitor.sh — Checks real disk usage and alerts via notify-send.
#
# Lesson from a full-disk incident: df and du -x MUST be compared. When df reports significantly
# more than du -x, something invisible is eating disk — overlayfs layers,
# deleted-but-open files, containerd snapshots, zombie processes holding
# file descriptors. The divergence IS the alert.
#
# Designed to run as a daily systemd user timer.

set -euo pipefail

ALERT_ROOT_PERCENT=80
ALERT_PODMAN_GB=15
ALERT_HOME_GB=300
ALERT_TMP_GB=2
ALERT_DIVERGENCE_GB=10  # df vs du -x divergence threshold

notify() {
    local urgency="$1" title="$2" body="$3"
    notify-send -u "$urgency" -a "disk-monitor" "$title" "$body"
    logger -t disk-monitor "$urgency: $title — $body"
}

# --- Core check: df vs du -x divergence (the runaway-disk diagnostic) ---

# df: what the kernel thinks is used (includes overlayfs, deleted-but-open files)
df_used_kb=$(df / | tail -1 | awk '{print $3}')
df_used_gb=$((df_used_kb / 1024 / 1024))
total_gb=$(df / | tail -1 | awk '{print int($2/1024/1024)}')

# du -x: what actually exists on disk (stays on same filesystem)
du_used_kb=$(sudo du -x -s / 2>/dev/null | awk '{print $1}') || true
du_used_gb=$((du_used_kb / 1024 / 1024))

# The divergence — this is where ghosts live
divergence_gb=$((df_used_gb - du_used_gb))
if [ "$divergence_gb" -lt 0 ]; then
    divergence_gb=$(( -divergence_gb ))
fi

if [ "$divergence_gb" -gt "$ALERT_DIVERGENCE_GB" ]; then
    # Something invisible is eating disk. Identify likely culprits.
    culprits=""

    # Check for deleted-but-open files (processes holding dead file descriptors)
    deleted_kb=$(sudo find /proc/*/fd -follow -type f 2>/dev/null | \
        xargs sudo ls -l 2>/dev/null | grep '(deleted)' | \
        awk '{sum += $5} END {print int(sum/1024)}' 2>/dev/null || echo "0")
    deleted_mb=$((deleted_kb / 1024))
    if [ "$deleted_mb" -gt 100 ]; then
        culprits="${culprits}Deleted-but-open files: ${deleted_mb}MB. "
    fi

    # Check Podman overlay layers (rootless)
    podman_overlay="$HOME/.local/share/containers/storage/overlay"
    if [ -d "$podman_overlay" ]; then
        overlay_count=$(ls "$podman_overlay" 2>/dev/null | wc -l)
        if [ "$overlay_count" -gt 50 ]; then
            culprits="${culprits}Podman overlay layers: ${overlay_count}. "
        fi
    fi

    [ -z "$culprits" ] && culprits="Unknown source — investigate with lsof +L1 and du -d1"

    notify critical \
        "GHOST DISK: ${divergence_gb}GB invisible" \
        "df says ${df_used_gb}GB used, du -x says ${du_used_gb}GB real. ${divergence_gb}GB is phantom data. ${culprits}"
fi

# --- Standard threshold checks ---

# Real usage (du -x based, not df)
if [ "$total_gb" -gt 0 ]; then
    real_pct=$((du_used_gb * 100 / total_gb))
    if [ "$real_pct" -gt "$ALERT_ROOT_PERCENT" ]; then
        notify critical "Disk: root ${real_pct}% real" "${du_used_gb}GB of ${total_gb}GB (du -x)"
    fi
fi

# Podman storage (rootless — lives in home dir)
podman_gb=0
podman_storage="$HOME/.local/share/containers/storage"
if [ -d "$podman_storage" ]; then
    podman_kb=$(du -x -s "$podman_storage" 2>/dev/null | awk '{print $1}') || true
    podman_gb=$((podman_kb / 1024 / 1024))
    if [ "$podman_gb" -gt "$ALERT_PODMAN_GB" ]; then
        notify warning "Disk: Podman ${podman_gb}GB" "$podman_storage exceeds ${ALERT_PODMAN_GB}GB threshold"
    fi
fi

# Home directory
home_kb=$(du -x -s "$HOME" 2>/dev/null | awk '{print $1}') || true
home_gb=$((home_kb / 1024 / 1024))
if [ "$home_gb" -gt "$ALERT_HOME_GB" ]; then
    notify warning "Disk: Home ${home_gb}GB" "$HOME exceeds ${ALERT_HOME_GB}GB threshold"
fi

# /tmp
tmp_kb=$(du -x -s /tmp 2>/dev/null | awk '{print $1}') || true
tmp_gb=$((tmp_kb / 1024 / 1024))
if [ "$tmp_gb" -gt "$ALERT_TMP_GB" ]; then
    notify warning "Disk: /tmp ${tmp_gb}GB" "/tmp exceeds ${ALERT_TMP_GB}GB threshold"
fi

logger -t disk-monitor "df=${df_used_gb}GB du=${du_used_gb}GB divergence=${divergence_gb}GB podman=${podman_gb}GB home=${home_gb}GB tmp=${tmp_gb}GB (total=${total_gb}GB)"
