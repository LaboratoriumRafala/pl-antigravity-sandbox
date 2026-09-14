#!/bin/bash
set -euo pipefail

# ==============================================================================
# sync-workspace-to-u2.sh — "Śluza Powietrzna - WLOT" (Air-Gap Git Transfer)
# ==============================================================================
# Opcjonalne argumenty z linii poleceń (z domyślnymi wartościami)
# Użycie 1 (domyślny projekt):  ./tools/sync-workspace-to-u2.sh
# Użycie 2 (inny projekt):      ./tools/sync-workspace-to-u2.sh nazwa-projektu
# Użycie 3 (z auto-mergem):     ./tools/sync-workspace-to-u2.sh [nazwa-projektu] --auto

# Auto-wykrywanie ścieżki projektu
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

AUTO_MERGE=0

for arg in "$@"; do
    if [ "$arg" = "--auto" ]; then
        AUTO_MERGE=1
    elif [[ "$arg" != -* ]]; then
        PROJECT_NAME="$arg"
    fi
done

# Odwrócone role w stosunku do wylotu
U2_STAGE="$U2_WORKSPACE"

BUNDLE_FILE="/tmp/sandbox-git-bundle-wlot-$$.bundle"
SYNC_MARKER="$U2_STAGE/.last-sync-from-u1"

trap 'rm -f "$BUNDLE_FILE"' EXIT

# NSA Standard: Domyślnie wszystkie nowe pliki w tym skrypcie będą dostępne TYLKO dla Ciebie
umask 077

echo "🔒 Śluza Powietrzna WLOTOWA — bezpieczny transfer commitów z U1 → U2"
echo "   Źródło (U1): $U1_WORKSPACE"
echo "   Cel (U2 Sandbox): $U2_STAGE"
echo ""

# ── Walidacja 1: Sprawdzenie czy U1 ma w ogóle Gita ──
if ! git -C "$U1_WORKSPACE" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "❌ BŁĄD: Brak repozytorium Git w Twoim folderze na U1 ($U1_WORKSPACE)."
    echo "   Musisz najpierw sklonować lub zainicjalizować tam projekt."
    exit 1
fi

# ── Walidacja 2: Sprawdzenie pustego repo ──
if ! git -C "$U1_WORKSPACE" rev-parse HEAD &>/dev/null; then
    echo "❌ BŁĄD: Twoje repozytorium na U1 jest całkowicie puste (brak commitów)."
    exit 1
fi

U1_HEAD=$(git -C "$U1_WORKSPACE" rev-parse HEAD)
echo "📊 Stan repozytorium U1: Gotowe do transferu (HEAD: ${U1_HEAD:0:8})"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# PRZYPADEK 1: Pierwsze uruchomienie wewnątrz Sandboxa
# ══════════════════════════════════════════════════════════════════════════════
if ! sudo -u "$U2_USER" test -d "$U2_STAGE/.git"; then
    echo "📦 Pierwsze przesyłanie do Sandboxa — tworzę pełny klon w U2..."
    
    # Tworzymy pełną paczkę jako U1
    git -C "$U1_WORKSPACE" bundle create "$BUNDLE_FILE" --all
    
    # NSA Standard: Plik jest prywatny (umask 077). Udostępniamy go TYLKO grupie U2.
    sudo chgrp "$U2_USER" "$BUNDLE_FILE"
    chmod g+r "$BUNDLE_FILE"
    
    # Tworzymy folder NADRZĘDNY, bo git clone nie lubi istniejących folderów docelowych
    sudo -u "$U2_USER" mkdir -p "$(dirname "$U2_STAGE")"
    sudo -u "$U2_USER" git clone "$BUNDLE_FILE" "$U2_STAGE"
    
    # Usuwamy origin z wnętrza sandboxa, by Agent nie używał bundle jako remota
    sudo -u "$U2_USER" git -C "$U2_STAGE" remote remove origin || true
    
    # Marker dla U2
    echo "$U1_HEAD" | sudo -u "$U2_USER" tee "$SYNC_MARKER" > /dev/null
    
    echo ""
    echo "✅ SUKCES: Projekt został bezpiecznie zaimportowany do Sandboxa!"
    echo "   Agent ma teraz dostęp do najnowszego kodu."
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# PRZYPADEK 2: Kolejne uruchomienie (Inkrementalny update do Sandboxa)
# ══════════════════════════════════════════════════════════════════════════════
LAST_SYNC=""
if sudo -u "$U2_USER" test -f "$SYNC_MARKER"; then
    LAST_SYNC=$(sudo -u "$U2_USER" cat "$SYNC_MARKER")
fi

echo "📦 Inkrementalna aktualizacja Sandboxa..."

if [ -n "$LAST_SYNC" ]; then
    # Sprawdzamy, czy są nowe commity
    NEW_COMMITS=$(git -C "$U1_WORKSPACE" rev-list ^"$LAST_SYNC" --all --count 2>/dev/null || echo "0")
    
    if [ "$NEW_COMMITS" -eq 0 ]; then
        echo "✅ Brak nowych commitów na U1. Sandbox jest całkowicie zsynchronizowany."
        exit 0
    fi

    echo "📦 Znalazłem $NEW_COMMITS nowych commitów! Pakuję..."
    git -C "$U1_WORKSPACE" bundle create "$BUNDLE_FILE" --all ^"$LAST_SYNC"
else
    # Fallback
    git -C "$U1_WORKSPACE" bundle create "$BUNDLE_FILE" --all
fi

# NSA Standard: Udostępnienie paczki wyłącznie grupie U2
sudo chgrp "$U2_USER" "$BUNDLE_FILE"
chmod g+r "$BUNDLE_FILE"

# Wciągnięcie commitów do wirtualnych gałęzi u1/* wewnątrz Sandboxa
echo "📥 Wczytywanie commitów U1 do bezpiecznych gałęzi w Sandboxie (u1/*)..."
sudo -u "$U2_USER" git -C "$U2_STAGE" fetch "$BUNDLE_FILE" '+refs/heads/*:refs/remotes/u1/*'

echo "$U1_HEAD" | sudo -u "$U2_USER" tee "$SYNC_MARKER" > /dev/null

echo ""
echo "✅ SUKCES: Nowe zmiany z U1 zostały pomyślnie załadowane do Sandboxa!"
echo ""
U1_CURRENT_BRANCH=$(git -C "$U1_WORKSPACE" rev-parse --abbrev-ref HEAD)

if [ "$AUTO_MERGE" -eq 1 ]; then
    LOCAL_BRANCH=$(sudo -u "$U2_USER" git -C "$U2_STAGE" rev-parse --abbrev-ref HEAD)
    if [ "$LOCAL_BRANCH" = "$U1_CURRENT_BRANCH" ]; then
        echo "🔀 Auto-merge: wciągam u1/$U1_CURRENT_BRANCH → $LOCAL_BRANCH (jako $U2_USER)..."
        if sudo -u "$U2_USER" git -C "$U2_STAGE" merge "u1/$U1_CURRENT_BRANCH" --ff-only 2>/dev/null; then
            echo "✅ Merge zakończony! Gałąź Agenta '$LOCAL_BRANCH' jest aktualna."
        else
            echo "⚠️  Fast-forward niemożliwy (Agent ma lokalne, niezatwierdzone zmiany?)."
            echo "   Agent musi wciągnąć to ręcznie w swoim terminalu: git merge u1/$U1_CURRENT_BRANCH"
        fi
    else
        echo "⚠️  Agent jest na gałęzi '$LOCAL_BRANCH', a Ty wysłałeś '$U1_CURRENT_BRANCH'."
        echo "   Agent musi wciągnąć to ręcznie w swoim terminalu: git merge u1/$U1_CURRENT_BRANCH"
    fi
else
    echo "💡 JAK AGENT MA Z TEGO KORZYSTAĆ:"
    echo "   Agent może wejść do terminala i wpisać:"
    echo "      git merge u1/$U1_CURRENT_BRANCH"
    echo "   aby połączyć Twoje zaktualizowane commity ze swoją gałęzią główną."
    echo "   (Wskazówka: możesz dodać flagę --auto przy wywołaniu skryptu, aby zrobić to automatycznie)"
fi
