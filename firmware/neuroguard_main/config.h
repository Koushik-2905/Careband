#pragma once

// ── Build modes ─────────────────────────────────────────────────
#define BOOT_SAFE_MODE 0
#define SERIAL_BAUD 115200
#define DISABLE_BROWNOUT 1
#define I2C_TIMEOUT_MS 150
#define MPU_FAIL_STREAK_MAX 8
#define MPU_ZERO_STREAK_MAX 15
#define MPU_RECOVER_COOLDOWN_MS 5000
#define BOOT_SKIP_I2C 0

#define SIMULATION_MODE 0
#define ENABLE_GSM 1
#define ENABLE_OLED 1
#define ENABLE_HR_SENSOR 1
#define ENABLE_BLE_ON_BOOT 1
#define ENABLE_ML 0  // SeizureDetector handles detection; ML off saves flash

// Set to 1 for hackathon / bench testing (shake wristband to trigger alert).
// Set to 0 for stricter real-world thresholds.
#define DEMO_MODE 1

#if DEMO_MODE
// Bench test: inject fake BPM so shake-only triggers 5s timer (like original test sketch).
// Set to 0 to require real tachycardia from MAX30102.
#define DEMO_INJECT_BPM 125
#else
#define DEMO_INJECT_BPM 0
#endif

#if BOOT_SAFE_MODE
#undef ENABLE_ML
#define ENABLE_ML 0
#undef ENABLE_GSM
#define ENABLE_GSM 0
#define ENABLE_BLE_ON_BOOT 1
#endif

#define ML_INFERENCE_INTERVAL_MS 2000
#define ML_CONFIDENCE_BLEND 0.35f  // 35% ML + 65% threshold when USE_HARDWARE_LOGIC is 0

// ── Pins (ESP32 DevKit) ─────────────────────────────────────────
#define SOS_BTN_PIN 5
#define BUZZER_PIN 4
#define VIB_MOTOR_PIN 26
#define LED_PIN 27
#define MPU_INT_PIN 35
#define I2C_SDA 21
#define I2C_SCL 22
#define GSM_RX 16
#define GSM_TX 17

// ── BLE UUIDs (must match mobile_app/lib/constants/ble_uuids.dart) ──
#define SERVICE_UUID "12345678-1234-1234-1234-123456789abc"
#define CHAR_UUID_GPS_WRITE "12345678-1234-1234-1234-123456789c9c"
#define CHAR_UUID_ALERT "12345678-1234-1234-1234-123456789abd"
#define CHAR_UUID_DATA "12345678-1234-1234-1234-123456789abe"
#define CHAR_UUID_CONFIG "12345678-1234-1234-1234-123456789abf"

// ── Emergency SMS contacts (E.164 format) ─────────────────────
static const char *CONTACTS[] = {"+917603926572"};
static const int CONTACT_COUNT = 1;

// ── Detection ───────────────────────────────────────────────────
#define SAMPLE_RATE 100
#define WINDOW_SIZE 200
#define CONFIDENCE_THR 0.80f
#define SEIZURE_MAG_THR 2.5f
#define ZCR_LOW 6.0f
#define ZCR_HIGH 16.0f
#define CANCEL_WINDOW_MS 5000
#define ALERT_COOLDOWN_MS 15000
#define GPS_STALE_MS 30000

static const char SMS_ALERT_TEXT[] =
    "ALERT: Patient requires immediate assistance! Tonic-Clonic Seizure Detected.";

// GPS: phone BLE only (no SIM cell-tower fallback)
#define ENABLE_GSM_LBS 0

// Pulse (MAX30102)
#define HR_LOW 50
#define HR_HIGH 120
#define HR_ALERT_LOW 40  // ignore BPM 40-50 during finger placement warmup

#define USE_HARDWARE_LOGIC 1
#define HARDWARE_TICK_MS 20

// Accelerometer (MPU6050 raw LSB)
#if DEMO_MODE
#define ACCEL_AVG_THR 10000.0f
#define ACCEL_PEAK_THR 15000.0f
#define GYRO_AVG_THR 8000.0f
#define GYRO_PEAK_THR 12000.0f
#define DETECT_SUSTAIN_MS 5000  // abnormal A+G must hold this long, then alert fires immediately
#define DETECT_DEBOUNCE_TICKS (DETECT_SUSTAIN_MS / HARDWARE_TICK_MS)
#else
#define ACCEL_AVG_THR 25000.0f
#define ACCEL_PEAK_THR 30000.0f
#define GYRO_AVG_THR 12000.0f
#define GYRO_PEAK_THR 18000.0f
#define DETECT_SUSTAIN_MS 1000
#define DETECT_DEBOUNCE_TICKS (DETECT_SUSTAIN_MS / HARDWARE_TICK_MS)
#endif

#define DETECT_PROGRESS_TICKS (1000 / HARDWARE_TICK_MS)  // log every 1 s while motion sustained
#define ML_ALERT_THR 0.65f
