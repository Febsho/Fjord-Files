# Architekturentscheidung und Plan

Stand: 15. November 2026. Arbeitsname: Fjord Files.

## Entscheidung

Dux Files (`7a89d08`) ist die Basis: Go-Daemon, Unix-Socket-Protokoll und Quickshell/QML bleiben erhalten. Tabs, zwei Bereiche, Datei-Jobs, Netzwerk und vorhandene Vorschauen werden weiterverwendet, nicht neu geschrieben. Die Oberfläche und der Backend-Prozess müssen gemeinsam versioniert werden. Eine eigene App-ID und getrennte Laufzeit- und Einstellungsdaten verhindern Kollisionen mit Dux. Die Registrierung als Dateimanager und Portal bleibt ausdrücklich opt-in. Systeminstallationen erfolgen nicht automatisch.

Rummage (`2789dd25`) ist ein eigenständiger C++20-/Wayland-Dateimanager. Seine Preview-Helfer verwenden Dateideskriptoren, SOCK_SEQPACKET, validierte Antworten und versiegelten Speicher; Decoder laufen getrennt mit seccomp und optional Landlock. Die internen Protokolle sind keine zugesagte externe API. Ein optionaler Adapter spricht das überprüfte interne Protokoll 4; Einrichtung und Einschränkungen stehen in [rummage-preview.md](rummage-preview.md). Die große Bildansicht und native Bild-Thumbnails verwenden standardmäßig kurzlebige Fjord-Selbststart-Helfer mit seccomp-Blockliste, Dateideskriptoren und Ressourcenlimits. Weitere Decoderpfade, insbesondere externe Thumbnailer und Medienvorschauen, sind davon nicht umfasst.

Sweep (`c3cd0bb8`) ist primär ein Bun/TypeScript-Monorepo mit optionaler Rust-Engine, nicht eine ausschließlich native Rust-CLI. `scan --json` bzw. `--json-stream`, `plan` und `apply --plan` sowie das Protokoll Version 1 bilden die geeignete Integrationsgrenze. Scans bleiben lesend. Löschungen dürfen ausschließlich über Sweeps geprüften Plan-/Apply-Pfad erfolgen; kein eigener Umweg. Scan, Auswahl und bestätigtes Verschieben per `apply --trash` sind über die CLI integriert; Einzelheiten und Grenzen stehen in [sweep-safety.md](sweep-safety.md). Das Verschieben in Sweeps eigenen Papierkorbordner gibt zunächst keinen Speicher frei.

Dux und Sweep stehen unter MIT; Rummage unter MIT mit weiteren Hinweisen in `THIRD_PARTY.md` (u. a. Wuffs MIT/Apache-2.0). Dux-QML- und Font-Lizenzen bleiben erhalten. Die tatsächlich in `cmd/dfiles` eingebundenen Go-Pakete wurden mit go-licenses v1.6.0 ermittelt; die Übersicht und vollständigen Lizenztexte sind in `docs/third-party-go-licenses.csv` und `assets/licenses/fjord-go/` abgelegt und werden mit den Arch- und AppImage-Artefakten ausgeliefert. Das umfasst keine separat installierten optionalen Helfer oder deren Abhängigkeiten. Repositories liegen getrennt; es wird noch kein Code aus Rummage oder Sweep kopiert.

## Schritte

1. Dux rekursiv auschecken, reproduzierbar lokal bauen, eigene Identität und opt-in-Desktopintegration schaffen; Navigation und Dateioperationen testen.
2. Bestehende Vorschauen und Quick Look anhand echter Funktionstests bewerten; dann fehlende Viewer mit MIME-basierter Registry und Content-Tabs ergänzen.
3. Rummage-Helfer und versionierten Adapter isoliert evaluieren, Benchmarks und Sandbox-Tests durchführen.
4. Sweep über seine versionierte CLI einbinden und Sicherheitsprüfungen/Plan erneut vor Ausführung validieren.
5. Desktopintegration, Noctalia-Themes, Performance, Paketierung und dokumentierte Tests ergänzen.

## Grenzen

Dies ist ein Entwicklungsstand, keine Zusicherung der Abnahmekriterien. Dux' vorhandene Funktionen sind nicht automatisch in dieser Umgebung end-to-end verifiziert. Keine Systemstandardwerte oder Portaleinstellungen werden geändert. Für spätere Benchmarks müssen Hardware, Dateisystem und Bedingungen dokumentiert werden.
