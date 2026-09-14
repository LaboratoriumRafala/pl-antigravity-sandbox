# .run-sandbox.d/ — Konfiguracja uruchomieniowa (host)

Skrypty w tym katalogu są wykonywane przez `run-sandbox.sh` **na maszynie
hosta** (nie wewnątrz kontenera). Służą do dodawania argumentów Podmana
specyficznych dla danego profilu.

## Jak to działa

Przed wywołaniem `podman run`, skrypt `run-sandbox.sh` przeszukuje ten katalog
i ładuje pliki `*.sh` w następującej kolejności:

1. `base/*.sh` — argumenty wspólne dla wszystkich profili
2. `<profil>/*.sh` — argumenty specyficzne dla wybranego profilu

Każdy plik jest ładowany przez `source` i może dopisywać elementy do tablicy
`PODMAN_EXTRA_ARGS+=()`.

## Przykłady

| Profil | Plik | Co dodaje |
|---|---|---|
| `base` | `base/10-display.sh` | Autodetekcja grafiki (Wayland / X11) |
| `gamedev` | `gamedev/10-audio.sh` | Socket PulseAudio (dźwięk) |
| `webdev` | `webdev/20-ports.sh` | Porty 8080, 4200 (przykład) |
| `ai` | `ai/30-gpu.sh` | Specjalny dostęp do akceleratorów (przykład) |

## Bezpieczeństwo

Skrypty z tego katalogu działają z uprawnieniami użytkownika hosta. Używają
`source`, co oznacza dostęp do zmiennych `run-sandbox.sh`. Jest to bezpieczne,
ponieważ pliki są częścią repozytorium — nie są generowane ani modyfikowane
przez kod działający wewnątrz sandboxa.
