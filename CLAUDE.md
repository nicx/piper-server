# Piper macOS Menüleisten-App — Project Guide

## Was das ist

Native macOS-Menüleisten-App (SwiftUI `MenuBarExtra`, Swift Package Manager), die
**wyoming-piper** (Piper-TTS über das Wyoming-Protokoll) als überwachten
Python-Subprozess betreibt — für Home-Assistant-Sprachausgabe, ohne Docker.
Schwesterprojekt von `esphome`, `home-assistant`, `matter-server` (Codeklone:
bei Problemen zuerst dort greppen).

**Autor:** nicx (25152397+nicx@users.noreply.github.com). Repo ist **öffentlich**:
keine IPs, Hostnamen, Entity-IDs, Mailadressen oder Benutzerpfade committen.

## Architektur

- Nur **CPython 3.14** wird gebündelt (`Scripts/bundle-runtime.sh`,
  `PY_VERSION=3.14.6`, `PBS_RELEASE=20260610`). piper-tts hat ein abi3-arm64-Wheel,
  onnxruntime cp314-arm64-Wheels.
- Beim ersten Start: venv + `pip install wyoming-piper` nach `~/Library/Piper/venv`
  (`EnvironmentManager`).
- **Alles in einem Ordner** `~/Library/Piper/{venv,voices,logs}` — bewusst anders als
  die Schwester-Apps (die loggen nach `~/Library/Logs/<App>`).
- Start: `python -m wyoming_piper --uri tcp://<bind>:<port> --voice <id> --data-dir ~/Library/Piper/voices`.
  Port 10200 (Wyoming-Standard), Bind standardmäßig `127.0.0.1`.
- `VoiceManager` lädt die Standardstimme VOR dem Start mit Fortschritt
  (URLSession, Temp-Datei → move, Config zuerst, Modell zuletzt). wyoming-piper
  findet Stimmen flach als `<id>.onnx` + `<id>.onnx.json`; andere angeforderte
  Stimmen lädt es selbst nach. `--local-files-only` betrifft nur das
  OmniVoice-Backend, nicht Piper-Stimmen.
- `ServerController`: Status `running` erst, wenn der Port Verbindungen annimmt.
  Verwaiste Instanz wird per Port-Bind-Probe + `lsof` + Kommandozeilen-Prüfung
  übernommen (Muster aus esphome). Kein Netzwerk-Gate (Dienst läuft offline).
- `describe` meldet ~174 Stimmen als `installed=True` (Upstream-Verhalten:
  „verfügbar, wird bei Bedarf geladen").
- Erster Start registriert die App einmalig als Anmeldeobjekt (`didOfferLoginItem`).
- Bundle-ID `com.nicx.piper-server`. Runtime-Override-Env: `PIPER_RUNTIME_DIR`.

## Bauen

```bash
./Scripts/bundle-runtime.sh                               # einmalig / bei Python-Update
CODESIGN_IDENTITY="nicx Selfsign" ./Scripts/make-app.sh   # NIE ad-hoc
```

- `make-app.sh` pinnt `SDKROOT` auf `MacOSX26.sdk` (Beta-SDK 27 ohne SwiftUI-Makros).
- Build-Guard: bricht ab, wenn `dist/Piper.app` läuft — App läuft produktiv aus `dist/`.
- JIT-/Library-Validation-Entitlements sind Pflicht (onnxruntime-.so aus dem venv).

## Gotchas

- App **nicht aus der Sandbox/headless starten** (Port 10200, Geister-Instanz) — der Nutzer startet sie selbst.
- Kein Auth im Wyoming-Protokoll → Bind `0.0.0.0` nur bewusst.
