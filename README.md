# Oddsparks Sync

Skrypt PowerShell do synchronizacji zapisów gry **Oddsparks: An Automation Adventure** przez Google Drive. Automatycznie wykrywa, czy pobrać (pull) czy wysłać (push) zapis — bez ręcznego kopiowania plików.

## Wymagania

- Windows z PowerShell 5.1+
- Konto Google z dostępem do współdzielonego folderu na Dysku Google
- Plik `client_secret.json` z Google Cloud (OAuth 2.0 — Desktop app)

## Konfiguracja

Skopiuj `client_secret.example.json` jako `client_secret.json` i uzupełnij danymi swojej aplikacji OAuth z [Google Cloud Console](https://console.cloud.google.com/).

Otwórz `RunSyncOddsparksSave.cmd` i ustaw trzy zmienne:

```bat
set WORLD=NazwaZapisu       :: nazwa pliku zapisu (bez .sav)
set PLAYER=TwojeImie        :: Twoje imię widoczne w snapshotach
set FOLDER_URL=LinkHttp     :: link do folderu na Dysku Google
```

## Użycie

Uruchom `RunSyncOddsparksSave.cmd` dwuklikiem lub z wiersza poleceń:

```bat
RunSyncOddsparksSave.cmd
```

Przy pierwszym uruchomieniu otworzy się przeglądarka z ekranem logowania Google. Token jest zapisywany lokalnie w `%APPDATA%\OddsparksSync\`.

### Tryby (`-Mode`)

| Tryb | Opis |
|------|------|
| `auto` | Automatycznie decyduje: pull jeśli Drive jest nowszy, push jeśli lokalny, błąd przy konflikcie (domyślny) |
| `status` | Pokazuje stan lokalny i zdalny bez żadnych zmian |
| `pull` | Wymusza pobranie najnowszego snapshotu z Drive |
| `push` | Wymusza wysłanie lokalnego zapisu na Drive |
| `login` | Ponownie loguje do Google |
| `logout` | Usuwa lokalny token Google |

Tryb można przekazać bezpośrednio do `.cmd`:

```bat
RunSyncOddsparksSave.cmd -DryRun
RunSyncOddsparksSave.cmd -Mode status
RunSyncOddsparksSave.cmd -Mode pull
```

Flaga `-DryRun` pokazuje decyzję bez wykonywania żadnych operacji na plikach.

### Backup (`-BackupDir`)

Przed każdą operacją pull i push skrypt automatycznie tworzy backup całego folderu `Savegames` jako plik ZIP:

```
%LOCALAPPDATA%\Oddsparks\Full\SavegamesBackups\2026-05-16_21-30-00__pull.zip
```

Domyślną lokalizację można zmienić:

```bat
RunSyncOddsparksSave.cmd -BackupDir "D:\MojeBackupy"
```

Przy `-DryRun` backup jest logowany, ale nie tworzony.

## Struktura Dysku Google

```
<Twój folder>/
└── saves/
    └── NazwaZapisu/
        ├── 2026-05-09_22-18-43__Wiktor/
        │   ├── NazwaZapisu.sav
        │   ├── NazwaZapisu_meta.sav
        │   └── NazwaZapisu_sync__2026-05-09_22-18-43__Wiktor.json
        └── 2026-05-10_23-02-11__Dominika/
            └── ...
```

Każdy snapshot to osobny folder — nic nie jest nadpisywane.

## Konflikty

Konflikt pojawia się, gdy dwie osoby zagrały na podstawie tej samej wersji zapisu. Skrypt zgłosi błąd i wyświetli stan obu snapshotów. Wybierz wersję ręcznie przez `-Mode pull` lub `-Mode push`.
