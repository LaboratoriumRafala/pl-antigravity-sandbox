#!/bin/bash
set -euo pipefail

# ==============================================================================
# sync-from-u2.sh — "Śluza Powietrzna" v2.0 (Enterprise/Bank-Grade)
# ==============================================================================
# Użycie 1 (domyślny projekt): ./tools/sync-workspace-from-u2.sh
# Użycie 2 (inny projekt):      ./tools/sync-workspace-from-u2.sh nazwa-projektu
# Użycie 3 (z auto-mergem):     ./tools/sync-workspace-from-u2.sh [nazwa-projektu] --auto

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

U1_STAGE="$U1_WORKSPACE"

BUNDLE_FILE="/tmp/sandbox-git-bundle-$$.bundle"
SYNC_MARKER="$U1_STAGE/.last-sync-from-u2"

trap 'rm -f "$BUNDLE_FILE"' EXIT

# NSA Standard: Domyślnie wszystkie nowe pliki tworzone przez ten skrypt na Twoim koncie będą prywatne
umask 077

echo "🔒 Śluza Powietrzna — bezpieczny transfer commitów z U2 → U1"
echo "   Źródło (U2): $U2_WORKSPACE"
echo "   Cel (U1):    $U1_STAGE"
echo ""

# ── Walidacja 1: Sprawdzenie czy U2 ma w ogóle Gita ──
if ! sudo -u "$U2_USER" git -C "$U2_WORKSPACE" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "❌ BŁĄD: Brak repozytorium Git w przestrzeni Agenta na U2 ($U2_WORKSPACE)."
    echo "   Agent (lub Ty) musi najpierw wykonać 'git init'."
    exit 1
fi

# ── Walidacja 2: Sprawdzenie pustego repo (Ochrona przed crashem Basha) ──
if ! sudo -u "$U2_USER" git -C "$U2_WORKSPACE" rev-parse HEAD &>/dev/null; then
    echo "❌ BŁĄD: Repozytorium Agenta jest całkowicie puste (brak commitów)."
    echo "   Agent musi stworzyć pierwszy commit (np. git commit -m 'Initial commit')."
    exit 1
fi

U2_HEAD=$(sudo -u "$U2_USER" git -C "$U2_WORKSPACE" rev-parse HEAD)
echo "📊 Stan repozytorium U2: Gotowe do transferu (HEAD: ${U2_HEAD:0:8})"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# PRZYPADEK 1: Pierwsze uruchomienie (Brak folderu na U1)
# ══════════════════════════════════════════════════════════════════════════════
if [ ! -d "$U1_STAGE/.git" ]; then
    echo "📦 Pierwsze uruchomienie — tworzę pełny klon historii U2..."
    
    # Tworzymy pełną paczkę ze WSZYSTKICH gałęzi (NSA Standard: umask 077 zapewnia prywatność w /tmp)
    sudo -u "$U2_USER" bash -c "umask 077 && git -C '$U2_WORKSPACE' bundle create '$BUNDLE_FILE' --all"
    sudo chown "$(id -un):$(id -gn)" "$BUNDLE_FILE"
    
    # Bezpieczne klonowanie (nie wyciszamy błędów, jeśli folder nie jest pusty!)
    mkdir -p "$U1_STAGE"
    git clone "$BUNDLE_FILE" "$U1_STAGE"
    
    cd "$U1_STAGE"
    git remote remove origin || true
    echo "$U2_HEAD" > "$SYNC_MARKER"
    
    echo ""
    echo "✅ SUKCES: Pełna historia Agenta została sklonowana do U1!"
    echo "   Możesz teraz otworzyć folder $U1_STAGE w VS Code."
    echo "   (Pamiętaj by z terminala dodać GitHuba: git remote add origin ...)"
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# PRZYPADEK 2: Kolejne uruchomienie (Inkrementalny update)
# ══════════════════════════════════════════════════════════════════════════════
LAST_SYNC=""
if [ -f "$SYNC_MARKER" ]; then
    LAST_SYNC=$(cat "$SYNC_MARKER")
fi

echo "📦 Inkrementalna synchronizacja historii..."

if [ -n "$LAST_SYNC" ]; then
    # Najpierw sprawdzamy, czy w ogóle są nowe commity do pobrania.
    # Używamy rev-list z --count, żeby nie chować błędów 'bundle create'
    NEW_COMMITS=$(sudo -u "$U2_USER" git -C "$U2_WORKSPACE" rev-list ^"$LAST_SYNC" --all --count 2>/dev/null || echo "0")
    if [ "$NEW_COMMITS" -eq 0 ]; then
        echo "✅ Brak nowych commitów na U2. Twoje środowisko U1 jest całkowicie zsynchronizowane."
        exit 0
    fi

    echo "📦 Znalazłem $NEW_COMMITS nowych commitów! Pakuję..."
    sudo -u "$U2_USER" bash -c "umask 077 && git -C '$U2_WORKSPACE' bundle create '$BUNDLE_FILE' --all ^'$LAST_SYNC'"
else
    # Fallback, gdy usunięto marker
    sudo -u "$U2_USER" bash -c "umask 077 && git -C '$U2_WORKSPACE' bundle create '$BUNDLE_FILE' --all"
fi

sudo chown "$(id -un):$(id -gn)" "$BUNDLE_FILE"

cd "$U1_STAGE"

# ── Rozwiązanie WTOPY 4 i 5 (Nie mieszamy w gałęziach U1 na ślepo) ──
echo "📥 Wczytywanie commitów Agenta do bezpiecznych gałęzi podglądu (u2/*)..."
# Wciągamy gałęzie U2 do przestrzeni refs/remotes/u2 (podobnie jak robi się git fetch origin)
git fetch "$BUNDLE_FILE" '+refs/heads/*:refs/remotes/u2/*'

echo "$U2_HEAD" > "$SYNC_MARKER"

echo ""
echo "✅ SUKCES: Zsynchronizowano nowe zmiany Agenta!"
echo ""
U2_CURRENT_BRANCH=$(sudo -u "$U2_USER" git -C "$U2_WORKSPACE" rev-parse --abbrev-ref HEAD)

if [ "$AUTO_MERGE" -eq 1 ]; then
    LOCAL_BRANCH=$(git -C "$U1_STAGE" rev-parse --abbrev-ref HEAD)
    if [ "$LOCAL_BRANCH" = "$U2_CURRENT_BRANCH" ]; then
        echo "🔀 Auto-merge: wciągam u2/$U2_CURRENT_BRANCH → $LOCAL_BRANCH..."
        if git -C "$U1_STAGE" merge "u2/$U2_CURRENT_BRANCH" --ff-only 2>/dev/null; then
            echo "✅ Merge zakończony! Twoja gałąź '$LOCAL_BRANCH' jest aktualna."
        else
            echo "⚠️  Fast-forward niemożliwy (masz lokalne zmiany na U1?)."
            echo "   Wciągnij ręcznie: cd $U1_STAGE && git merge u2/$U2_CURRENT_BRANCH"
        fi
    else
        echo "⚠️  Jesteś na gałęzi '$LOCAL_BRANCH', a Agent pracuje na '$U2_CURRENT_BRANCH'."
        echo "   Wciągnij ręcznie: cd $U1_STAGE && git merge u2/$U2_CURRENT_BRANCH"
    fi
else
    echo "💡 JAK Z TEGO KORZYSTAĆ (w VS Code lub terminalu):"
    echo "   1. Zobacz pobrane zmiany: git log --oneline --graph --all"
    echo "   2. Aby złączyć (wciągnąć) pracę Agenta do swojej gałęzi, wpisz:"
    echo "      git merge u2/$U2_CURRENT_BRANCH"
    echo "   (Praca Agenta bezpiecznie czeka w 'u2/$U2_CURRENT_BRANCH')"
    echo "   (Wskazówka: możesz dodać flagę --auto przy wywołaniu skryptu, aby zrobić to automatycznie)"
fi
