# CAREBand elder app (`mobile_app`)

**Role:** Runs on the **elder’s phone**. Large-button care UI (medicine, appointments, check-in, call family, emergency) plus BLE GPS gateway to the wristband. Forwards events to Firebase for `caretaker_app/`.

Privacy toggles live in the shield icon. Judges can tap **Continue without band (demo)** on the scan screen.

## Setup

```powershell
cd mobile_app
flutter create . --org com.neuroguard --project-name neuroguard_app
flutter pub get
```

Add `google-services.json` to `android/app/` (same Firebase project as caretaker app).

## Run / build

```bash
flutter run
flutter build apk --release
```

## What it does

- Scan and connect to **NeuroGuard** (ESP32)
- Relay **phone GPS** to wristband over BLE
- Push vitals/alerts to Firebase (`devices/neuroguard-001/`)
- Keep app open in background while patient wears the band

## Permissions (Android)

Bluetooth scan/connect + fine location (required for GPS).
