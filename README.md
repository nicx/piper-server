# Piper (macOS Menüleisten-App)

Eine native macOS-**Menüleisten-App**, die einen lokalen **Piper-Sprachausgabe-Dienst**
([wyoming-piper](https://github.com/rhasspy/wyoming-piper), Wyoming-Protokoll)
direkt auf dem Mac betreibt — **ohne Docker, ohne VM, ohne Cloud**. Gedacht als
Text-to-Speech für Home Assistant (z. B. Ansagen auf einem HomePod) anstelle
eines Online-TTS-Dienstes.

Stack: Swift · SwiftUI `MenuBarExtra` · gebündeltes CPython 3.14
([python-build-standalone](https://github.com/astral-sh/python-build-standalone))
· `SMAppService`.

- **Monochromes Menüleisten-Symbol** (`waveform`, zeigt Status und laufende Downloads).
- **Starten / Stoppen / Neu starten** mit Auto-Restart bei Absturz (Keepalive, exponentielles Backoff) und Mitteilung bei Absturz/Erholung.
- **Stimmenwahl** im Menü: die deutschen Piper-Stimmen, Download mit Fortschrittsanzeige beim ersten Start bzw. bei Auswahl; danach komplett offline.
- **Protokoll** als Live-Fenster und als Datei.
- **Beim Anmelden starten** über `SMAppService` (wird beim ersten Start einmalig eingetragen), Dienst startet mit der App.
- **wyoming-piper aktualisieren** per Knopfdruck (Versionsvergleich gegen PyPI, pip-Upgrade).
- Übernimmt eine verwaiste eigene Instanz, die nach einem App-Absturz noch den Port belegt.

## Speicherort

Alles, was die App schreibt, liegt in **einem** Ordner:

```
~/Library/Piper/venv/     Python-Umgebung mit wyoming-piper (beim ersten Start angelegt)
~/Library/Piper/voices/   Stimmen (<name>.onnx + <name>.onnx.json)
~/Library/Piper/logs/     piper.log
```

Die Einstellungen liegen wie bei jeder macOS-App in den Standard-Preferences
(`com.nicx.piper-server`).

## Stimmen

| Stimme | Qualität | Größe | Lizenz der Trainingsdaten |
|---|---|---|---|
| Thorsten | hoch / mittel / niedrig | 114 / 63 / 63 MB | CC0 |
| Thorsten (emotional) | mittel | 76 MB | CC0 |
| Kerstin | niedrig | 63 MB | CC0 |
| Ramona, Karlsson | niedrig | 63 MB | M-AILABS |
| Eva K. | sehr niedrig | 20 MB | M-AILABS |
| Pavoque | niedrig | 63 MB | CC BY-NC-SA 4.0 |
| MLS (236 Sprecher) | mittel | 76 MB | CC BY 4.0 |

Standard ist **de_DE-thorsten-high**. Quelle:
[huggingface.co/rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices)
(Lizenzangaben aus den jeweiligen Model Cards). Fordert Home Assistant eine
andere, noch nicht geladene Stimme an, lädt wyoming-piper sie selbst nach.

## Home Assistant anbinden

1. **Einstellungen → Geräte & Dienste → Integration hinzufügen → Wyoming Protocol**
2. Host `127.0.0.1` (HA auf demselben Mac) bzw. die IP des Macs, Port `10200`.
3. Die neue TTS-Entity (`tts.piper`) in `tts.speak` verwenden:

```yaml
action: tts.speak
target:
  entity_id: tts.piper
data:
  media_player_entity_id: media_player.<dein_player>
  message: "Die Waschmaschine ist fertig."
  cache: true
```

Läuft Home Assistant auf einem anderen Rechner, in den Einstellungen
„Erreichbar für: Alle Geräte im Netz“ wählen — der Dienst hat **keine
Authentifizierung**.

## Bauen

```bash
./Scripts/bundle-runtime.sh                                  # CPython 3.14 → ./Runtime (einmalig)
CODESIGN_IDENTITY="<deine Identität>" ./Scripts/make-app.sh  # dist/Piper.app, signiert
open dist/Piper.app
```

`make-app.sh` bricht ab, wenn die App gerade aus `dist/` läuft (der Build würde
das laufende Bundle löschen). Ohne `CODESIGN_IDENTITY` wird ad-hoc signiert;
dann vergisst macOS Berechtigungen (Mitteilungen, Anmeldeobjekt) bei jedem
Rebuild.

## Lizenz

MIT, siehe [LICENSE](LICENSE). Zur Laufzeit per pip installiert und **nicht**
Teil dieses Repos: wyoming-piper (MIT), piper-tts (GPL-3.0-or-later),
onnxruntime (MIT). Die Stimmen haben eigene Lizenzen (siehe Tabelle).
