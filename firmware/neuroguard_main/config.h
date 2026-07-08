#pragma once

// ── Build modes ─────────────────────────────────────────────────
#define BOOT_SAFE_MODE 0
#define SERIAL_BAUD 115200
#define DISABLE_BROWNOUT 1
#define I2C_TIMEOUT_MS 50
#define BOOT_SKIP_I2C 0

#define SIMULATION_MODE 0
#define ENABLE_GSM 1
#define ENABLE_OLED 1
#define ENABLE_HR_SENSOR 1
#define ENABLE_BLE_ON_BOOT 1
#define ENABLE_ML 0

#if BOOT_SAFE_MODE
#undef ENABLE_ML
#define ENABLE_ML 0
#undef ENABLE_GSM
#define ENABLE_GSM 0
#define ENABLE_BLE_ON_BOOT 1
#endif

#define ML_INFERENCE_INTERVAL_MS 2000

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
static const char *CONTACTS[] = {"+919876543210", "+919876543211"};
static const int CONTACT_COUNT = 2;

// ── Detection ───────────────────────────────────────────────────
#define SAMPLE_RATE 100
#define WINDOW_SIZE 200
#define CONFIDENCE_THR 0.80f
#define CANCEL_WINDOW_MS 5000
#define GPS_STALE_MS 30000

// GPS: phone BLE only (no SIM cell-tower fallback)
#define ENABLE_GSM_LBS 0

// Pulse (MAX30102)
#define HR_LOW 50
#define HR_HIGH 120

// Accelerometer (MPU6050 raw LSB)
#define ACCEL_AVG_THR 25000.0f
#define ACCEL_PEAK_THR 30000.0f

// Gyroscope (MPU6050 raw LSB, ±250 dps range)
#define GYRO_AVG_THR 12000.0f
#define GYRO_PEAK_THR 18000.0f

#define USE_HARDWARE_LOGIC 1
#define HARDWARE_TICK_MS 20
#define ML_ALERT_THR 0.65f
