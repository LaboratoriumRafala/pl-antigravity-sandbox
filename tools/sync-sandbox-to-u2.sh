#!/bin/bash
# ==============================================================================
# sync-sandbox-to-u2.sh - Bezpieczna synchronizacja kodu na konto U2
# ==============================================================================
# Ten skrypt kopiuje TYLKO pliki źródłowe projektu (skrypty, Containerfile, proxy)
# na konto U2, BEZ nadpisywania danych persystentnych IDE (loginy, historia, 
# ustawienia) ani plików roboczych agenta. 
# Dzięki temu nie musisz logować się ponownie po każdej zmianie.
#
# Użycie (jako U1):
#   ./tools/sync-sandbox-to-u2.sh

# Auto-wykrywanie ścieżki projektu (działa niezależnie skąd uruchomisz skrypt)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Ładowanie konfiguracji
CONFIG_FILE="$SCRIPT_DIR/settings.sh"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Brak pliku konfiguracyjnego: tools/settings.sh"
    echo ""
    echo "   Przed pierwszym użyciem skopiuj szablon i uzupełnij swoje dane:"
    echo "   cp tools/settings.sh.example tools/settings.sh"
    echo ""
    echo "   Szczegóły znajdziesz w README.md (sekcja 'Instrukcja Krok po Kroku')."
    exit 1
fi
source "$CONFIG_FILE"

SOURCE="$PROJECT_ROOT"

echo "🔄 Synchronizacja kodu do U2 ($U2_USER)..."

# Kopiujemy TYLKO pliki konfiguracyjne projektu, NIE dane persystentne.
# --delete usuwa z U2 pliki, których nie ma na U1, ALE wykluczenia chronią:
#   antigravity-userdata/ → loginy, historia czatów, wtyczki (istnieje TYLKO na U2)
#   workspace/            → projekty agenta (istnieje TYLKO na U2)
#   Antigravity IDE/      → binarka IDE (zarządzana osobno na U2)
#   tmp/                  → tymczasowe logi diagnostyczne (folder lokalny U1)
sudo rsync -av --delete \
    --exclude='antigravity-userdata' \
    --exclude='workspace' \
    --exclude='Antigravity IDE' \
    --exclude='.agents' \
    --exclude='tools' \
    --exclude='tmp' \
    --exclude='.git' \
    "$SOURCE/" "$DEST/"

# Ustawiamy właściciela TYLKO na skopiowanych plikach (nie na danych persystentnych).
# Używamy find zamiast chown -R, by nie skanować tysięcy plików w antigravity-userdata/.
sudo find "$DEST/" -maxdepth 1 -not -path "$DEST/antigravity-userdata" \
                                -not -path "$DEST/workspace" \
                                -not -path "$DEST/Antigravity IDE" \
                                -not -path "$DEST/" \
                                -exec chown -R "$U2_USER:$U2_USER" {} +

# Nadajemy własność samemu katalogowi głównemu (rsync kopiuje własność z U1)
sudo chown "$U2_USER:$U2_USER" "$DEST"

# Upewniamy się, że workspace/ i antigravity-userdata/ istnieją i należą do U2
sudo mkdir -p "$DEST/workspace" "$DEST/antigravity-userdata"
sudo chown "$U2_USER:$U2_USER" "$DEST/workspace" "$DEST/antigravity-userdata"

echo "✅ Synchronizacja zakończona."
echo "   Dane logowania i historia czatów NIE zostały nadpisane."
echo "   Folder workspace/ jest gotowy do pracy."
