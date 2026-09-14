#!/bin/bash
# ==============================================================================
# Host Drop-in: PulseAudio (profil gamedev)
# ==============================================================================
# Przekazuje socket serwera dźwięku z hosta do kontenera.
# Umożliwia odtwarzanie dźwięku w grach (Godot) oraz powiadomienia IDE.
#
# UWAGA BEZPIECZEŃSTWA: Dostęp do socketu PulseAudio daje również
# teoretyczny dostęp do mikrofonu. Ryzyko jest neutralizowane przez
# filtr Squid (brak możliwości eksfiltracji nagrania).

echo "🔊 Włączono dostęp do dźwięku (PulseAudio) dla profilu gamedev."
PODMAN_EXTRA_ARGS+=("-v" "/run/user/$(id -u)/pulse/native:/run/user/1000/pulse/native")
PODMAN_EXTRA_ARGS+=("-e" "PULSE_SERVER=unix:/run/user/1000/pulse/native")
