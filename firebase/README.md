# Firebase (NeuroGuard)

## Setup

1. Create project at https://console.firebase.google.com
2. Enable **Realtime Database** and **Cloud Messaging**
3. Run `flutterfire configure` in `mobile_app/`
4. Deploy rules from `database.rules.json` (must allow `care` and `activeAlert`, not only `vitals`/`events`). In Firebase Console → Realtime Database → Rules, paste that file, or run `firebase deploy --only database`.

## Data shape

```
devices/neuroguard-001/vitals
  state, hr, conf, ml, gpsOk, lat, lng, ts   # updated ~every 2s from Flutter (BLE)

devices/neuroguard-001/events/{pushId}
  type: FALL_SUSPECTED | SEIZURE_SUSPECTED | SOS | NEED_HELP | ...
  ts, conf, hr, lat, lng, valid

devices/neuroguard-001/care
  consent, profile, medicine, appointment, checkin, escalation, insight, audit
```

Family UI must hide fields the elder turned off. Default: emergency/wellbeing/medicine ON; heart-rate, activity, always-on location OFF; location-in-emergency ON.

Caretaker dashboard (`caretaker-dashboard/`) and **caretaker Flutter app** (`caretaker_app/`) subscribe to both paths when Firebase is configured.

### Optional: FCM when caretaker app is killed

Deploy a Cloud Function that sends to topic `caretaker_neuroguard-001` when a new event is written (caretaker app already subscribes to this topic).

Adjust rules in `database.rules.json` for production auth.
