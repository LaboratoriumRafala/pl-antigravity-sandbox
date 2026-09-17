# 🛡️ Sandbox dla Agentów AI (Antigravity)

Wyizolowane, przenośne środowisko deweloperskie oparte na Podmanie, przygotowane pod zaawansowane projekty z Agentami AI (LLM).

Architektura opiera się na modelu **Zero-Trust Egress**, chroniąc system operacyjny i sieć domową przed wyciekiem danych (Data Exfiltration) oraz niekontrolowanym uruchamianiem pobranego kodu.

## Spis treści
- [Quick Start](#quick-start)
- [Dlaczego to rozwiązanie jest bezpieczne?](#dlaczego-to-rozwiązanie-jest-bezpieczne)
- [Struktura folderu](#struktura-folderu)
- [Architektura: 1 projekt = 1 folder](#architektura-1-projekt--1-folder)
- [Instrukcja uruchomienia](#instrukcja-uruchomienia)
- [Rozszerzanie i modyfikowanie](#rozszerzanie-i-modyfikowanie)

## Quick Start

```bash
git clone https://github.com/LaboratoriumRafala/pl-antigravity-sandbox
cd pl-antigravity-sandbox
```

Umieść Antigravity IDE w folderze projektu (szczegóły → [Krok 2: Umieść IDE](#krok-2-umieść-ide)), a następnie uruchom:

```bash
chmod +x run-sandbox.sh
./run-sandbox.sh
```

> [!NOTE]
> Wymagany jest Linux z zainstalowanym Podmanem. Użytkownik Windowsa? Zobacz [README-WINDOWS.md](README-WINDOWS.md).

## Dlaczego to rozwiązanie jest bezpieczne?

Standardowe środowiska (nawet oparte o Dockera) ograniczają się do izolacji systemu plików. Jeśli Agent LLM pobierze skrypt, który spróbuje połączyć się z serwerem Command&Control lub pobrać dodatkowy malware, standardowy kontener mu na to pozwoli.

Ten sandbox wprowadza architekturę dwóch kontenerów w strefie DMZ:

1. **Kontener główny (Sandbox)** z IDE i kompilatorami działa w sieci `--internal` (brak routingu na zewnątrz). Fizycznie nie ma możliwości wypuszczenia pakietu internetowego.
2. **Kontener proxy (Squid)** jest jedynym mostem między siecią wewnętrzną a internetem. Przepuszcza wyłącznie domeny z białej listy (`whitelist.txt`).

Ruch wyjdzie na zewnątrz wyłącznie gdy domena znajduje się na białej liście. Nawet jeśli złośliwy skrypt usunie zmienne proxy lub spróbuje uderzyć bezpośrednio po adresie IP, trafi na fizyczny brak routingu.

### Warstwy ochrony:

| # | Warstwa | Co chroni | Szczegóły |
|---|---------|-----------|-----------|
| 1 | **Kontener Podman (namespaces)** | Izolacja od hosta | Agent nie widzi plików poza zamontowanymi wolumenami. Rootless Podman — brak roota na hoście. |
| 2 | **Sieć `--internal`** | Fizyczna blokada internetu | Sandbox nie ma routingu na zewnątrz. Jedyna droga to proxy. |
| 3 | **Squid Proxy (Egress Filtering)** | Ochrona przed eksfiltracją (DLP) | Tylko domeny z `whitelist.txt` są przepuszczane. Reszta → `403 Forbidden`. |
| 4 | **Ślepota DNS (`--disable-dns` + `--dns none`)** | Ochrona przed DNS Tunneling | Sieć w ogóle nie uruchamia bramki DNS (Aardvark), a kontener nie posiada `resolv.conf`. Nawet surowe pakiety UDP 53 wysyłane z kontenera trafiają w próżnię. |
| 5 | **`--security-opt=no-new-privileges`** | Blokada eskalacji uprawnień | Procesy wewnątrz kontenera nie mogą podnieść swoich uprawnień (np. przez `sudo`, `setuid`). |
| 6 | **Wolumeny read-only** | Ochrona integralności IDE | Agent nie może podmienić plików IDE (`/opt/antigravity` → `:ro`). |
| 7 | **`--userns keep-id:uid=1000,gid=1000`** | Mapowanie użytkownika | Wymusza, by agent zawsze miał UID 1000 wewnątrz kontenera, niezależnie od tego, z jakiego konta (U1 czy U2) został uruchomiony. Chroni to uprawnienia plików w `workspace/`. |
| 8 | **Autodetekcja Wayland / X11** | Izolacja sesji graficznej | Pod Wayland agent ma zablokowany podsłuch (keylogging) innych okien z poziomu protokołu. Pod starszym X11 zalecamy architekturę U1/U2 dla osiągnięcia tej samej izolacji. |

### Dlaczego NIE używamy `--cap-drop=ALL`?

Flaga `--cap-drop=ALL` usuwa **wszystkie** Linux capabilities (uprawnienia jądra) wewnątrz kontenera. Brzmi to jak maksymalne bezpieczeństwo, ale w praktyce **uniemożliwia IDE prawidłowe działanie**:

- IDE (Electron/Antigravity) musi tworzyć **pseudoterminale** (pty) dla wbudowanego terminala i Agenta AI
- Agent AI potrzebuje **zarządzać procesami potomnymi** (uruchamianie, kończenie skryptów)
- Rozszerzenia IDE wymagają **komunikacji międzyprocesowej** (IPC)

Bez tych capabilities IDE zamraża się lub crashuje po zalogowaniu. Standardowa izolacja Podmana (namespace + no-new-privileges) jest **w pełni wystarczająca** do ochrony hosta — capabilities wewnątrz kontenera działają wyłącznie w user namespace i nie dają żadnych uprawnień na systemie hosta.

### Co Agent MOŻE zrobić wewnątrz sandboxa:
- ✅ Tworzyć, edytować i usuwać pliki w `/workspace/`
- ✅ Instalować pakiety wewnątrz kontenera (znikają po restarcie)
- ✅ Uruchamiać i zabijać procesy wewnątrz kontenera
- ✅ Łączyć się z domenami z białej listy (API Gemini, Google Cloud)

### Czego Agent **NIE MOŻE** zrobić:
- ❌ Dotknąć plików poza zamontowanymi wolumenami (Twój system jest niewidoczny)
- ❌ Połączyć się z serwerem spoza białej listy (Squid blokuje → `TCP_DENIED/403`)
- ❌ Eskalować uprawnień do roota na hoście
- ❌ Podmienić plików IDE (zamontowane jako read-only)
- ❌ Przetrwać restart — kontener jest efemeryczny (`--rm`)

> [!NOTE]
> Bezpieczeństwo tego sandboxa **nie opiera się na niewiedzy agenta** (Security by Obscurity). Nawet jeśli agent przeczyta cały kod źródłowy tego projektu (np. znajdzie go na GitHubie), nie pomoże mu to w ucieczce — zabezpieczenia działają na poziomie jądra Linux (namespaces), konfiguracji sieci (brak routingu) i systemu plików (read-only mounts).

---

## Struktura folderu

```
pl-antigravity-sandbox/               ← Na hoście (NIE ZAMONTOWANY w kontenerze)
├── run-sandbox.sh                    ← Skrypt uruchomieniowy (NIE ZAMONTOWANY)
├── Containerfile                     ← Przepis na kontener — multi-stage (NIE ZAMONTOWANY)
├── proxy/                            ← Konfiguracja strażnika (NIE ZAMONTOWANA)
│   ├── squid.conf                    ← Reguły firewalla
│   ├── whitelist-base.txt            ← Domeny wspólne dla wszystkich profili
│   ├── whitelist-mcp.txt             ← Domeny dodatkowe: Google Cloud MCP
│   ├── whitelist-gamedev.txt         ← Domeny dodatkowe: Godot Engine
│   └── whitelist.txt                 ← (GENEROWANA automatycznie — nie edytuj!)
├── README.md                         ← Ten plik (NIE ZAMONTOWANY)
├── .gitignore
├── Antigravity IDE/                  ← Pobrane IDE (montowane jako TYLKO DO ODCZYTU)
│   └── antigravity-ide               ← Plik binarny IDE
├── workspace/                        ← JEDYNY folder z prawami ZAPISU dla agenta
│   └── (tu agent tworzy gry, kod, assety)
├── antigravity-userdata/             ← Dane użytkownika (loginy, wtyczki, historia)
│   ├── gemini/                       (wspólne — dane AI)
│   ├── ide-config/                   (wspólne — wtyczki IDE)
│   ├── ide-server/                   (wspólne — runtime IDE)
│   ├── config/                       (wspólne — motywy, okna)
│   ├── profile-base-local/           (cache narzędzi — profil base)
│   ├── profile-mcp-local/            (cache narzędzi — profil mcp)
│   └── profile-gamedev-local/        (cache narzędzi — profil gamedev)
├── .containerfile/                   ← Zasoby dla Containerfile (ręczne COPY do obrazu przy buildzie)
│   ├── start-agent.sh                ← Skrypt startowy kontenera (PID 1)
│   ├── base/bin/                     ← Skrypty profilu bazowego (startup.d/, shutdown.d/, help.d/)
│   └── gamedev/bin/                  ← Skrypty profilu gamedev (startup.d/, shutdown.d/, help.d/)
├── .run-sandbox.d/                   ← Konfiguracja hosta, ładowana przez run-sandbox.sh (auto-discovery)
│   ├── base/                         ← Argumenty Podmana wspólne dla wszystkich profili
│   └── gamedev/                      ← Argumenty Podmana specyficzne dla gamedev (np. PulseAudio)
├── workspace-tools/                  ← Skrypty na maszynie deweloperskiej (poza kontenerem)
│   └── extract-chat.py               ← Eksport rozmów AI do Markdown
└── tools/                            ← Narzędzia TYLKO na konto U1 (synchronizacja, konfiguracja — pomijane przy kopiowaniu na U2)
    ├── settings.sh.example           ← Szablon konfiguracji (skopiuj do settings.sh i uzupełnij)
    ├── sync-sandbox-to-u2.sh         ← Synchronizacja sandboxa na konto U2
    ├── sync-workspace-to-u2.sh       ← Transfer projektu z U1 do workspace agenta na U2
    └── sync-workspace-from-u2.sh     ← Transfer pracy agenta z U2 z powrotem na U1
```

**Co agent widzi wewnątrz kontenera:**
| Ścieżka w kontenerze | Co zawiera | Prawa |
|---|---|---|
| `/workspace/` (lub `~/workspace`) | Twoje pliki gry/kodu | Odczyt + Zapis |
| `/opt/antigravity/` | Pliki IDE | Tylko odczyt |
| `/home/agent/.gemini/` | Historia czatów i stan LLM | Odczyt + Zapis |
| `/home/agent/.antigravity-ide/` | Wtyczki i konfiguracja IDE | Odczyt + Zapis |
| `/home/agent/.antigravity-ide-server/` | Pamięć runtime serwera IDE | Odczyt + Zapis |
| `/home/agent/.config/` | Ustawienia GUI, motywy, okna | Odczyt + Zapis |
| `/home/agent/.local/` | Cache narzędzi (per-profil, izolowany) | Odczyt + Zapis |

---

## Architektura: 1 projekt = 1 folder

Ten folder (`pl-antigravity-sandbox/`) służy jako szablon. Aby uniknąć zakażeń krzyżowych pamięci AI między projektami, stosuj zasadę: jeden projekt = jeden folder sandboxa.

### Jak zacząć nowy projekt (np. WebDev)?
1. Skopiuj ten cały folder na hoście: `cp -r pl-antigravity-sandbox/ moj-projekt-webdev/`
2. Agent w nowym folderze będzie miał czystą historię (pusty folder `antigravity-userdata/gemini`).
3. Pliki IDE Antigravity (które ważą 800MB) możesz albo skopiować, albo — by oszczędzić miejsce — użyć dowiązania symbolicznego (symlink) do jednego głównego folderu IDE: `ln -s /sciezka/do/Antigravity-IDE ./Antigravity\ IDE`

### A co z Git / GitHubem?
Agent ma odcięty dostęp do GitHuba (usunięty z białej listy) i nie może robić `git push` ani korzystać z `curl` by wyprowadzić kod. Zamiast tego:
1. Agent koduje i używa Gita LOKALNIE w `workspace/` (widzi historię, diffy).
2. Ty, na swoim koncie U2, otwierasz folder `workspace/` za pomocą własnego, hostowanego VS Code (lub terminala).
3. **Ty robisz `git commit` i `git push` na zewnątrz sandboxa.** Agent nie ma pojęcia, dokąd trafia kod.

---

## Instrukcja uruchomienia

### Wymagania:
- Linux (np. Ubuntu, Mint)
- Zainstalowany `podman` (działa rootless, bez sudo)
- Wyświetlanie okien: X11 lub Wayland (patrz sekcja "X11 vs Wayland" na dole)

### Dwa tryby pracy

Sandbox działa w dwóch trybach — wybierz odpowiedni dla siebie:

| | **Quick Start** (jeden użytkownik) | **Bank-Grade** (U1 + U2) |
|---|---|---|
| Izolacja sieci | ✅ Podman + Squid Proxy | ✅ Podman + Squid Proxy |
| Izolacja systemu plików | ✅ Kontener | ✅✅ Kontener + osobne konto |
| Izolacja sesji graficznej (X11) | ❌ Agent widzi Twój ekran | ✅ Osobna sesja U2 |
| Izolacja sesji graficznej (Wayland) | ✅ Wayland izoluje natywnie | ✅✅ Dodatkowa warstwa |
| Dla kogo | Hobbystów, Wayland, nauka | Produkcja, X11, dane wrażliwe |
| Wymaga osobnego konta | Nie | Tak |

> [!WARNING]
> **Jeśli Twój system używa X11** (np. Linux Mint z Cinnamon), tryb Quick Start oznacza, że kontener ma dostęp do Twojego ekranu — teoretycznie może robić zrzuty ekranu i przechwytywać klawiaturę. Jeśli w tej samej sesji otwierasz bankowość lub pocztę, **użyj trybu Bank-Grade (U1/U2)**.
>
> Nie wiesz co masz? Wpisz w terminalu: `echo $XDG_SESSION_TYPE` — wynik to `x11` lub `wayland`.

---

### Krok 1: Pobierz ten folder
Sklonuj repozytorium lub pobierz i rozpakuj archiwum.

### Krok 2: Umieść IDE
Pobierz z oficjalnej strony instalację IDE (np. Antigravity IDE). Masz dwie opcje umieszczenia:

**Opcja A — Bezpośrednio (prosta):**
Umieść rozpakowane pliki w podfolderze `Antigravity IDE/` wewnątrz tego folderu.

**Opcja B — Symlink (praktyczna, zalecana przy wielu sandboxach):**
Pobierz IDE do jednego centralnego miejsca (np. `~/Aplikacje/Antigravity IDE/`), a następnie utwórz dowiązanie symboliczne:
```bash
ln -s "/sciezka/do/Antigravity IDE" "./Antigravity IDE"
```
Dzięki temu jeden folder IDE obsługuje wiele sandboxów, a aktualizacja IDE odbywa się w jednym miejscu.

> [!NOTE]
> **Tryb Bank-Grade (U1/U2):** IDE potrzebujesz **wyłącznie na koncie U2** — na U1 nie jest ono używane. Skrypt `sync-sandbox-to-u2.sh` celowo pomija folder `Antigravity IDE/` przy synchronizacji, więc musisz pobrać IDE osobno na koncie U2 i umieścić je (lub zlinkować) w zsynchronizowanym folderze sandboxa.

### Krok 3: Uruchomienie

**Tryb Quick Start** (jeden użytkownik, bez U2):
```bash
./run-sandbox.sh                      # Profil: base (czyste IDE)
./run-sandbox.sh --profile gamedev    # Profil: gamedev (Godot Engine)
```
Przejdź do sekcji "Po uruchomieniu".

**Tryb Bank-Grade** (U1/U2 — dodatkowa konfiguracja):

#### 3a. Konfiguracja (jednorazowo, na koncie U1)
Skopiuj szablon ustawień i uzupełnij swoimi danymi (nazwy kont systemowych, ścieżki na U2):
```bash
cp tools/settings.sh.example tools/settings.sh
```
Plik `tools/settings.sh` jest w `.gitignore` — Twoje prywatne dane nigdy nie trafią do repozytorium.

#### 3b. Synchronizacja na konto deweloperskie (U2)
Na swoim głównym koncie (U1) uruchom:
```bash
./tools/sync-sandbox-to-u2.sh
```
Zsynchronizuje to czysty kod i konfigurację z U1 na U2, całkowicie pomijając `Antigravity IDE/`, `antigravity-userdata/`, `tools/` i inne dane lokalne.

#### 3c. IDE na koncie U2
Zaloguj się na konto U2 i pobierz tam IDE osobno. Zalecany sposób — symlink do centralnego folderu:
```bash
ln -s "/home/U2_USER/Aplikacje/Antigravity IDE" "/home/U2_USER/Projekty/moj-sandbox/Antigravity IDE"
```

#### 3d. Uruchomienie (na koncie U2)
W terminalu (będąc w zsynchronizowanym folderze sandboxa) wybierz profil:
```bash
./run-sandbox.sh                      # Profil: base (czyste IDE)
./run-sandbox.sh --profile mcp        # Profil: mcp (Google Cloud MCP)
./run-sandbox.sh --profile gamedev    # Profil: gamedev (Godot Engine)
./run-sandbox.sh --profile mcp --rebuild  # Przebudowa profilu od zera
```

> [!TIP]
> **Pro-Tip: Własne skróty do profili**
> Zamiast za każdym razem wpisywać flagę `--profile`, możesz stworzyć na hoście dowiązanie symboliczne (symlink), z którego skrypt automatycznie odczyta profil. Na przykład:
> ```bash
> ln -s run-sandbox.sh run-sandbox-gamedev.sh
> ./run-sandbox-gamedev.sh  # Uruchomi profil gamedev!
> ```

---

### Po uruchomieniu

Pierwsze uruchomienie pobierze bazowy obraz Ubuntu i zainstaluje pakiety. Zajmie to kilka minut — każde kolejne uruchomienie będzie błyskawiczne.

Skrypt automatycznie:
1. Wygeneruje białą listę domen z `whitelist-base.txt` + `whitelist-<profil>.txt`
2. Utworzy dwie izolowane sieci Podmana (`sandbox-internal` i `sandbox-external`)
3. Uruchomi Strażnika Proxy (Squid) i poczeka na jego gotowość
4. Zbuduje obraz deweloperski dla wybranego profilu (korzysta z cache)
5. Uruchomi izolowany kontener z Twoim środowiskiem

**Dostępne profile:**
| Profil | Co zawiera | Kiedy używać |
|---|---|---|
| `base` | Czyste IDE Antigravity | Domyślny — dla nowych projektów bez specyficznych narzędzi |
| `mcp` | base + Node.js runtime | Google Cloud MCP (notebooks, wizualizacje, data agent) |
| `gamedev` | base + Godot Engine + PulseAudio | Tworzenie gier w Godot 4.x (włączony dźwięk z hosta) |

### Automatyczny start i terminal
Po wejściu do kontenera IDE uruchomi się automatycznie w tle, oddając wolny terminal do pracy (np. do uruchomienia silnika Godot).

**Gdzie są logi IDE?** 
Logi IDE nie są wyświetlane w konsoli. Dostępne komendy:
- `ide-logs` – podgląd na żywo (tylko najnowsze linijki, zamykasz `Ctrl+C`).
- `ide-logs-full` – pełny zrzut całego pliku (przydatne do kopiowania błędów).

**Zarządzanie IDE**
W każdej chwili możesz wyłączyć IDE (np. jeśli się zawiesi) komendą:
```bash
ide-stop
```
> **Wskazówka:** Skrypt czeka cierpliwie na bezpieczne zamknięcie aplikacji (Graceful Shutdown). Jeśli jednak aplikacja zawiesiła się krytycznie i nie reaguje, możesz użyć "Przycisku Paniki" wciskając **`Ctrl+C`**, co wymusi jej natychmiastowe zabicie (SIGKILL).
A następnie uruchomić je ponownie wpisując:
```bash
ide-start
```

**Eksport czatu (Bezpieczny Audyt)**
Ze względów bezpieczeństwa (tryb `--no-sandbox` dla Electrona i brak dostępu do okien dialogowych hosta), przycisk "Export" wewnątrz IDE nie działa. Czat logowany jest jednak w postaci surowych plików `transcript.jsonl`.
Aby wyeksportować sformatowaną, czystą rozmowę w formacie Markdown (bez logów systemowych agenta), uruchom poniższe polecenie **bezpośrednio na hoście (poza kontenerem)**:

```bash
./workspace-tools/extract-chat.py
```
*(Jeśli skrypt nie ma jeszcze praw wykonywalnych, możesz użyć `python3 workspace-tools/extract-chat.py`)*

Plik zostanie wygenerowany bezpośrednio w folderze `workspace/`.

Przy pierwszym uruchomieniu zostaniesz poproszony o logowanie do konta Google (OAuth — jednorazowo). Logowanie otwiera wbudowaną przeglądarkę Google Chrome wewnątrz kontenera.

### Wielozadaniowość (tmux)
Aby ułatwić pracę z wieloma aplikacjami (np. jednoczesny podgląd logów IDE i uruchamianie innych programów), zintegrowaliśmy program `tmux`. Po wejściu do kontenera wystarczy wpisać `tmux`, aby wejść w tryb wirtualnych okien.
Główny skrót (Prefix) to **`Ctrl+B`** (naciskasz Ctrl+B, puszczasz i wciskasz właściwy klawisz):
- `Ctrl+B %` – dzieli ekran w pionie.
- `Ctrl+B "` – dzieli ekran w poziomie.
- `Ctrl+B strzałki` – przełączanie się między okienkami.
- `Ctrl+B [` – tryb scrollowania (do góry/dołu strzałkami, wyjście `q`).

### Specyfika profilu GameDev
Wybierając profil `gamedev`, masz do dyspozycji nie tylko automatyczny start IDE, ale również zestaw dedykowanych komend do ukrywania silnika Godot w tle:
- `godot-start` – uruchamia Godota w tle.
- `godot-logs` – podgląd logów Godota na żywo.
- `godot-logs-full` – pełny zrzut logów Godota.
- `godot-stop` – wyłącza proces Godota (również obsługuje bezpieczne zamykanie oraz "Przycisk Paniki" `Ctrl+C`).

### Konfiguracja Agenta AI
Po zalogowaniu i przejściu kreatora konfiguracji, możesz bezpiecznie ustawić Agenta AI w trybie **autonomicznym** (auto-run). Dzięki izolacji kontenerowej i filtrowi Squid, Agent może swobodnie działać bez Twojej zgody na każdą komendę — nie ma możliwości uszkodzenia Twojego systemu hosta.

---

## Rozszerzanie i modyfikowanie

### 1. Agent nie może połączyć się z jakimś serwisem?
Otwórz `proxy/whitelist.txt` i dodaj brakującą domenę. Zrestartuj środowisko.

**Jak znaleźć brakującą domenę?** Sprawdź logi strażnika (nazwa kontenera proxy zawiera nazwę Twojego folderu):
```bash
podman logs proxy-NAZWA_FOLDERU 2>&1 | grep "TCP_DENIED"
```
Zobaczysz dokładny adres, który został zablokowany.

### 2. Jak dodać nowe narzędzie (Node.js, Rust, itp.)?
Aby zainstalować nowy pakiet systemowy, otwórz `Containerfile`, znajdź sekcję `RUN apt-get update...` i dopisz pakiet. Przy następnym uruchomieniu użyj `./run-sandbox.sh --rebuild`.

**Jak dodać nowy serwis w tle (np. bazę danych PostgreSQL)?**
Użyj wzorca *Drop-in Hooks*:
1. Utwórz w `.containerfile/base/bin/startup.d/` plik `50-postgres.sh` i wpisz kod startujący serwis.
2. Utwórz w `.containerfile/base/bin/shutdown.d/` plik `50-postgres.sh` i wpisz kod zamykający serwis.
3. Kontener sam uruchomi te skrypty w odpowiedniej kolejności dzięki **Mirror Pattern**.

> *Pełna dokumentacja systemu wtyczek: [`.containerfile/README.md`](file:///home/rafal/Projekty/pl-antigravity-sandbox/.containerfile/README.md)*

### 3. Jak zmienić wersję Godota?
W `Containerfile` zmień wartość `ARG GODOT_VERSION="4.7.1-stable"` na nową wersję. Przy następnym uruchomieniu skrypt pobierze i zainstaluje nową wersję.

### 4. Jak zresetować środowisko?
Kontener główny jest efemeryczny (flaga `--rm`). Wyjdź (`exit`) i uruchom ponownie — kontener odtworzy się z czystego obrazu. Twoje pliki w `workspace/` i historia czatów pozostaną nienaruszone.

### 5. Jak sprawdzić, dokąd agent próbował się połączyć?
```bash
podman logs proxy-NAZWA_FOLDERU
```
Zobaczysz listę WSZYSTKICH żądań sieciowych z oznaczeniem, które zostały przepuszczone (`TCP_TUNNEL/200`), a które zablokowane (`TCP_DENIED/403`).

> [!TIP]
> Nazwy kontenerów i sieci zawierają nazwę folderu sandboxa (np. `proxy-gamedev-project1`, `sandbox-internal-gamedev-project1`). Dzięki temu możesz uruchamiać wiele sandboxów równolegle bez konfliktów. Lista aktywnych kontenerów: `podman ps`.

