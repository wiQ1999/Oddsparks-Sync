# Oddsparks - współdzielone zapisy gry

Ten folder służy do współdzielenia zapisów gry **Oddsparks: An Automation Adventure** między graczami.

System opiera się na snapshotach. Każdy snapshot to osobny folder zawierający plik zapisu gry, odpowiadający mu plik metadanych gry oraz własny plik synchronizacji JSON. Proces może być wykonywany ręcznie albo obsługiwany przez skrypt synchronizujący.

## Struktura Dysku Google

```text
Oddsparks: An Automation Adventure/
└── Saves/
    └── NazwaZapisu/
        ├── 2026-05-09_22-18-43__Wiktor/
        │   ├── NazwaZapisu.sav
        │   ├── NazwaZapisu_meta.sav
        │   └── NazwaZapisu_sync__2026-05-09_22-18-43__Wiktor.json
        └── 2026-05-10_23-02-11__Dominika/
            ├── NazwaZapisu.sav
            ├── NazwaZapisu_meta.sav
            └── NazwaZapisu_sync__2026-05-10_23-02-11__Dominika.json
```

Folder `saves` zawiera osobne katalogi dla światów gry. Nazwa katalogu świata, np. `NazwaZapisu`, identyfikuje konkretny zapis/świat.

## Konwencje nazw

### Folder snapshotu

```text
YYYY-MM-DD_HH-mm-ss__IMIE
```

### Plik zapisu gry

```text
NAZWA-ZAPISU.sav
```

### Plik metadanych gry

```text
NAZWA-ZAPISU_meta.sav
```

### Plik synchronizacji JSON

```text
NAZWA-ZAPISU_sync__YYYY-MM-DD_HH-mm-ss__IMIE.json
```

Plik synchronizacji JSON jest plikiem technicznym tego systemu. Nie jest plikiem gry. Służy do zapisania informacji o snapshocie, autorze synchronizacji, źródłowym snapshocie oraz plikach skopiowanych w ramach snapshotu.

## Lokalny folder zapisów gry

Lokalny folder zapisów Oddsparks:

```text
%LOCALAPPDATA%\Oddsparks\Full\Savegames
```

Przykładowa zawartość:

```text
Savegames/
├── NazwaZapisu.sav
├── NazwaZapisu_meta.sav
├── NazwaZapisu_sync__2026-05-09_22-18-43__Wiktor.json
└── NazwaZapisu_sync__2026-05-10_23-02-11__Dominika.json
```

Plik `NazwaZapisu.sav` jest aktualnym plikiem zapisu gry i może być nadpisywany. Plik `NazwaZapisu_meta.sav` jest dodatkowym plikiem gry powiązanym z tym samym zapisem i powinien być synchronizowany razem z plikiem `.sav`. Pliki `NazwaZapisu_sync__*.json` są lokalną historią synchronizacji.

## Schemat metadanych synchronizacji JSON

Przykład:

```json
{
  "schema_version": 2,
  "world": {
    "name": "NazwaZapisu"
  },
  "files": {
    "save_file": {
      "name": "NazwaZapisu.sav",
      "sha256": "new-save-hash"
    },
    "meta_file": {
      "name": "NazwaZapisu_meta.sav",
      "sha256": "new-meta-save-hash"
    },
    "sync_file": {
      "name": "NazwaZapisu_sync__2026-05-10_23-02-11__Wiktor.json"
    }
  },
  "snapshot": {
    "folder_name": "2026-05-10_23-02-11__Wiktor",
    "created_at": "2026-05-10T23:02:11+02:00",
    "created_by": "Wiktor"
  },
  "source_snapshot": {
    "folder_name": "2026-05-09_22-18-43__Dominika"
  }
}
```

Pole `files.save_file` opisuje główny plik zapisu gry. Pole `files.meta_save_file` opisuje dodatkowy plik metadanych gry `*_meta.sav`, który musi pochodzić z tego samego lokalnego stanu zapisu co plik `.sav`. Pole `files.sync_file` wskazuje nazwę własnego pliku synchronizacji JSON dla danego snapshotu.

## Pobieranie zapisu przed grą

1. Zamknij grę.
2. Otwórz folder świata na Dysku Google, np. `saves/NazwaZapisu/`.
3. Wybierz najnowszy folder snapshotu według daty i czasu w nazwie.
4. Skopiuj całą zawartość snapshotu do lokalnego folderu `Savegames`, w tym:
   - plik `NazwaZapisu.sav`,
   - plik `NazwaZapisu_meta.sav`,
   - plik `NazwaZapisu_sync__YYYY-MM-DD_HH-mm-ss__IMIE.json`.
5. Uruchom grę.
6. Dla komunikatu "Wykryto konflikt synchronizacji w chmurze...", wybierz nowszy plik lokalny - "PRZEŚLIJ DO CHMURY".

## Wysyłanie zapisu po grze

1. Zapisz grę - nadpisz zapis z tą samą nazwą.
2. Zamknij grę.
3. W lokalnym folderze `Savegames` znajdź aktualny plik `NazwaZapisu.sav`, `NazwaZapisu_meta.sav` i najnowszy plik synchronizacji `NazwaZapisu_sync__*.json`.
4. Utwórz nowy plik synchronizacji, uzupełnij polę `source_snapshot.folder_name` na podstawie pola `snapshot.folder_name`z ostatniego pliku synchronizacji.
5. Utwórz nowy folder snapshotu na Dysku Google.
6. Skopiuj do niego:
   - aktualny plik `NazwaZapisu.sav`,
   - aktualny plik `NazwaZapisu_meta.sav`,
   - nowy plik synchronizacji JSON `NazwaZapisu_sync__YYYY-MM-DD_HH-mm-ss__IMIE.json`.
7. Zostaw nowy plik synchronizacji JSON również lokalnie.

## Konflikty

Konflikt występuje, gdy dwa snapshoty mają ten sam `source_snapshot.folder_name`. Oznacza to, że dwie osoby grały osobno na podstawie tej samej wcześniejszej wersji. W takiej sytuacji trzeba ręcznie wybrać jeden snapshot jako kontynuację i usunąć duplikat.

## Cofanie do starszego snapshotu

Przy ręcznym cofnięciu do starszej wersji należy:

1. Zamknąć grę.
2. Skopiować starszy plik `NazwaZapisu.sav` do lokalnego folderu `Savegames`.
3. Skopiować odpowiadający mu plik `NazwaZapisu_meta.sav` do lokalnego folderu `Savegames`.
4. Skopiować odpowiadający mu plik synchronizacji JSON.
5. Usunąć lokalne pliki synchronizacji JSON nowsze niż przywracany snapshot.

## Backup automatyczny

Przed każdą operacją modyfikującą lokalne pliki gry (pull, push) skrypt tworzy automatyczny backup całego folderu `Savegames` w postaci skompresowanego archiwum ZIP.

Domyślna lokalizacja backupów:

```text
%LOCALAPPDATA%\Oddsparks\Full\SavegamesBackups\
```

Nazwa pliku ZIP:

```text
YYYY-MM-DD_HH-mm-ss__pull.zip
YYYY-MM-DD_HH-mm-ss__push.zip
```

Lokalizację można zmienić parametrem `-BackupDir`. Przy fladze `-DryRun` backup jest tylko logowany, ale nie tworzony.

## Zasady bezpieczeństwa

- Nie kopiuj plików, gdy gra jest uruchomiona.
- Nie nadpisuj snapshotów na Dysku Google.
- Każdy eksport tworzy nowy folder snapshotu.
- Snapshot jest poprawny tylko wtedy, gdy zawiera plik `.sav`, odpowiadający mu plik `_meta.sav` oraz odpowiadający im plik synchronizacji JSON `*_sync__*.json`.
- Przed ręczną podmianą zapisu warto wykonać kopię lokalnego folderu `Savegames`.
