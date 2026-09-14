# ==============================================================================
# Containerfile - Wieloprofilowy obraz deweloperski Sandboxa
# ==============================================================================
# Architektura Multi-Stage: jeden plik, wiele profili.
# Budowanie wybranego profilu: podman build --target <profil> -t sandbox-<profil> .
#
# Dostępne profile:
#   base    → Czyste IDE Antigravity (bez żadnych dodatkowych narzędzi)
#   mcp     → base + Node.js runtime (Google Cloud MCP)
#   gamedev → base + Godot Engine
#
# Każdy profil dziedziczy WSZYSTKO z bazy (X11, Chrome, Python3, proxy, user).

# ==============================================================================
# BAZA — wspólna dla WSZYSTKICH profili
# ==============================================================================
FROM ubuntu:22.04 AS base

# Wyłączamy interaktywne zapytania podczas instalacji pakietów
ENV DEBIAN_FRONTEND=noninteractive

# --- Zależności Systemowe i GUI ---
# Pakiety do obsługi grafiki (X11, Mesa 3D), certyfikaty SSL,
# narzędzia deweloperskie oraz Google Chrome (do logowania OAuth).
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    git \
    python3 \
    tmux \
    ca-certificates \
    unzip \
    libx11-6 \
    libxcursor1 \
    libxinerama1 \
    libxrandr2 \
    libxi6 \
    libgl1-mesa-dev \
    libgl1-mesa-glx \
    mesa-utils \
    libxext6 \
    libxrender1 \
    libxtst6 \
    libxss1 \
    libasound2 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libgbm1 \
    libxkbfile1 \
    dbus-x11 \
    xdg-utils \
    && wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get install -y ./google-chrome-stable_current_amd64.deb \
    && rm google-chrome-stable_current_amd64.deb \
    && rm -rf /var/lib/apt/lists/*

# Chrome wrapper (--no-sandbox wymagany w kontenerze)
RUN mv /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.orig && \
    echo '#!/bin/bash\nexec /usr/bin/google-chrome-stable.orig --no-sandbox "$@"' > /usr/bin/google-chrome-stable && \
    chmod +x /usr/bin/google-chrome-stable

# --- Bezpieczeństwo i uprawnienia (Rootless Agent) ---
# Użytkownik z UID/GID=1000, mapowany na hosta przez --userns keep-id.
RUN groupadd -g 1000 agent && \
    useradd -u 1000 -g agent -s /bin/bash -m agent

# --- Ustawienia Środowiska (Antigravity IDE) ---
# Wrapper dla komendy 'antigravity-ide' z flagą --no-sandbox
RUN echo '#!/bin/bash\nexec /opt/antigravity/antigravity-ide --no-sandbox "$@"' > /usr/local/bin/antigravity-ide && \
    chmod +x /usr/local/bin/antigravity-ide

# Tworzymy struktury katalogów dla haków startowych i końcowych
# Konwencja numeracji w startup.d/ i shutdown.d/:
# 00-09 - Zarezerwowane dla systemu
# 10-49 - Usługi bazowe
# 50-89 - Rozszerzenia społeczności (np. bazy danych, serwery WWW)
# 90-99 - Aplikacje końcowe (np. IDE uruchamiane na końcu)
RUN mkdir -p /usr/local/bin/startup.d /usr/local/bin/shutdown.d

# --- Skrypt startowy agenta ---
COPY .containerfile/start-agent.sh /usr/local/bin/start-agent.sh
RUN chmod +x /usr/local/bin/start-agent.sh

# Kopiowanie skryptów z profilu base (Mirror Pattern)
COPY .containerfile/base/bin/ /usr/local/bin/
RUN chmod -R +x /usr/local/bin/

ENV PATH="/usr/local/bin:/opt/antigravity:${PATH}"
ENV HOME=/home/agent

# Tworzymy krytyczne katalogi, aby Podman nie tworzył ich jako root
RUN mkdir -p /home/agent/.config /home/agent/.local && \
    chown -R agent:agent /home/agent/.config /home/agent/.local

# Przełączamy na zwykłego użytkownika
USER agent
WORKDIR /workspace

# Tworzymy symlink Złotego Mostu w katalogu domowym
RUN ln -s /workspace /home/agent/workspace

# --- Konfiguracja Proxy Egress ---
# UWAGA: Zmienne proxy (http_proxy, https_proxy) NIE są ustawiane tutaj.
# Są wstrzykiwane wyłącznie w runtime przez 'podman run -e' w run-sandbox.sh.
# Dzięki temu profile mogą swobodnie używać apt-get/wget podczas budowania
# bez konieczności obchodzenia proxy, które nie istnieje w czasie budowy.

ENV ELECTRON_NO_SANDBOX=1

CMD ["/usr/local/bin/start-agent.sh"]

# ==============================================================================
# PROFIL: MCP — Google Cloud MCP (Node.js runtime, bez npm)
# ==============================================================================
# Dodaje TYLKO interpreter Node.js (bez menedżera pakietów npm).
# Wymagany przez serwery MCP, które są bundlowane z rozszerzeniem IDE.
# Komenda 'npm' NIE jest dostępna — agent nie może pobierać pakietów z rejestru.
FROM base AS mcp

USER root
RUN apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
USER agent

# ==============================================================================
# PROFIL: GameDev — Godot Engine
# ==============================================================================
# Dodaje silnik Godot do systemu. Wersję można zmienić poniżej.
FROM base AS gamedev

USER root

# Instalacja wsparcia audio: libpulse0 (klient PulseAudio) + libasound2-plugins (most ALSA→PulseAudio)
# Electron/Chromium szuka dźwięku przez ALSA — wtyczka przekierowuje go do PulseAudio przez socket hosta.
RUN apt-get update && apt-get install -y --no-install-recommends libpulse0 libasound2-plugins && rm -rf /var/lib/apt/lists/*

ARG GODOT_VERSION="4.7.1-stable"
RUN wget -q -O godot.zip \
    https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip \
    && unzip godot.zip \
    && mv Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
    && rm godot.zip

# Kopiowanie skryptów z profilu gamedev (Mirror Pattern)
COPY .containerfile/gamedev/bin/ /usr/local/bin/
RUN chmod -R +x /usr/local/bin/

USER agent
