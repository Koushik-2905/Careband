# CAREBand AI (NeuroGuard hardware)

**Support, not surveillance.** Wearable possible-fall / possible-seizure detection plus an elder-first care app. Families use the **caretaker phone app** — a web dashboard is not required.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the system sketch.

## What is already wired in this repo

| Layer | What you have |
|-------|----------------|
| Wearable | ESP32, MPU6050, MAX30102, OLED, GSM SMS, BLE GPS from phone |
| Firmware | Seizure-like rules, **fall heuristic**, 30s “Are you okay?”, SOS **hold 2s**, short press **I’m OK**, reminder buzz from phone |
| Elder app `mobile_app/` | Large-button home, medicine, appointments, check-in, consent, Kannada/English intents, BLE gateway |
| Family app `caretaker_app/` | Alarms, consent-filtered status, check-in/medicine, maps only if allowed |
| Backend | Firebase RTDB (`devices/neuroguard-001/care` + events + vitals) |

## Repository layout

```
Neuroguard/
├── src/                 # Documentation website (Vite + React)
├── firmware/            # ESP32 Arduino firmware v2.0
├── mobile_app/          # Flutter companion app
├── ml/                  # TinyML model (your team — placeholder)
├── hardware/            # BOM + wiring
├── firebase/            # RTDB rules
├── caretaker-dashboard/ # Caretaker web app — alerts, Maps, vitals (:5174)
└── PROJECT.md           # Full map
```

## Two apps (enough for family)

| App | User | Purpose |
|-----|------|---------|
| `mobile_app/` | **Elder** | Care home screen + BLE GPS gateway |
| `caretaker_app/` | **Family** | Alerts and consent-filtered summary |

`caretaker-dashboard/` is leftover web UI and is **not** needed for the product.

## Caretaker apps

**Flutter (alarm + notifications):**

```bash
cd caretaker_app
flutter create . --org com.neuroguard --project-name neuroguard_caretaker
flutter pub get
flutter run
```

See [caretaker_app/README.md](caretaker_app/README.md).

**Web dashboard:**

```bash
cd caretaker-dashboard && npm.cmd install && npm.cmd run dev
```

http://localhost:5174 — [caretaker-dashboard/README.md](caretaker-dashboard/README.md).

## Documentation site

**Live:** https://neuroguard-ruby.vercel.app

```bash
npm install && npm run dev
```

## Firmware

See [firmware/README.md](firmware/README.md). Open `firmware/neuroguard_main/neuroguard_main.ino` in Arduino IDE.

## Mobile app

See [mobile_app/README.md](mobile_app/README.md). Requires Flutter SDK.

## Machine learning

Detection uses **5-feature threshold voting** today. When your TinyML model is ready, follow [ml/README.md](ml/README.md) and set `ENABLE_ML` in `firmware/neuroguard_main/config.h`.

## Deploy docs site

```bash
npx vercel --prod
```

## What you should do

1. **Flash firmware** `firmware/neuroguard_main/` after wiring vibe motor on **GPIO 26** (NPN) and SOS on **GPIO 5**. Hold 2 s = SOS. Short press during “Are you okay?” = cancel.
2. **Put SMS numbers** in `firmware/neuroguard_main/config.h` (`CONTACTS[]`).
3. **Add `google-services.json`** to both Flutter apps (same Firebase project). Rebuild APKs.
4. **Elder demo without hardware:** open `mobile_app`, tap *Continue without band*, then medicine / check-in / Emergency / Band → *Demo: possible fall*. Watch `caretaker_app`.
5. **Privacy demo:** turn Location OFF in the elder shield icon; family app should show “Not shared”. Leave *Location in emergencies only* ON if you want maps on SOS.
6. **Say on stage:** possible fall / possible seizure-like event — **not diagnosis**. Kannada phrases should be checked by a native speaker.
7. **Do not** build a separate Node/React dashboard unless judges ask; the family Flutter app is the product surface.

Hardware still on you: coin vibe motor, large SOS button, LiPo if you want a wearable demo. Fall heuristic needs a drop-then-still motion; use the in-app demo button if the stage floor is unreliable.

## License

MIT
