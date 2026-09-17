#!/bin/bash
# ==============================================================================
# run-sandbox.sh - Skrypt uruchomieniowy izolowanego Sandboxa
# ==============================================================================
# Ten skrypt orkiestruje uruchomienie wyizolowanego środowiska Podman.
# Tworzy niezbędne sieci (w tym odciętą od internetu 'sandbox-internal'),
# podnosi serwer Proxy Strażnika, buduje obraz deweloperski i ostatecznie
# uruchamia środowisko agenta, przekazując mu odpowiednie zasoby (Karta Graficzna, Ekran).
#
# Użycie:
#   ./run-sandbox.sh                          → profil: base (czyste IDE)
#   ./run-sandbox.sh --profile mcp            → profil: mcp (Google Cloud MCP)
#   ./run-sandbox.sh --profile gamedev        → profil: gamedev (Godot Engine)
#   ./run-sandbox.sh --profile mcp --rebuild  → wymusza przebudowę obrazu kontenera dla wybranego profilu od zera
#
# Skrót: symlink z nazwą profilu (autodetekcja z argv[0]):
#   ln -s run-sandbox.sh run-sandbox-gamedev.sh
#   ./run-sandbox-gamedev.sh                  → profil: gamedev (bez flagi!)
#   ./run-sandbox-gamedev.sh --profile mcp    → profil: mcp (flaga nadpisuje nazwę)
#
# WAŻNE: Agent wewnątrz kontenera widzi TYLKO:
#   /workspace/          → folder workspace/ (z prawem zapisu — tu tworzy gry i kod)
#   /opt/antigravity/    → pliki IDE (TYLKO DO ODCZYTU — agent nie może ich podmienić)
#   /home/agent/.gemini/ → dane AI, historia czatów (z prawem zapisu)
#
# Wszystkie persystentne dane IDE (loginy, rozszerzenia, historia) są
# przechowywane w jednym folderze antigravity-userdata/ na hoście.
#
# Agent NIE WIDZI: run-sandbox.sh, Containerfile, proxy/, PRZEWODNIK.md

set -e # Przerwij działanie w przypadku błędu

# ==============================================================================
# Weryfikacja środowiska hosta (Pre-flight checks)
# ==============================================================================
if ! command -v podman &> /dev/null; then
    echo "❌ Błąd: Podman nie jest zainstalowany na tym systemie."
    echo "   Zainstaluj go komendą dla swojej dystrybucji (np. sudo apt install podman)."
    exit 1
fi

# ==============================================================================
# Obsługa argumentów skryptu
# ==============================================================================
# --profile <nazwa> : Wybór profilu środowiska (base, mcp, gamedev).
#                     Domyślnie: base (czyste IDE bez żadnych dodatków).
# --rebuild         : Wymusza przebudowanie obrazu kontenera od zera (bez cache).
#                     Użyj gdy zmienisz Containerfile i chcesz mieć pewność,
#                     że Podman nie użyje starych warstw z pamięci.
PROFILE="base"

# Autodetekcja profilu z nazwy skryptu (wzorzec argv[0])
# Jeśli skrypt nazywa się run-sandbox-gamedev.sh → profil = gamedev
# Flaga --profile ma wyższy priorytet i nadpisuje tę wartość
SCRIPT_NAME=$(basename "$0" .sh)
if [[ "$SCRIPT_NAME" =~ ^run-sandbox-(.+)$ ]]; then
    PROFILE="${BASH_REMATCH[1]}"
fi

BUILD_FLAGS=""
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --rebuild)
            BUILD_FLAGS="--no-cache"
            echo "⚠️  Tryb przebudowy: obraz zostanie zbudowany od zera (bez cache)."
            shift
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

# Walidacja profilu
case "$PROFILE" in
    base|mcp|gamedev) ;;
    *)
        echo "❌ Nieznany profil: $PROFILE"
        echo "   Dostępne profile: base, mcp, gamedev"
        exit 1
        ;;
esac

# ==============================================================================
# 0. Identyfikator projektu (unikalne nazwy kontenerów i sieci)
# ==============================================================================
# Nazwa folderu, w którym leży ten sandbox, staje się prefixem/sufixem
# dla nazw sieci i kontenerów. Dzięki temu możesz uruchamiać wiele
# sandboxów równolegle bez konfliktów nazw.
PROJECT_ID=$(basename "$(pwd)")

NETWORK_EXT="sandbox-external-${PROJECT_ID}"
NETWORK_INT="sandbox-internal-${PROJECT_ID}"
CONTAINER_PROXY="proxy-${PROJECT_ID}"
CONTAINER_SANDBOX="sandbox-${PROJECT_ID}"

# ==============================================================================
# 1. Automatyczne czyszczenie po zamknięciu (trap)
# ==============================================================================
# Gdy wyjdziesz z sandboxa (wpisując 'exit' lub Ctrl+D), ta funkcja
# automatycznie zatrzyma kontener proxy i posprząta po sobie.
cleanup() {
    echo ""
    echo "🧹 Czyszczenie po zakończeniu sesji..."
    echo "[1/6] Zatrzymywanie kontenera sieciowego ($CONTAINER_PROXY)..."
    podman stop "$CONTAINER_PROXY" >/dev/null 2>&1 || true
    echo "[2/6] Usuwanie kontenera sieciowego ($CONTAINER_PROXY)..."
    podman rm "$CONTAINER_PROXY" >/dev/null 2>&1 || true
    echo "[3/6] Usuwanie kontenera roboczego ($CONTAINER_SANDBOX)..."
    podman rm "$CONTAINER_SANDBOX" >/dev/null 2>&1 || true
    echo "[4/6] Usuwanie sieci wewnętrznej ($NETWORK_INT)..."
    podman network rm "$NETWORK_INT" >/dev/null 2>&1 || true
    echo "[5/6] Usuwanie sieci zewnętrznej ($NETWORK_EXT)..."
    podman network rm "$NETWORK_EXT" >/dev/null 2>&1 || true
    
    # Cofnij uprawnienia X11 TYLKO jeśli żaden inny sandbox nie działa na tym hoście
    if ! podman ps --format "{{.Names}}" | grep -q "^sandbox-"; then
        echo "[6/6] Zamykanie dostępu do ekranu (xhost)..."
        xhost -local:podman >/dev/null 2>&1 || true
    else
        echo "[6/6] Pominięcie blokady ekranu (inne sandboxy wciąż pracują)..."
    fi
    
    echo "✅ Środowisko zamknięte. Pliki projektów (workspace/) są bezpieczne."
}
trap cleanup EXIT

echo "🚀 Inicjalizacja środowiska Sandbox..."
echo "📋 Profil: $PROFILE | Projekt: $PROJECT_ID"

# ==============================================================================
# 1. Przygotowanie struktury katalogów
# ==============================================================================
# antigravity-userdata/ — jeden folder przechowujący CAŁY persystentny stan IDE:
#   gemini/      → dane AI (historia czatów, serwer językowy)
#   ide-config/  → rozszerzenia IDE, ustawienia argv.json
#   ide-server/  → dane runtime serwera IDE
#   config/      → ustawienia UI (settings.json, rozmiary paneli, motywy)
#
# workspace/ — folder roboczy agenta (jedyne miejsce z prawem zapisu na projekty).
if [ ! -d "antigravity-userdata" ]; then
    echo "📁 Tworzenie folderu danych użytkownika (antigravity-userdata/)..."
fi
mkdir -p antigravity-userdata/gemini/antigravity
mkdir -p antigravity-userdata/gemini/antigravity-ide
mkdir -p antigravity-userdata/ide-config
mkdir -p antigravity-userdata/ide-server
mkdir -p antigravity-userdata/config
mkdir -p "antigravity-userdata/profile-${PROFILE}-local"

if [ ! -d "workspace" ]; then
    echo "📁 Tworzenie folderu roboczego agenta (workspace/)..."
fi
mkdir -p workspace

# ==============================================================================
# 2. Generowanie białej listy domen (Whitelist)
# ==============================================================================
# Łączymy whitelist-base.txt z dodatkową listą profilu (jeśli istnieje).
# Wynikowy plik proxy/whitelist.txt jest ładowany przez Squida.
echo "🔗 Generowanie białej listy domen (profil: $PROFILE)..."
cat proxy/whitelist-base.txt > proxy/whitelist.txt
if [ "$PROFILE" != "base" ] && [ -f "proxy/whitelist-${PROFILE}.txt" ]; then
    echo "" >> proxy/whitelist.txt
    echo "# === Domeny dodatkowe: profil ${PROFILE} ===" >> proxy/whitelist.txt
    cat "proxy/whitelist-${PROFILE}.txt" >> proxy/whitelist.txt
fi

# ==============================================================================
# 3. Konfiguracja Izolowanych Sieci (Network Namespaces)
# ==============================================================================
# Tworzymy dwie sieci w Podmanie:
#   $NETWORK_EXT → ma dostęp do internetu (TYLKO dla proxy/strażnika)
#   $NETWORK_INT → odcięta od internetu flagą --internal (dla agenta)
podman network exists "$NETWORK_EXT" 2>/dev/null || podman network create "$NETWORK_EXT" > /dev/null
# --internal to flaga "Bank-Grade" - fizycznie odcina sieć od wyjścia na świat
# --disable-dns wyłącza serwer Aardvark DNS na bramce sieci. Bez tego agent
# mógłby ręcznie odpytać bramkę (10.89.x.1:53) surowym pakietem UDP i wynieść
# dane przez DNS Tunneling. Z tą flagą bramka w ogóle nie nasłuchuje na porcie 53.
podman network exists "$NETWORK_INT" 2>/dev/null || podman network create --internal --disable-dns "$NETWORK_INT" > /dev/null

# ==============================================================================
# 4. Uruchomienie Strażnika (Proxy Squid)
# ==============================================================================
# Sprawdzamy czy strażnik działa. Jeśli nie, uruchamiamy lekki kontener Alpine.
# Strażnik jest podpięty do DWÓCH sieci: wewnętrznej i zewnętrznej.
# Dzięki temu jest jedynym mostem między agentem a internetem.
if ! podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_PROXY}$"; then
    echo "🛡️  Uruchamianie serwera Proxy (Strażnik)..."
    # WAŻNE: Montujemy naszą konfigurację do /config/ (NIE do /etc/squid/), ponieważ
    # instalator Squida (apk) musi zapisać swoje domyślne pliki do /etc/squid/.
    # Po instalacji kopiujemy naszą konfigurację na właściwe miejsce.
    podman run -d --name "$CONTAINER_PROXY" --replace \
        --network "$NETWORK_EXT" \
        --network "$NETWORK_INT" \
        -v "$(pwd)/proxy":/config:ro,Z \
        docker.io/library/alpine:latest \
        sh -c "apk add --no-cache squid && cp /config/squid.conf /etc/squid/squid.conf && cp /config/whitelist.txt /etc/squid/whitelist.txt && squid -N -f /etc/squid/squid.conf" > /dev/null

    # Czekamy, aż Squid faktycznie zacznie nasłuchiwać na porcie 3128.
    # Bez tego sandbox mógłby się uruchomić zanim proxy jest gotowe.
    echo -n "   Oczekiwanie na gotowość Strażnika "
    PROXY_READY=false
    for i in $(seq 1 20); do
        # Używamy nc (netcat) z Alpine do cichego sprawdzenia portu
        if podman exec "$CONTAINER_PROXY" nc -z 127.0.0.1 3128 2>/dev/null; then
            PROXY_READY=true
            break
        fi
        echo -n "[${i}] "
        sleep 2
    done

    if [ "$PROXY_READY" = true ]; then
        echo "✅ Gotowy!"
    else
        echo ""
        echo "❌ BŁĄD: Strażnik proxy nie odpowiedział w ciągu 40s."
        echo "   Sandbox BEZ proxy nie jest sandboxem — uruchamianie przerwane."
        echo "   Sprawdź logi: podman logs $CONTAINER_PROXY"
        exit 1
    fi
else
    echo "✅ Strażnik już działa."
fi

# ==============================================================================
# Pobieranie adresu IP proxy (Ślepota DNS)
# ==============================================================================
# Pobieramy fizyczny adres IP serwera Proxy w sieci wewnętrznej.
# Jest to niezbędne, abyśmy mogli wyłączyć rozwiązywanie nazw (DNS) w kontenerze
# agenta (--dns none), chroniąc go przed atakami typu DNS Tunneling.
PROXY_IP=$(podman inspect -f '{{(index .NetworkSettings.Networks "'"${NETWORK_INT}"'").IPAddress}}' "$CONTAINER_PROXY" 2>/dev/null)

if [ -z "$PROXY_IP" ]; then
    echo "❌ BŁĄD: Nie udało się pobrać adresu IP proxy ($CONTAINER_PROXY) w sieci $NETWORK_INT."
    echo "   Sprawdź, czy kontener proxy działa: podman ps"
    exit 1
fi

# ==============================================================================
# 5. Budowanie obrazu dla wybranego profilu
# ==============================================================================
echo "🏗️  Budowanie obrazu (profil: $PROFILE)..."
echo "   (Zbuduje się tylko raz lub gdy zmienisz Containerfile)"
# --target wybiera odpowiedni stage z Containerfile (base, mcp, gamedev).
# Każdy profil dziedziczy bazę, więc cache bazy jest współdzielony.
podman build $BUILD_FLAGS --target "$PROFILE" -t "sandbox-$PROFILE" .

# ==============================================================================
# 6. Uruchomienie Sandboxa
# ==============================================================================
echo ""
echo ""
echo "🎮 Uruchamianie środowiska Sandbox (profil: $PROFILE)..."
echo ""

# Wyjaśnienie flag Podmana:
# --rm                            : Usuń kontener po wyłączeniu (czyste środowisko za każdym razem)
# --network $NETWORK_INT          : Podepnij TYLKO do sieci bez dostępu do internetu
# --shm-size=1g                   : Zwiększ pamięć współdzieloną do 1GB (zapobiega crashom Electrona/GUI)
# --security-opt=no-new-privileges: Zablokuj eskalację uprawnień (np. setuid)
# --device /dev/dri               : Przekaż kartę graficzną (GPU) dla Godota
# -v workspace:/workspace:Z       : Folder roboczy agenta (JEDYNE miejsce z prawem zapisu)
# -v Antigravity IDE:ro           : Pliki IDE (TYLKO DO ODCZYTU — agent nie może podmienić)
# -v antigravity-userdata/*       : Dane persystentne IDE (z prawem zapisu)
# --userns keep-id:uid=1000,gid=1000 : Mapuj hosta na agenta (UID 1000) w kontenerze
#
# Serwer graficzny (X11/Wayland) jest konfigurowany przez drop-in:
#   .run-sandbox.d/base/10-display.sh
#
# UWAGA: Nie używamy --cap-drop=ALL, ponieważ IDE (Electron) i jego Agent AI
# wymagają standardowych capabilities do tworzenia pseudoterminali (pty),
# zarządzania procesami i komunikacji międzyprocesowej. Izolacja kontenera
# (namespace + no-new-privileges + Squid proxy) jest wystarczająca.


PODMAN_EXTRA_ARGS=()

# Ładowanie konfiguracji hosta z katalogu drop-in
# Najpierw base/*.sh (wspólne dla wszystkich), potem <profil>/*.sh (specyficzne)
for host_config in .run-sandbox.d/base/*.sh \
                   .run-sandbox.d/"$PROFILE"/*.sh; do
    [ -f "$host_config" ] || continue
    source "$host_config"
done

podman run -it --rm --name "$CONTAINER_SANDBOX" \
    --network "$NETWORK_INT" \
    --shm-size=1g \
    --hostname "$PROJECT_ID" \
    --dns none \
    --security-opt=no-new-privileges \
    -e GTK_USE_PORTAL=0 \
    -e ELECTRON_NO_SANDBOX=1 \
    -e SANDBOX_PROFILE="$PROFILE" \
    -e DCONF_PROFILE=/dev/null \
    -e http_proxy="http://${PROXY_IP}:3128" \
    -e https_proxy="http://${PROXY_IP}:3128" \
    -e HTTP_PROXY="http://${PROXY_IP}:3128" \
    -e HTTPS_PROXY="http://${PROXY_IP}:3128" \
    -e no_proxy="localhost,127.0.0.1" \
    -v "$(pwd)/workspace":/workspace:Z \
    -v "$(pwd)/Antigravity IDE":/opt/antigravity:ro,Z \
    -v "$(pwd)/antigravity-userdata/gemini":/home/agent/.gemini:Z \
    -v "$(pwd)/antigravity-userdata/ide-config":/home/agent/.antigravity-ide:Z \
    -v "$(pwd)/antigravity-userdata/ide-server":/home/agent/.antigravity-ide-server:Z \
    -v "$(pwd)/antigravity-userdata/config":/home/agent/.config:Z \
    -v "$(pwd)/antigravity-userdata/profile-${PROFILE}-local":/home/agent/.local:Z \
    --userns keep-id:uid=1000,gid=1000 \
    "${PODMAN_EXTRA_ARGS[@]}" \
    "sandbox-$PROFILE" \
    "${ARGS[@]}"
