# 🪟 Sandbox na Windows (przez WSL2)

> [!WARNING]
> **Ten sandbox jest narzędziem linuksowym.** Poniższa instrukcja pozwala uruchomić go na Windows 11 przez WSL2 (Windows Subsystem for Linux), ale wiąże się z narzutem wydajnościowym. WSL2 to pełna maszyna wirtualna Hyper-V — Windows, WSL2 i Podman z kontenerem zużywają RAM jednocześnie. Na maszynach z 16GB RAM środowisko może działać odczuwalnie wolniej niż na natywnym Linuksie.
>
> Jeśli planujesz regularną pracę z tym sandboxem, rozważ instalację Linuksa jako dual-boot (Ubuntu, Mint, Fedora).

---

## Krok 1: Instalacja WSL2

Otwórz **PowerShell** (Menu Start → wpisz „Terminal" → Enter):

```powershell
wsl --install
```

> [!NOTE]
> W Windows 11 komenda `wsl.exe` jest preinstalowana, ale to tylko zaślepka. Powyższa komenda pobiera pełne środowisko Linux (domyślnie Ubuntu).

**Zrestartuj komputer**, jeśli pojawi się komunikat z taką prośbą.

Po restarcie uruchom ponownie:

```powershell
wsl --install
```

Tym razem otworzy się terminal Ubuntu z prośbą o ustawienie nazwy użytkownika i hasła. Wpisz je — to będą Twoje dane logowania do środowiska Linux.

> [!TIP]
> Aby w przyszłości wrócić do zainstalowanego Linuksa, wystarczy wpisać `wsl` w PowerShell.

## Krok 2: Aktualizacja systemu i instalacja narzędzi

W terminalu Ubuntu (WSL2):

```bash
sudo apt update
sudo apt install podman
```

> [!IMPORTANT]
> Komenda `sudo apt update` jest obowiązkowa na świeżej instalacji. Bez niej system nie wie, jakie pakiety są dostępne, i `apt install podman` zakończy się błędem „package not found".

## Krok 3: Pobranie projektu

Przejdź do katalogu domowego Linuksa (ważne — nie pracuj bezpośrednio na `/mnt/c/`, bo operacje dyskowe między Windowsem a WSL2 są wolne):

```bash
cd ~
mkdir -p ~/Projekty
cd ~/Projekty
git clone https://github.com/TWOJA-NAZWA/pl-antigravity-sandbox.git
cd pl-antigravity-sandbox
```

> [!TIP]
> Alternatywnie możesz pobrać archiwum `.zip` lub `.tar.gz` z poziomu przeglądarki na Windowsie. Plik pojawi się na dysku C:, który w WSL2 jest widoczny jako `/mnt/c/`. Skopiuj go do katalogu domowego Linuksa i rozpakuj:
> ```bash
> cp /mnt/c/Users/TWÓJ_USER/Downloads/pl-antigravity-sandbox.tar.gz ~/Projekty/
> cd ~/Projekty
> tar -xzf pl-antigravity-sandbox.tar.gz
> rm pl-antigravity-sandbox.tar.gz
> ```

## Krok 4: Instalacja Antigravity IDE

Sandbox wymaga plików Antigravity IDE w folderze projektu. Pobierz **wersję dla Linuksa** ze strony Antigravity i skopiuj archiwum do WSL2:

```bash
mkdir -p ~/Aplikacje
cp "/mnt/c/Users/TWÓJ_USER/Downloads/Antigravity IDE.tar.gz" ~/Aplikacje/
cd ~/Aplikacje
tar -xzf "Antigravity IDE.tar.gz"
rm "Antigravity IDE.tar.gz"
```

Następnie utwórz symlink w folderze projektu (zgodnie z instrukcją w głównym README):

```bash
cd ~/Projekty/pl-antigravity-sandbox
ln -s ~/Aplikacje/Antigravity\ IDE/ .
```

## Krok 5: Uruchomienie

```bash
cd ~/Projekty/pl-antigravity-sandbox
./run-sandbox.sh
```

Przy pierwszym uruchomieniu skrypt zbuduje obraz kontenera (to może potrwać kilka minut). Po zakończeniu otworzy się okno Antigravity IDE — zaloguj się kontem Google.

Aby wyłączyć sandbox, wciśnij `CTRL + D` w terminalu. Skrypt zamknie kontener i wyczyści zasoby. Przed dalszą pracą zapoznaj się z pełną instrukcją w głównym [README](README.md).

---

## Deinstalacja (przywracanie systemu do stanu wyjściowego)

Jeśli zdecydujesz, że WSL2 nie jest dla Ciebie, wykonaj poniższe kroki, aby całkowicie usunąć środowisko:

### 1. Usunięcie dystrybucji Linux

Otwórz **PowerShell**:

```powershell
wsl --unregister Ubuntu
```

> [!CAUTION]
> Ta komenda **trwale usuwa** całą dystrybucję Ubuntu wraz ze wszystkimi plikami, które w niej utworzyłeś (projekty, konfiguracja, dane). Upewnij się, że nie masz tam niczego ważnego.

### 2. Wyłączenie WSL2 (opcjonalne)

Jeśli chcesz całkowicie usunąć WSL2 z systemu:

1. Otwórz **Ustawienia** → **Aplikacje** → **Funkcje opcjonalne** → **Więcej funkcji systemu Windows**
2. Odznacz **Podsystem Windows dla systemu Linux**
3. Odznacz **Platforma maszyny wirtualnej**
4. Kliknij OK i zrestartuj komputer

Alternatywnie z poziomu PowerShell (jako Administrator):

```powershell
wsl --uninstall
```

Po tych krokach system Windows wróci do stanu sprzed instalacji WSL2.
