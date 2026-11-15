# Arch / CachyOS: lokaler Entwicklungsstand

Das Rezept paketiert einen lokalen Snapshot einschließlich uncommitteter und nicht ignorierter neuer Dateien sowie der mitgelieferten QML-Komponenten und Quickshell-Laufzeit. Es ist kein automatisch aktualisiertes Git-Paket. Es installiert die Lizenzen der Quellprojekte, Fonts und aufgelösten Go-Abhängigkeiten; die Modul-/Lizenzübersicht steht in `docs/third-party-go-licenses.csv`, die vollständigen Lizenztexte in `assets/licenses/fjord-go/`. Der Go-Bericht wurde mit `go-licenses` v1.6.0 für `./cmd/dfiles` erstellt; ausschließlich die eigenen Fjord-Pakete wurden beim Fremdlizenzbericht ignoriert. Die lokale Dux-Go-Abzweigung hat eine MIT-Hauptlizenz sowie BSD-Hinweise für `syncmap` und `wayland`, alle liegen im Lizenzbundle. Für einen reproduzierbaren Eingabestand das erzeugte Archiv und den zugehörigen PKGBUILD aufbewahren; bei Änderungen einen neuen Snapshot erstellen. Der Build lädt Go-Module anhand von `go.sum` herunter, benötigt also beim ersten Mal Netzwerkzugang. Identische Binärdateien setzen außerdem dieselben Versionen der Buildwerkzeuge und Abhängigkeiten voraus.

```sh
python3 distro/arch/snapshot.py /tmp/fjord-package
cd /tmp/fjord-package
export SOURCE_DATE_EPOCH=$(cat .source-date-epoch)
makepkg -s
```

Voraussetzungen sind `base-devel`, Python und ein Arch-Go-Paket ab 1.27.3 sowie die im Rezept genannten Abhängigkeiten. Ist die passende Go-Version in den aktivierten Paketquellen noch nicht verfügbar, kann der reguläre Abhängigkeitscheck nicht erfüllt werden; eine lokal bereitgestellte Go-Version ist kein Ersatz für einen sauberen Paketbau. Quickshell muss das Kommando `qs` bereitstellen. Qt Multimedia und Qt PDF werden für die Medien- beziehungsweise PDF-Vorschau benötigt. Auf diesem Arch/CachyOS-System liefert `qt6-webengine` das Qt-PDF-Modul; beide sind optionale Paketabhängigkeiten. Sweep ist optional. Während der Snapshot-Erstellung sollten keine Dateien im Arbeitsbaum geändert werden. Der optionale Rummage-Adapter erfordert einen separat eingerichteten kompatiblen Helfer (siehe `docs/rummage-preview.md`).

Das Paket installiert Programm, Launcher, Icon, Desktop-Eintrag, Lizenzen und eine nicht aktivierte Systemd-User-Unit. Es ändert keine Standardanwendungen und installiert keine Portal-, D-Bus- oder Polkit-Integration. Die Desktop-Datei bietet Dateitypen an; die Auswahl eines Standards erfolgt separat durch den Benutzer. Zur Inhaltsprüfung ohne Installation: `bsdtar -tf fjord-files-*.pkg.tar.zst`. Ein Paket kann anschließend bewusst mit `sudo pacman -U ...` installiert werden.
