# .containerfile/ — Zasoby obrazu kontenera

Zawartość tego katalogu jest kopiowana do obrazu kontenera podczas budowania
(`podman build`). Nic z tego nie jest montowane w czasie pracy — wszystko trafia
do obrazu na etapie `COPY` w pliku `Containerfile`.

## Struktura katalogów

Katalogi są podzielone na **profile** (`base`, `gamedev`, itp.).
Każdy profil posiada podkatalog `bin/`, którego zawartość trafia
do `/usr/local/bin/` wewnątrz kontenera.

Przykład: plik `.containerfile/base/bin/ide-start` staje się `/usr/local/bin/ide-start`.

## System wtyczek (Drop-in Hooks)

Skrypt `start-agent.sh` automatycznie wykrywa i wykonuje pliki z trzech katalogów:

| Katalog | Przeznaczenie | Przykład |
|---|---|---|
| `bin/startup.d/*.sh` | Uruchamianie usług przy starcie kontenera | `99-ide.sh` |
| `bin/shutdown.d/*.sh` | Zamykanie usług przy wyjściu z kontenera | `99-ide.sh` |
| `bin/help.d/*.txt` | Opis komend wyświetlany na ekranie powitalnym | `10-ide.txt` |

### Konwencja numeracji

Nazwy plików zaczynają się od liczby dwucyfrowej, która określa kolejność
wykonywania:

| Zakres | Przeznaczenie |
|---|---|
| `00–09` | Zarezerwowane dla systemu |
| `10–49` | Usługi bazowe |
| `50–89` | Rozszerzenia (bazy danych, serwery WWW) |
| `90–99` | Aplikacje końcowe (IDE) |

Zamykanie odbywa się w kolejności odwrotnej (LIFO): usługa `99` zostanie
wyłączona przed usługą `10`.

## Tworzenie nowego profilu

Przykład: profil `database` z PostgreSQL.

1. Utwórz katalog: `database/bin/`
2. Utwórz podkatalogi: `startup.d/`, `shutdown.d/`, `help.d/`
3. Dodaj skrypt startowy: `database/bin/startup.d/50-postgres.sh`
4. Dodaj opis komend (opcjonalnie): `database/bin/help.d/50-postgres.txt`
5. W `Containerfile` dodaj sekcję nowego profilu z instrukcją:
   `COPY .containerfile/database/bin/ /usr/local/bin/`

Skrypt `start-agent.sh` wykryje nowe pliki automatycznie.

## Izolacja

Każdy skrypt z `startup.d/` i `shutdown.d/` jest uruchamiany jako osobny
podproces. Błąd w jednym skrypcie nie zatrzymuje pozostałych i nie zaśmieca
środowiska zmiennymi.
