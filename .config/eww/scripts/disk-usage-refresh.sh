#!/bin/bash
# feature: disk
# role:    helper
# disk-usage-refresh.sh — computes BOTH disk-widget payloads from ONE du
# pass and caches them in /tmp. Runs OUTSIDE eww's cgroup (systemd user
# timer eww-disk-refresh.timer) so du's page-cache/slab is never charged
# to eww.service and a config reload never blocks on an in-flight du
# (eww joins the old script-var runtime on the GTK main thread; a
# synchronous 25-65s du there froze the daemon for 40-70s).

HOME_DIR="$HOME"
USAGE_CACHE="/tmp/eww-disk-usage.json"
OTHER_CACHE="/tmp/eww-disk-other.json"

DISK_TOTAL=$(df --output=size "$HOME_DIR" | tail -1)
{ [ -z "$DISK_TOTAL" ] || [ "$DISK_TOTAL" -le 0 ]; } && DISK_TOTAL=1

# Single traversal feeds both payloads
du_home=$(du -d1 -k "$HOME_DIR" 2>/dev/null)

size_of() {
    echo "$du_home" | awk -v p="$1" '$2 == p { print $1; exit }'
}

# ── Payload 1: category percentages ──────────────────────────────────────
docs_dir=$(xdg-user-dir DOCUMENTS); docs=$(size_of "$docs_dir"); docs=${docs:-0}
pics_dir=$(xdg-user-dir PICTURES);  pics=$(size_of "$pics_dir"); pics=${pics:-0}
dls_dir=$(xdg-user-dir DOWNLOAD);   dls=$(size_of "$dls_dir");   dls=${dls:-0}
vids_dir=$(xdg-user-dir VIDEOS);    vids=$(size_of "$vids_dir"); vids=${vids:-0}
home_total=$(size_of "$HOME_DIR");  home_total=${home_total:-0}

other=$(( home_total - docs - pics - dls - vids ))
[ "$other" -lt 0 ] && other=0

root_size=$(du -sk /root 2>/dev/null | awk '{print $1}')
root_size=${root_size:-0}

pct() {
    awk -v s="$1" -v t="$DISK_TOTAL" 'BEGIN { printf "%.1f", (s / t) * 100 }'
}

tmp_usage=$(mktemp /tmp/eww-disk-usage.XXXXXX)
printf '{"documents":%s,"pictures":%s,"downloads":%s,"videos":%s,"other":%s,"root":%s,"documents_path":"%s","pictures_path":"%s","downloads_path":"%s","videos_path":"%s"}\n' \
    "$(pct "$docs")" "$(pct "$pics")" "$(pct "$dls")" "$(pct "$vids")" \
    "$(pct "$other")" "$(pct "$root_size")" \
    "$docs_dir" "$pics_dir" "$dls_dir" "$vids_dir" > "$tmp_usage"
mv "$tmp_usage" "$USAGE_CACHE"
chmod 644 "$USAGE_CACHE"

# ── Payload 2: top 6 heaviest non-standard dirs ──────────────────────────
tmp_other=$(mktemp /tmp/eww-disk-other.XXXXXX)
echo "$du_home" | \
  sort -rnk1 | \
  awk -v home="$HOME_DIR" '
    BEGIN { count = 0 }
    {
      dir = $2
      if (dir == home) next
      name = dir
      sub(home "/", "", name)
      if (name == "documents" || name == "pictures" || name == "downloads" || name == "videos") next
      sizes[count] = $1
      names[count] = name
      paths[count] = dir
      count++
    }
    END {
      n = (count < 6) ? count : 6
      printf "["
      for (i = 0; i < n; i++) {
        if (i > 0) printf ","
        size_mb = sizes[i] / 1024
        if (size_mb >= 1024) {
          size_str = sprintf("%.1fG", size_mb / 1024)
        } else {
          size_str = sprintf("%.0fM", size_mb)
        }
        printf "{\"name\":\"%s\",\"path\":\"%s\",\"size\":\"%s\"}", names[i], paths[i], size_str
      }
      printf "]\n"
    }' > "$tmp_other"
mv "$tmp_other" "$OTHER_CACHE"
chmod 644 "$OTHER_CACHE"
