#!/bin/bash
# ==============================================================================
# 10-display.sh — Autodetekcja serwera graficznego (Wayland / X11)
# ==============================================================================
# Wayland jest preferowany (bezpieczny — pełna izolacja okien).
# X11 jest fallbackiem z ostrzeżeniem o ryzyku keyloggingu.
#
# Ten drop-in dodaje do PODMAN_EXTRA_ARGS odpowiednie flagi montowania
# gniazda graficznego i zmienne środowiskowe.

DISPLAY_MODE=""

# Sprawdzamy, czy host działa na Waylandzie
if [ "$XDG_SESSION_TYPE" = "wayland" ] && [ -n "$WAYLAND_DISPLAY" ]; then
    WAYLAND_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY}"
    if [ -S "$WAYLAND_SOCKET" ]; then
        DISPLAY_MODE="wayland"
    fi
fi

if [ "$DISPLAY_MODE" = "wayland" ]; then
    # === Tryb Wayland (Bezpieczny) ===
    echo "🛡️  Wykryto Wayland — tryb bezpieczny (izolacja okien aktywna)."
    
    # Montujemy gniazdo w dedykowanym, poprawnym katalogu (nie w /tmp),
    # ponieważ libwayland-client rygorystycznie weryfikuje uprawnienia (0700).
    # Podman automatycznie zmapuje uprawnienia podczas montowania pliku.
    PODMAN_EXTRA_ARGS+=(-v "$WAYLAND_SOCKET:/run/user/1000/wayland-0:ro")
    PODMAN_EXTRA_ARGS+=(-e "XDG_RUNTIME_DIR=/run/user/1000")
    PODMAN_EXTRA_ARGS+=(-e "WAYLAND_DISPLAY=wayland-0")
    
    # Wymusza natywny Wayland dla aplikacji opartych na Electron/Chromium (Ozone)
    PODMAN_EXTRA_ARGS+=(-e "ELECTRON_OZONE_PLATFORM_HINT=auto")
else
    # === Tryb X11 (Fallback) ===
    xhost +local:podman > /dev/null 2>&1 || true
    PODMAN_EXTRA_ARGS+=(-v "/tmp/.X11-unix:/tmp/.X11-unix:ro")
    PODMAN_EXTRA_ARGS+=(-e "DISPLAY=$DISPLAY")

    # Wyświetlamy ostrzeżenie TYLKO raz, krótko i na temat.
    echo "⚠️  X11: brak izolacji okien. Zalecamy Wayland lub osobne konto (README → U1/U2)."
fi
