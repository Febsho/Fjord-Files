# Fjord Files – Entwicklungsstand

Eigenständiger Entwicklungsfork von Dux Files. Architektur und offene Schritte: [docs/architecture.md](docs/architecture.md). Die Upstream-Lizenzen und Copyright-Hinweise bleiben erhalten.

## Bauen und starten

Voraussetzungen: Go 1.27.3 oder neuer und Quickshell mit Qt 6. Die gemeinsam genutzten QML-Komponenten und Quickshell-Laufzeit sind im Repository enthalten.

```sh
make build
./run-fjord
```

`run-fjord` nutzt das installierte Upstream-Quickshell. Für Entwicklungsumgebungen ohne Go im PATH kann der Build hier mit `PATH="$HOME/.local/opt/filemanager-go1.27.3/bin:$PATH" make build` erfolgen. Der Build enthält die QML-Dateien, benötigt aber für diesen Startweg Quickshell auf dem PATH. `make test` führt die Go-Tests aus; `python3 quickshell/tests/run-qml.py` prüft die QML-Oberfläche offscreen. `python3 scripts/test_acceptance.py` prüft Dateiliste, Kopieren, Verschieben und Papierkorb mit einem isolierten Test-Daemon und temporären Dateien. `python3 scripts/test_dbus_activation.py` prüft die optionale D-Bus-Aktivierung auf einem isolierten Sitzungsbus; dafür werden `dbus-run-session`, `gdbus` und Quickshell benötigt. Build und Tests nicht gleichzeitig starten: der Build erzeugt das eingebettete QML-Verzeichnis neu.

Ein x86_64-AppImage lässt sich mit `make appimage` bauen. Benötigt werden Go, Quickshell, Qt 6 mit QML- und Multimedia-Modulen, Qt PDF, `rsvg-convert` und `curl`. Das Skript lädt `appimagetool` und den Type-2-Runtime bei Bedarf in `.appimage-work/tools/` und prüft beide gegen festgelegte SHA-256-Werte; ein eigenes Tool kann über `APPIMAGETOOL=/pfad/zum/appimagetool` angegeben werden. Qt/QML und QuickShell werden aus dem Buildsystem übernommen; Wayland, der Grafiktreiber und glibc bleiben Laufzeitabhängigkeiten des Zielsystems. Das AppImage wird nach `dist/Fjord-Files-x86_64.AppImage` geschrieben und per SHA-256 begleitet.

App-ID: `io.github.febsho.fjordfiles`. Einstellungen, Cache und IPC verwenden `fjord-files`. Die Integration als Dateimanager ist standardmäßig ausgeschaltet. `make install PREFIX="$HOME/.local"` installiert Programm, Starter, Desktop-Eintrag, Icon und eine nicht aktivierte Systemd-User-Unit lokal. Die Installation ändert keine Systemstandards und installiert keine D-Bus-, Portal- oder Polkit-Dateien. `make uninstall PREFIX="$HOME/.local"` entfernt diese Installationsdateien wieder. Quickshell muss auf dem PATH sein. Eine Systeminstallation ist mit `PREFIX=/usr` möglich. Optional lässt sich der Hintergrunddienst nach der Installation mit `systemctl --user enable --now fjord-files.service` aktivieren und mit `systemctl --user disable --now fjord-files.service` wieder deaktivieren.

Für die optionale D-Bus-Aktivierung gibt es den separaten Befehl `make install-dbus-activation PREFIX="$HOME/.local"`. Er kann bei Anfragen an `org.freedesktop.FileManager1` Vorrang vor anderen Dateimanagern erhalten und überschreibt keine vorhandene Fjord-Aktivierungsdatei. Rückgängig: die ausdrücklich dafür angelegte Datei `~/.local/share/dbus-1/services/io.github.febsho.fjordfiles.FileManager1.service` entfernen. Bei abweichendem `XDG_DATA_HOME` kann das Ziel mit `DBUS_SERVICES_DIR="$XDG_DATA_HOME/dbus-1/services"` überschrieben werden; rückgängig gemacht wird dann diese Datei im gewählten Verzeichnis. Eine laufende Instanz beansprucht die Schnittstelle ansonsten nur bei aktivierter Einstellung; ein bestehender Besitzer wird nicht verdrängt.

Eine automatisch übernommene Noctalia-Qt-Palette ist optional; Einzelheiten und Fallbacks stehen unter [Noctalia-Farben](docs/noctalia.md). Archive im ZIP-, TAR-, 7z-, RAR- und CPIO-Format können durchsucht werden; weitere unterstützte Archivformate lassen sich vollständig entpacken, sind aber nicht als virtuelle Ordner eingebunden. Einzelne reguläre Dateien können aus ZIP-, TAR-, 7z- und RAR-Archiven entpackt werden; vorhandene Dateien werden nicht überschrieben. Die Einzeldatei-Extraktion ist auf 512 MiB begrenzt und benötigt Dateisystemunterstützung für `renameat2` mit `RENAME_NOREPLACE`. Bei einem Absturz kann ein privates temporäres Verzeichnis zurückbleiben. Die begrenzte Textbearbeitung speichert eine neue Datei; Näheres steht unter [Textbearbeitung](docs/text-editor.md).

Der Bildbetrachter kann einen Zuschnitt sowie Drehung und Spiegelung als neue PNG-Datei exportieren. Die große Bildansicht und native Bild-Thumbnails (PNG, JPEG, GIF, BMP, TIFF und WebP) laufen in kurzlebigen Helfern mit seccomp-Blockliste und Ressourcenlimits. Externe PDF- und Video-Thumbnailer laufen nur mit Bubblewrap und schreibgeschützten Eingaben; ohne Bubblewrap werden sie deaktiviert. Der große PDF-Viewer und die Medienwiedergabe bleiben eigene, nicht durch diese Thumbnail-Sandboxes isolierte Pfade. Einzelheiten stehen unter [Rummage-Bildvorschau](docs/rummage-preview.md).

Die [Speicherübersicht](docs/storage.md) zeigt Dateisystembelegung, eine lesende Projektinventur und Sweep-Verlauf.

Die Rummage-Bildintegration unterstützt optional die große Bildansicht und den vorhandenen XDG-Thumbnail-Cache; ohne konfigurierten Rummage-Helper bleiben Fjords isolierte Bilddecoder aktiv. Sweep-Scans mit bestätigtem Verschieben in Sweeps eigenen Papierkorbordner sind ebenfalls integriert; das Verschieben schafft nicht unmittelbar Speicherplatz. Einrichtung und Grenzen stehen unter [Rummage-Bildvorschau](docs/rummage-preview.md) und [Sweep-Sicherheit](docs/sweep-safety.md). Einige interne Dux-Namen und Integrationspfade bestehen weiterhin; vollständige Koexistenz, Oberfläche und Dateioperationen müssen noch interaktiv getestet werden.

DOCX, XLSX, PPTX, ODT, ODS und ODP werden als Office-Dokumente erkannt. Die optionale PDF-Vorschau braucht systemweit installiertes oder ausdrücklich konfiguriertes LibreOffice, Bubblewrap und Qt PDF; sie läuft im Sandbox-Prozess und ist in Preview Panel, Content Tab und Quick Look verfügbar. Details und Testgrenzen stehen in [Office-Vorschau](docs/office-preview.md).

Die Audio- und Videovorschau verwendet Qt Multimedia; Codec-Unterstützung hängt von der Laufzeit ab. Im Seitenpanel startet Video stumm, Audio bleibt pausiert. Getesteter Medienpfad und Decodergrenzen stehen unter [Audio- und Videovorschau](docs/media-preview.md).
