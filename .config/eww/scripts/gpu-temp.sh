#!/bin/bash
# feature: temps
# role:    helper
# gpu-temp.sh — GPU temperature WITHOUT keeping the dGPU awake.
#
# nvidia-smi wakes the M1000M and holds it active; polled every 5s the
# card could never reach its autosuspend window (runtime_status was
# permanently "active"). Reading power/runtime_status is a kernel PM
# attribute and never wakes the device — so: only query nvidia-smi while
# something real already has the GPU active; while suspended emit 0 and
# let it sleep. The proprietary driver exposes no hwmon node (verified),
# so there is no wake-free temperature source.

GPU_PCI="/sys/bus/pci/devices/0000:01:00.0"

status=$(cat "$GPU_PCI/power/runtime_status" 2>/dev/null)
if [ "$status" = "active" ]; then
    nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0
else
    echo 0
fi
