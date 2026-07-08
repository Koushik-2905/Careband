# NeuroGuard Patient GPS App (`mobile_app`)

**Role:** Runs on the **patient's phone**. Connects to the wristband over BLE and **sends GPS every 10 seconds**. Forwards vitals and seizure events to **Firebase** for the caretaker app.

This is **not** the main caregiver app — use `caretaker_app/` for alarms, maps, and alerts.

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
