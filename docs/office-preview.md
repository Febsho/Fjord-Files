# Office-Vorschau

DOCX, XLSX, PPTX sowie ODT, ODS und ODP werden anhand des ZIP-Inhalts erkannt. Ist ein System-LibreOffice unter `/usr`, `/bin` oder `/opt` oder eine ausdrücklich konfigurierte Runtime, Bubblewrap und Qt PDF vorhanden, konvertiert Fjord das Dokument asynchron in PDF und zeigt es mit dem integrierten PDF-Betrachter im Preview Panel, Content Tab und Quick Look an. Ohne diese Voraussetzungen bleibt die Vorschau deaktiviert und die Standardanwendung kann die Datei öffnen. Eine abweichende Runtime kann über die absoluten Pfade `FJORD_OFFICE_RUNTIME_ROOT` und `FJORD_OFFICE_CONVERTER` angegeben werden; nur der ausgewählte Runtime-Baum wird schreibgeschützt in die Sandbox eingebunden.

Der Konverter läuft in einer Bubblewrap-Umgebung ohne Netzwerk. Nur Systemlaufzeit-Verzeichnisse sind schreibgeschützt sichtbar; das Dokument wird aus einer privaten Arbeitskopie schreibgeschützt eingehängt. Ausgabe und temporäres Benutzerprofil liegen in beschreibbaren Sandbox-Verzeichnissen. Eingaben über 64 MiB, PDFs über 64 MiB und Konvertierungen über 60 Sekunden werden abgelehnt. Der Cache liegt unter `XDG_CACHE_HOME/fjord-files/office-previews`, ist auf 256 MiB begrenzt und wird nach Quellpfad, Dateigröße und Änderungszeit versioniert. Die anschließende PDF-Darstellung läuft über Qt PDF im Quickshell-Prozess.

Die Konvertierung selbst ist ein optionaler externer Renderer. Der QML-Test lädt den Office-Viewer und stellt eine PDF-Testseite dar; die Konvertierungsantwort wird dabei simuliert. Ein Go-Integrationstest erzeugt mit der explizit konfigurierten LibreOffice-Runtime in Bubblewrap ein PDF aus einer DOCX-Fixture und prüft den Cache-Treffer. Zusätzlich wurde auf CachyOS/Wayland der echte AppImage-Fluss mit einer explizit konfigurierten lokalen LibreOffice-Runtime geprüft: eine echte DOCX-Fixture wurde in Bubblewrap konvertiert und anschließend über Quick Look als PDF-Seite mit dem erwarteten Dokumenttext sichtbar gerendert. Das bestätigt diesen DOCX-Pfad, ersetzt aber keine Formatmatrix für ODT, Tabellen, Präsentationen oder weitere LibreOffice-Versionen. Reproduktion des Integrationstests mit einer Runtime:

```sh
FJORD_TEST_OFFICE_RUNTIME_ROOT=/absoluter/pfad/zur/runtime \
FJORD_TEST_OFFICE_CONVERTER=/absoluter/pfad/zu/soffice \
CGO_ENABLED=0 go test ./internal/ipc -run TestOfficePreviewSandboxedConversion
```
