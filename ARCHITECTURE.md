# CAREBand AI — system architecture

**Support, not surveillance.** Family uses the **caretaker phone app** (no separate web dashboard required). Detection is **possible-event**, not diagnosis.

```
ELDER
  │
  ▼
┌─────────────────────────────────────────────┐
│  CAREBand wearable (ESP32)                  │
│  MPU6050 · MAX30102 · OLED                  │
│  Buzzer · vibe (GPIO 26) · SOS (GPIO 5)     │
│  Possible fall / seizure-like · I’m OK gate │
└───────────────┬───────────────┬─────────────┘
                │ BLE (primary) │ GSM SMS fallback
                ▼               │  (if phone absent)
┌─────────────────────────────────────────────┐
│  Elder phone app  (Flutter · mobile_app)    │
│  Gateway: GPS every 10s · BLE events        │
│  5 big buttons · Kannada/English intents    │
│  Medicine · check-in · consent switches     │
└──────────────────────┬──────────────────────┘
                       │ HTTPS → Firebase RTDB
                       ▼
┌─────────────────────────────────────────────┐
│  Care backend (Firebase)                    │
│  vitals · events · care/consent             │
│  medicines · check-ins · escalation L1–L4   │
│  insights · audit                           │
│  Every family read is consent-filtered      │
└──────────────────────┬──────────────────────┘
                       ▼
┌─────────────────────────────────────────────┐
│  Family app  (Flutter · caretaker_app)      │
│  Status · check-in · medicine · alerts      │
│  Location / HR only if the elder allowed    │
└─────────────────────────────────────────────┘
```

## Escalation (state machine)

```
L1  Reminder (phone + band buzz)
L2  Second check-in
L3  Notify family (consent-filtered text)
L4  Emergency: possible fall/seizure with no “I’m OK”, SOS hold 2s, or I NEED HELP
     Location attached only if location OR location-in-emergency is ON
```

Short press during a suspected event = **I’m OK** (cancel, log, no L4).
SOS hold 2 seconds skips the confirm window and goes to L4.

## Data the family never sees by default

Heart rate · detailed activity · always-on location · raw accelerometer.
Raw sensor streams stay on the band/phone; Firebase stores **event summaries**.
