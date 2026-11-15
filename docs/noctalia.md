# Noctalia-Farben

Wenn `colorSource` und Hell/Dunkel-Modus auf „Auto“ stehen, liest Fjord die von Noctalias Qt-Template erzeugte Datei `$XDG_CONFIG_HOME/qt6ct/colors/noctalia.conf` (ohne gesetztes XDG-Verzeichnis unter `~/.config`). Fjord prüft einmal beim Laden und nach Dateiänderungen mit `noctalia msg theme-mode-get`, ob eine Noctalia-Instanz erreichbar ist. Der Aufruf ist auf zwei Sekunden begrenzt. Änderungen an der Palette werden über Dateibeobachtung übernommen, ohne dauerhaftes Polling. Die Helligkeit wird aus der Fensterfarbe bestimmt; die Farbrollen stammen aus der Qt-Palette und sind daher eine Annäherung an Noctalias vollständige Material-Palette.

Fehlt die Datei, ist sie ungültig oder antwortet Noctalia beim Prüfen nicht, verwendet Fjord die bestehende Dux-Farbquelle beziehungsweise das eingestellte Preset. Die explizite Auswahl von Hell/Dunkel oder einer anderen Farbquelle hat Vorrang. Das Qt-Template muss in Noctalia aktiviert sein; Fjord ändert keine Noctalia-Einstellungen. Ein späteres Starten oder Beenden von Noctalia ohne anschließende Änderung der Palettendatei wird erst beim nächsten Laden erkannt.

## Live-Prüfung

Am 15. November 2026 startete das AppImage unter CachyOS/Wayland mit einer privaten XDG-Konfiguration, in der nur Noctalias vorhandene `noctalia.conf` lesbar war. `noctalia msg theme-mode-get` antwortete mit `dark`, `color-scheme-get` mit `wallpaper m3-tonal-spot`; Quickshell protokollierte das Laden und Beobachten der Palettendatei und zeigte ein sichtbares Fjord-Fenster. Die Prüfung bestätigt diesen aktiven Hostpfad, aber keine Live-Änderung der Palette oder die visuelle Übereinstimmung jeder Farbrolle.
