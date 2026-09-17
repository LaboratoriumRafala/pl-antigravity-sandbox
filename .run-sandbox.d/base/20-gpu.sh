#!/bin/bash
# ==============================================================================
# 20-gpu.sh — Autodetekcja akceleratora graficznego (GPU)
# ==============================================================================
# Linux natywny używa /dev/dri (Direct Rendering Infrastructure).
# WSL2 (Windows) używa /dev/dxg (DirectX Graphics).
#
# Jeśli żaden z nich nie istnieje, kontener uruchomi się bez akceleracji
# sprzętowej (software rendering). Grafika będzie działać, ale wolniej.

if [ -e /dev/dri ]; then
    PODMAN_EXTRA_ARGS+=(--device /dev/dri)
elif [ -e /dev/dxg ]; then
    # WSL2: Microsoft mapuje GPU jako /dev/dxg
    PODMAN_EXTRA_ARGS+=(--device /dev/dxg)
else
    echo "⚠️  GPU: Nie wykryto /dev/dri ani /dev/dxg — kontener uruchomi się bez akceleracji sprzętowej."
fi
