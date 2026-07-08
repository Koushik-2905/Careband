# NeuroGuard Caretaker App (`caretaker_app`) — **main app**

For **family / nurses**. Loud alarm, vibration, maps, and live vitals from Firebase.

| App | Folder | Phone |
|-----|--------|--------|
| **Caretaker (main)** | `caretaker_app/` | Caregiver |
| Patient GPS relay | `mobile_app/` | Patient — BLE + GPS only |

## Setup

```bash
cd caretaker_app
flutter create . --org com.neuroguard --project-name neuroguard_caretaker
flutter pub get
```

`google-services.json` → `caretaker_app/android/app/` (package `com.neuroguard.neuroguard_caretaker`).

Patient app uses package `com.neuroguard.neuroguard_app` in the **same** Firebase project.

## Run

```bash
flutter run
flutter build apk --release
```

## Data flow

```
ESP32 (pulse + accel + gyro) ──BLE──► Patient GPS app ──Firebase──► Caretaker app (this)
                              └──SMS──► Emergency contacts (phone GPS in SMS text)
```

GPS on alerts comes from the **patient phone**, not the SIM module.
