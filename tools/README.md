# Narzędzia Administratora (Tryb Bank-Grade)

Ten folder zawiera skrypty przeznaczone **wyłącznie dla głównego konta (U1)**. 

Służą one do zarządzania środowiskiem w architekturze najwyższego bezpieczeństwa (tzw. Trybie Bank-Grade). Skrypty te pozwalają na synchronizację czystego środowiska (Sandboxa) na wyizolowane konto deweloperskie (U2), zachowując przy tym pełną separację danych wrażliwych.

**Dlaczego to jest ważne?**
Zabezpiecza to Twój główny system (U1) przed dostępem Agenta AI, a także chroni Twoje prywatne konfiguracje. Przy przenoszeniu plików, ten folder celowo **zostaje na koncie U1** i nigdy nie trafia na konto agenta (U2).

👉 Szczegółowa instrukcja instalacji i użycia tych skryptów znajduje się w **głównym pliku README** projektu.
