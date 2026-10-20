// Sensors + integrated SeizureDetector (bench-tested algorithm).
#include "hardware_logic.h"
#include "config.h"
#include "seizure_detector.h"

#include <Wire.h>
#include "MAX30105.h"
#include "heartRate.h"
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <math.h>
#include <string.h>

MAX30105 particleSensor;
Adafruit_MPU6050 mpu;
SeizureDetector patientMonitor;

bool gHrSensorOk = false;
bool gMpuOk = false;
uint8_t gMpuFailStreak = 0;

float gLastAx = 0, gLastAy = 0, gLastAz = 0;
float gLastGx = 0, gLastGy = 0, gLastGz = 0;
bool gLastMpuEventOk = false;

static bool readMpu6050Direct(float &ax, float &ay, float &az, float &gx, float &gy, float &gz) {
  Wire.beginTransmission(0x68);
  Wire.write(0x3B);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom((uint8_t)0x68, (size_t)14, (bool)true) != 14) return false;

  auto read16 = []() {
    int16_t hi = Wire.read();
    int16_t lo = Wire.read();
    return (int16_t)((hi << 8) | lo);
  };

  int16_t rawAx = read16();
  int16_t rawAy = read16();
  int16_t rawAz = read16();
  read16();  // skip temperature
  int16_t rawGx = read16();
  int16_t rawGy = read16();
  int16_t rawGz = read16();

  ax = rawAx / 16384.0f * 9.80665f;
  ay = rawAy / 16384.0f * 9.80665f;
  az = rawAz / 16384.0f * 9.80665f;
  gx = rawGx / 131.0f * 0.0174532925f;
  gy = rawGy / 131.0f * 0.0174532925f;
  gz = rawGz / 131.0f * 0.0174532925f;
  return true;
}

static bool readMpu6050Sample(float &ax, float &ay, float &az, float &gx, float &gy, float &gz) {
  // Direct register read is reliable on this board; getEvent() can return zeros after BLE init.
  if (readMpu6050Direct(ax, ay, az, gx, gy, gz)) {
    float mag = sqrtf((ax * ax) + (ay * ay) + (az * az));
    if (mag > 1.0f) return true;
  }

  sensors_event_t a, g, temp;
  if (mpu.getEvent(&a, &g, &temp)) {
    ax = a.acceleration.x;
    ay = a.acceleration.y;
    az = a.acceleration.z;
    gx = g.gyro.x;
    gy = g.gyro.y;
    gz = g.gyro.z;
    float mag = sqrtf((ax * ax) + (ay * ay) + (az * az));
    if (mag > 1.0f) return true;
  }
  return false;
}

static void configureMpu6050() {
  mpu.setAccelerometerRange(MPU6050_RANGE_2_G);
  mpu.setGyroRange(MPU6050_RANGE_250_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_44_HZ);
}

long gLastIrValue = 0;

const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;
float beatsPerMinute = 0;
int beatAvg = 0;

void hardwareLogicInit() {
  Serial.println("[SENSORS] MPU6050 + MAX30102 + SeizureDetector...");

  gMpuOk = mpu.begin();
  if (!gMpuOk) {
    Serial.println("[SENSORS] MPU6050 not found");
  } else {
    configureMpu6050();
    float ax, ay, az, gx, gy, gz;
    if (readMpu6050Sample(ax, ay, az, gx, gy, gz)) {
      Serial.printf("[SENSORS] MPU6050 OK  ax=%.2f ay=%.2f az=%.2f\n", ax, ay, az);
    } else {
      Serial.println("[SENSORS] MPU6050 found but read failed");
      gMpuOk = false;
    }
  }
  delay(100);

  if (!particleSensor.begin(Wire, I2C_SPEED_STANDARD, 0x57)) {
    if (!particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
      Serial.println("[SENSORS] MAX30102 not found");
      gHrSensorOk = false;
    } else {
      particleSensor.setup();
      particleSensor.setPulseAmplitudeRed(0x1F);
      particleSensor.setPulseAmplitudeIR(0x1F);
      gHrSensorOk = true;
      Serial.printf("[SENSORS] MAX30102 OK @ default addr  IR=%ld\n", particleSensor.getIR());
    }
  } else {
    particleSensor.setup();
    particleSensor.setPulseAmplitudeRed(0x1F);
    particleSensor.setPulseAmplitudeIR(0x1F);
    gHrSensorOk = true;
    Serial.printf("[SENSORS] MAX30102 OK @ 0x57  IR=%ld\n", particleSensor.getIR());
  }

  Serial.println("[SENSORS] SeizureDetector armed (5s tremor + HR spike)");
}

HardwareLogicState hardwareLogicTick() {
  HardwareLogicState out;
  unsigned long now = millis();

  out.pulseAbnormal = false;
  out.accelAbnormal = false;
  out.gyroAbnormal = false;
  out.fingerPresent = false;
  out.isAbnormal = false;
  out.beatAvg = beatAvg;
  strcpy(out.status, "NORMAL");

  if (gHrSensorOk) {
    long irValue = particleSensor.getIR();
    gLastIrValue = irValue;
    out.irValue = irValue;

    if (irValue >= 10000) {
      out.fingerPresent = true;
      if (checkForBeat(irValue)) {
        long delta = now - lastBeat;
        lastBeat = now;
        beatsPerMinute = 60.0f / (delta / 1000.0f);
        if (beatsPerMinute > HR_LOW && beatsPerMinute < HR_HIGH + 40) {
          rates[rateSpot++] = (byte)beatsPerMinute;
          rateSpot %= RATE_SIZE;
          int total = 0;
          for (byte i = 0; i < RATE_SIZE; i++) total += rates[i];
          beatAvg = total / RATE_SIZE;
        }
      }
      out.beatAvg = beatAvg;
    } else {
      beatAvg = 0;
      out.beatAvg = 0;
    }
  }

  gLastMpuEventOk = false;
  if (gMpuOk) {
    float ax, ay, az, gx, gy, gz;
    if (readMpu6050Sample(ax, ay, az, gx, gy, gz)) {
      gMpuFailStreak = 0;
      gLastMpuEventOk = true;
      gLastAx = ax;
      gLastAy = ay;
      gLastAz = az;
      gLastGx = gx;
      gLastGy = gy;
      gLastGz = gz;

      float bpm = (float)(beatAvg > 0 ? beatAvg : 0);
#if DEMO_INJECT_BPM > 0
      bpm = (float)DEMO_INJECT_BPM;
#endif
      bool isSeizing = patientMonitor.detect(gLastAx, gLastAy, gLastAz, gLastGx, gLastGy, gLastGz,
                                           bpm, now);
      out.isAbnormal = isSeizing;
      out.accelMag = patientMonitor.debug_currentMag;
      out.gyroMag = patientMonitor.getCurrentFreq();

      if (isSeizing) {
        strcpy(out.status, "SEIZURE DETECTED");
      } else if (patientMonitor.debug_timerSeconds > 0.0f) {
        strcpy(out.status, "DETECTING");
      } else {
        strcpy(out.status, "NORMAL");
      }

      out.accelAbnormal = patientMonitor.debug_isShaking;
      out.gyroAbnormal = patientMonitor.debug_isTachycardic;
      out.pulseAbnormal = patientMonitor.debug_isTachycardic;
    } else if (++gMpuFailStreak >= MPU_FAIL_STREAK_MAX) {
      gMpuFailStreak = 0;
      Serial.println("[SENSORS] MPU read fail — re-init");
      gMpuOk = mpu.begin();
      if (gMpuOk) configureMpu6050();
    }
  }

  return out;
}

void hardwareLogicPrintDiagnostics() {
  bool bothActive =
      patientMonitor.debug_isShaking && patientMonitor.debug_isTachycardic;
  Serial.print(bothActive ? "[DETECTING] " : "[NORMAL]    ");
  Serial.print("Tremor: ");
  Serial.print(patientMonitor.debug_isShaking ? "YES" : "NO ");
  Serial.print(" | HR: ");
  Serial.print(patientMonitor.debug_isTachycardic ? "YES" : "NO ");
  if (patientMonitor.debug_isShaking && !patientMonitor.debug_isTachycardic) {
    Serial.print("(need>");
    Serial.print((int)(patientMonitor.getBaselineBPM() + 35));
    Serial.print(") ");
  }
  Serial.print(" | Mag: ");
  Serial.print(patientMonitor.debug_currentMag, 1);
  Serial.print(" | Freq: ");
  Serial.print(patientMonitor.getCurrentFreq(), 1);
  Serial.print("Hz | Timer: ");
  Serial.print(patientMonitor.debug_timerSeconds, 1);
  Serial.print("s | BPM: ");
  Serial.print(beatAvg);
#if DEMO_INJECT_BPM > 0
  Serial.print("(det:");
  Serial.print(DEMO_INJECT_BPM);
  Serial.print(")");
#endif
  Serial.print(" Base:");
  Serial.print((int)patientMonitor.getBaselineBPM());
  Serial.print(" | MPU:");
  Serial.print(gLastMpuEventOk ? "OK" : "FAIL");
  Serial.print(" | Ax:");
  Serial.print(gLastAx, 1);
  Serial.print(",");
  Serial.print(gLastAy, 1);
  Serial.print(",");
  Serial.print(gLastAz, 1);
  Serial.print(" | IR:");
  Serial.println(gLastIrValue);
}

bool readMpu6050Raw(int16_t &ax, int16_t &ay, int16_t &az, int16_t &gx, int16_t &gy,
                    int16_t &gz) {
  if (!gLastMpuEventOk) return false;
  ax = (int16_t)(gLastAx * 16384.0f / 9.80665f);
  ay = (int16_t)(gLastAy * 16384.0f / 9.80665f);
  az = (int16_t)(gLastAz * 16384.0f / 9.80665f);
  gx = (int16_t)(gLastGx * 131.0f * 57.29578f);
  gy = (int16_t)(gLastGy * 131.0f * 57.29578f);
  gz = (int16_t)(gLastGz * 131.0f * 57.29578f);
  return true;
}

bool recoverMpu6050() { return gMpuOk; }
