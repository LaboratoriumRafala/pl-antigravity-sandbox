#!/bin/bash
# ==============================================================================
# start-agent.sh - Główny proces (PID 1) wewnątrz kontenera Sandbox
# ==============================================================================

graceful_shutdown() {
    echo ""
    echo "🔒 Zamykanie środowiska..."
    
    if [ -d /usr/local/bin/shutdown.d ]; then
        # Wykonaj skrypty w odwrotnej kolejności (odporne na spacje w nazwach)
        # Dzięki temu to co uruchomiło się na końcu, zamyka się pierwsze
        shopt -s nullglob
        hooks=(/usr/local/bin/shutdown.d/*.sh)
        for ((i=${#hooks[@]}-1; i>=0; i--)); do
            hook="${hooks[$i]}"
            [ -f "$hook" ] || continue
            echo "   Wykonuję hak zamykający: $(basename "$hook")"
            "$hook"
        done
        shopt -u nullglob
    fi
    
    echo "✅ Zakończono. Możesz bezpiecznie zamknąć terminal."
}
trap graceful_shutdown EXIT



echo "🚀 Ładowanie wtyczek startowych..."
if [ -d /usr/local/bin/startup.d ]; then
    shopt -s nullglob
    for hook in /usr/local/bin/startup.d/*.sh; do
        [ -f "$hook" ] || continue
        echo "   Uruchamiam: $(basename "$hook")"
        "$hook"
    done
    shopt -u nullglob
fi

echo ""
if [ -d /usr/local/bin/help.d ]; then
    echo "🛠️  Dostępne podręczne komendy:"
    shopt -s nullglob
    for helpfile in /usr/local/bin/help.d/*.txt; do
        [ -f "$helpfile" ] || continue
        cat "$helpfile"
    done
    shopt -u nullglob
    echo ""
fi

echo "🎮 Możesz teraz bezpiecznie pracować w tym terminalu lub uruchomić tmux."
echo "🔒 Aby zamknąć środowisko i zapisać dane, wpisz 'exit' lub naciśnij [Ctrl+D]."
echo ""
echo "⚠️  WAŻNE: Zapisuj projekty i pliki WYŁĄCZNIE w folderze ~/workspace"
echo "   Wszystko co zapiszesz w innych miejscach katalogu domowego ZNIKNIE po restarcie!"
echo ""
# Konfiguracja prompta z widoczną nazwą profilu
# Dopisujemy to do .bashrc, by nie tracić domyślnych aliasów Ubuntu (np. ll, kolorowe ls)
echo "export PS1='\u@\h(\$SANDBOX_PROFILE):\w\$ '" >> ~/.bashrc

# Pozostawienie terminala interaktywnego (załaduje .bashrc)
/bin/bash

