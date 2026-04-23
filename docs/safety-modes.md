# Tryby usuwania (`delete_mode`)

`AutoCleanMac` obsługuje trzy tryby usuwania. Wybierasz je w `~/.config/autoclean-mac/config.json` pod kluczem `delete_mode`.

| Wartość   | Zachowanie                                                                     | Odwracalne? |
|-----------|--------------------------------------------------------------------------------|-------------|
| `trash`   | **Domyślny.** Przenosi pliki do systemowego Kosza (`FileManager.trashItem`).   | Tak         |
| `live`    | Trwale usuwa plik (`FileManager.removeItem`). Zachowanie sprzed v0.x.          | Nie         |
| `dry_run` | Niczego nie kasuje, tylko loguje co *zostałoby* usunięte i zlicza rozmiar.     | —           |

## Override środowiskowy

Zmienna `AUTOCLEANMAC_DRY_RUN` (jakakolwiek niepusta wartość) wymusza `dry_run` niezależnie od configu. Przydatne do testów bez edycji pliku.

```bash
AUTOCLEANMAC_DRY_RUN=1 ./AutoCleanMac.app/Contents/MacOS/AutoCleanMac
```

## Migracja z wcześniejszych wersji

Wcześniejsze wersje używały `.live` na sztywno. Istniejące configi nie mają klucza `delete_mode` i nowa wersja nadaje im wartość domyślną `trash`. Jeśli chcesz zachować stare zachowanie, dopisz:

```json
{ "delete_mode": "live" }
```

## Co oznacza "zwolniono X GB" dla trybu `trash`?

Rozmiar jest liczony **przed** przeniesieniem, rekurencyjnie dla katalogów. W Koszu pliki dalej zajmują miejsce dopóki nie opróżnisz Kosza — wartość z podsumowania odzwierciedla potencjalną ilość zwolnionej przestrzeni, nie stan po operacji.
