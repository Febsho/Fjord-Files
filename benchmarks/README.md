# Performance-Messungen

Die JSON-Dateien enthalten Messungen des Daemons und vergleichen Fjord mit dem unveränderten Dux-Files-Commit `7a89d083` auf derselben CachyOS-Installation. Beide Läufe verwendeten denselben Benchmark, 1.000 kleine Dateien, drei Wiederholungen und Btrfs auf einer AMD Ryzen 5 7600X3D Maschine.

| Messung | Dux | Fjord |
| --- | ---: | ---: |
| Daemon bereit | 8,0 ms | 7,8 ms |
| Leerlauf-RSS | 22,2 MiB | 22,8 MiB |
| Erste Verzeichnis-Seite | 13,8 ms | 14,2 ms |
| Textvorschau | 2,5 ms | 2,5 ms |
| isoliertes 512px-Thumbnail | 11,4 ms | 27,5 ms |
| vollständige Namenssuche | 3,0 ms | 3,1 ms |
| Kopie, 128 MiB | 96,8 ms | 82,8 ms |
| Kopie, 1.000 kleine Dateien | 114,9 ms | 115,6 ms |

Die Thumbnail-Messung in Fjord enthält Bubblewrap- und Prozessstartkosten; Dux verwendet dort seinen ursprünglichen Thumbnailpfad. Das ist ein Sicherheits-/Latenzvergleich und kein identischer Decodervergleich. Die Kopien liefen auf einem komprimierten Btrfs-Subvolume. Die Caches waren nicht kontrolliert und es gab nur drei Wiederholungen; die Werte sind daher ein lokaler Ausgangspunkt, keine belastbare allgemeine Rangliste.

Die Rohdaten messen den Daemon, nicht UI-Rendering. Ein späterer Lauf ergänzt den sichtbaren GUI-Kaltstart, aber ein Warmstart und vollständig gerenderter Frame sind weiterhin offen. Sweep war nicht installiert, daher fehlt der Sweep-Scan. Der Benchmark-Daemonstart ist ein Headless-Messwert. Rohdaten und Binär-Hashes:

- [Fjord](results/fjord-x86_64-2026-11-15.json)
- [Dux upstream](results/dux-upstream-x86_64-2026-11-15.json)

Der AppImage-GUI-Lauf auf tmpfs verwendet 10.000 Fixture-Einträge und drei Wiederholungen; Umbriel meldete das Fenster nach 1.204 ms Median. Er ist kein direkter GUI-Vergleich mit Dux, dessen Messdatei keinen GUI-Start enthält: [Fjord mit GUI](results/cachyos-2026-11-15-gui.json). Der GUI-Wert umfasst isolierten Vordergrundstart bis zum vom Compositor gemeldeten sichtbaren Fenster, nicht den ersten gerenderten Frame. Vergleiche mit den Btrfs-Messungen oben sind wegen des anderen Dateisystems nicht direkt aussagekräftig.

Ein aktualisierter Lauf mit dem checksum-geprüften Sweep v0.5.2 misst zusätzlich den echten Sweep-Scan des Fixtures: 145,7 ms Median; der sichtbare GUI-Kaltstart lag bei 1.147 ms. Rohdaten und SHA-256 von Sweep- und AppImage-Binary stehen in [cachyos-2026-11-15-gui-sweep-v0.5.2.json](results/cachyos-2026-11-15-gui-sweep-v0.5.2.json). Auch dieser Lauf ist tmpfs und damit nicht direkt mit der Btrfs-Tabelle oben vergleichbar.

Reproduktion: `python3 scripts/benchmark.py --binary core/bin/dfiles --files 1000 --repeats 3 --large-mib 128 --temp-parent /home/$USER`. Verwende für den Dux-Vergleich einen Build des angegebenen unveränderten Commits. Der temporäre Pfad muss kurz sein, weil Unix-Domain-Sockets eine begrenzte Pfadlänge haben.
