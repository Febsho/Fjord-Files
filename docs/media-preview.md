# Audio- und Videovorschau

Audio und Video werden über Qt Multimedia abgespielt. Welche Container und Codecs funktionieren, hängt von der mitgelieferten beziehungsweise installierten Qt-Multimedia- und FFmpeg-Laufzeit ab; die Dateiendung allein garantiert keine Abspielbarkeit. Fehler des Backends werden in der Vorschau angezeigt.

Im Seitenbereich startet ein ausgewähltes Video stumm, damit sein erstes decodiertes Bild sichtbar wird. Eine ausgewählte Audiodatei startet dort nicht automatisch. In der großen Vorschau stehen Wiedergabe/Pause, Zeitleiste und Lautstärke bereit; Wiedergabegeschwindigkeit sowie Audio- und Untertitelspuren erscheinen dort, wenn das Medium sie enthält. Untertitel werden über dem Videobild gerendert.

Der Live-Test auf CachyOS/Wayland mit dem AppImage bestätigte ein vier Sekunden langes MP4 mit MPEG-4-Video in der Seitenvorschau sowie die Audio-Vorschau einer WAV-Datei. Das ist keine vollständige Codec-, Hardware-Decoding- oder Geräteausgabe-Matrix. Der Qt-Multimedia-Decoder läuft innerhalb des UI-Prozesses und ist nicht durch die Bild-Thumbnail-Sandbox isoliert.
