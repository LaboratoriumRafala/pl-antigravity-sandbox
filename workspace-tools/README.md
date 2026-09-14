# Narzędzia Zewnętrzne (Workspace Tools)

Skrypty w tym folderze są przeznaczone do uruchamiania **poza kontenerem**, bezpośrednio na hoście deweloperskim.

**Dlaczego skrypty są na zewnątrz?**
Środowisko Antigravity działa w trybie ekstremalnej izolacji (Zero-Trust, blokada eksfiltracji). Aby zachować szczelność sandboxa, natywne mechanizmy środowiska graficznego (jak dostęp do schowka, czy wyskakujące okna zapisu plików hosta) są zablokowane. Agent loguje całą konwersację bezpiecznie w tle w postaci surowych plików JSON.

Skrypty z tego folderu (np. `extract-chat.py`) służą jako "most". Pozwalają z zewnątrz bezpiecznie przekształcić logi agenta do pięknego, czytelnego formatu Markdown, bez tworzenia luki bezpieczeństwa wewnątrz kontenera.

👉 Instrukcja użycia narzędzi znajduje się w **głównym pliku README** projektu.
