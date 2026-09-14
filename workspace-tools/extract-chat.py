#!/usr/bin/env python3
# ==============================================================================
# extract-chat.py - Narzędzie do ekstrakcji czatu z surowych logów IDE
# ==============================================================================
# Ponieważ IDE w trybie bezpiecznym nie może wywołać okienka "Zapisz jako",
# ten skrypt czyta natywne transkrypty zapisywane przez Antigravity na dysku
# i zamienia je w czytelny plik Markdown.
# 
# Uruchomienie: python3 workspace-tools/extract-chat.py
# Alternatywnie: ./workspace-tools/extract-chat.py

import os
import json
import glob
from pathlib import Path

def main():
    # Szukamy katalogu z danymi względem lokalizacji samego skryptu
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    
    base_dir = project_root / "antigravity-userdata" / "gemini" / "antigravity-ide" / "brain"
    out_dir = project_root / "workspace"
    
    if not base_dir.exists():
        print(f"❌ Nie znaleziono folderu: {base_dir}")
        print("Upewnij się, że uruchamiasz skrypt w głównym folderze projektu (gdzie jest run-sandbox.sh).")
        return

    # Znajdź najnowszą konwersację
    conversations = []
    for conv_dir in base_dir.iterdir():
        if conv_dir.is_dir() and (conv_dir / ".system_generated/logs/transcript.jsonl").exists():
            # Sprawdź czas modyfikacji pliku z logami
            log_file = conv_dir / ".system_generated/logs/transcript.jsonl"
            mtime = log_file.stat().st_mtime
            conversations.append((mtime, conv_dir.name, log_file))

    if not conversations:
        print("❌ Nie znaleziono żadnych logów czatu (transcript.jsonl).")
        return

    # Sortuj po dacie (najnowsze na początku)
    conversations.sort(reverse=True, key=lambda x: x[0])
    _, latest_id, log_file = conversations[0]

    print(f"🔍 Znaleziono najnowszą konwersację: {latest_id}")
    
    out_dir.mkdir(exist_ok=True)
    out_file = out_dir / f"chat-export-{latest_id[:8]}.md"

    print(f"📝 Generowanie pliku: {out_file}")

    with open(log_file, "r", encoding="utf-8") as f_in, open(out_file, "w", encoding="utf-8") as f_out:
        f_out.write(f"# Chat Conversation\n\n")
        f_out.write(f"Note: _This is purely the output of the chat conversation and does not contain any raw data, codebase snippets, etc. used to generate the output._\n\n")

        for line in f_in:
            if not line.strip():
                continue
            
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            # Filtrujemy tylko to co ważne: to co napisał użytkownik i to co odpisał model
            if entry.get("status") != "DONE":
                continue
                
            step_type = entry.get("type")
            source = entry.get("source")
            content = entry.get("content", "").strip()
            
            import re
            
            # Helper do czyszczenia tagów <thought> z logów modelu
            def clean_thoughts(text):
                # Usuwa <ctrl94>thought ... <ctrl95> lub <thought> ... </thought> (w tym ze znakami nowej linii)
                text = re.sub(r'<ctrl94>thought.*?<ctrl95>', '', text, flags=re.DOTALL)
                text = re.sub(r'<thought>.*?</thought>', '', text, flags=re.DOTALL)
                return text.strip()

            if step_type == "USER_INPUT":
                f_out.write(f"## User Input\n\n{content}\n\n")
            elif step_type == "PLANNER_RESPONSE":
                clean_content = clean_thoughts(content)
                if clean_content:
                    f_out.write(f"## Planner Response\n\n{clean_content}\n\n")
            elif step_type == "VIEW_FILE" and source == "MODEL":
                f_out.write(f"*Viewed a file*\n\n")
            elif step_type == "CODE_ACTION" and source == "MODEL":
                f_out.write(f"*Edited relevant file*\n\n")
            elif step_type == "RUN_COMMAND" and source == "MODEL":
                f_out.write(f"*Ran a command in terminal*\n\n")
            elif step_type == "LIST_DIRECTORY" and source == "MODEL":
                f_out.write(f"*Listed a directory*\n\n")
            elif step_type == "GREP_SEARCH" and source == "MODEL":
                f_out.write(f"*Searched files*\n\n")

    print(f"✅ Gotowe! Plik zapisany w: {out_file}")
    print("Teraz możesz po prostu uruchomić ./tools/sync-from-u2.sh aby wyciągnąć go na ten komputer.")

if __name__ == "__main__":
    main()
