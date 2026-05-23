// Bench-tested sensor logic from your standalone sketch (logic preserved).
#include "hardware_logic.h"
#include "config.h"

#include <Wire.h>
#include "MAX30105.h"
#include "heartRate.h"
#include <MPU6050.h>
#include <math.h>
#include <string.h>

MAX30105 particleSensor;
MPU6050 mpu;

bool gHrSensorOk = false;
bool gMpuOk = false;

const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;
float beatsPerMinute = 0;
int beatAvg = 0;

const int BUFFER_SIZE = 20;
float accelBuffer[BUFFER_SIZE];
int accelIndex = 0;
float accelMag = 0;
float accelAvg = 0;

void hardwareLogicInit() {
  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(100000);

  Serial.println("[SENSORS] Initializing MAX30102 + MPU6050...");

  if (!particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("[SENSORS] MAX30102 not found — check SDA/SCL (21/22). HR disabled.");
    gHrSensorOk = false;
  } else {
    particleSensor.setup(50, 4, 2, 100, 411, 4096);
    particleSensor.setPulseAmplitudeRed(0x1F);
    particleSensor.setPulseAmplitudeIR(0x1F);
    gHrSensorOk = true;
    Serial.println("[SENSORS] MAX30102 OK");
  }
  delay(200);

  gMpuOk = mpu.testConnection();
  if (!gMpuOk) {
    Serial.println("[SENSORS] MPU6050 not found — motion/ML buffer may be empty.");
  } else {
    mpu.initialize();
    Wire.beginTransmission(0x68);
    Wire.write(0x6B);
    Wire.write(0x00);
    Wire.endTransmission(true);
    Serial.println("[SENSORS] MPU6050 OK");
  }
  delay(200);

  Serial.println("[SENSORS] Ready (IR,BPM,AX,AY,AZ,STATUS)");
}

HardwareLogicState hardwareLogicTick() {
  HardwareLogicState out;
  int16_t ax, ay, az;

  if (!gHrSensorOk) {
    out.fingerPresent = false;
    out.beatAvg = 0;
    strcpy(out.status, "NO HR SENSOR");
    return out;
  }

  long irValue = particleSensor.getIR();
  out.irValue = irValue;

  if (irValue < 10000) {
    beatAvg = 0;
    out.fingerPresent = false;
    out.beatAvg = 0;
    static unsigned long lastNoFinger = 0;
    if (millis() - lastNoFinger > 2000) {
      lastNoFinger = millis();
      Serial.println("[HR] Place finger on MAX30102");
    }
    return out;
  }
  out.fingerPresent = true;

  if (checkForBeat(irValue)) {
    long delta = millis() - lastBeat;
    lastBeat = millis();
    beatsPerMinute = 60.0 / (delta / 1000.0);
    if (beatsPerMinute > 50 && beatsPerMinute < 120) {
      rates[rateSpot++] = (byte)beatsPerMinute;
      rateSpot %= RATE_SIZE;
      int total = 0;
      for (byte i = 0; i < RATE_SIZE; i++) total += rates[i];
      beatAvg = total / RATE_SIZE;
    }
  }

  if (gMpuOk) {
    mpu.getAcceleration(&ax, &ay, &az);
  }
  out.ax = ax;
  out.ay = ay;
  out.az = az;

  accelMag = sqrt((float)ax * ax + (float)ay * ay + (float)az * az);
  accelBuffer[accelIndex++] = accelMag;
  accelIndex %= BUFFER_SIZE;

  accelAvg = 0;
  for (int i = 0; i < BUFFER_SIZE; i++) accelAvg += accelBuffer[i];
  accelAvg /= BUFFER_SIZE;

  out.accelMag = accelMag;
  out.accelAvg = accelAvg;
  out.beatAvg = beatAvg;

  bool bpmAbnormal = (beatAvg > 120 || beatAvg < 50);
  bool highMotion = (accelAvg > 25000);
  bool extremeShake = (accelMag > 30000);

  String status = "NORMAL";
  if (bpmAbnormal && highMotion) {
    status = "ABNORMAL - POSSIBLE FIT";
  } else if (highMotion && extremeShake) {
    status = "ABNORMAL - SHAKING";
  }

  out.isAbnormal = status.startsWith("ABNORMAL");
  status.toCharArray(out.status, sizeof(out.status));

  static unsigned long lastCsv = 0;
  if (millis() - lastCsv > 1000) {
    lastCsv = millis();
    Serial.print("[DATA] IR=");
    Serial.print(irValue);
    Serial.print(" BPM=");
    Serial.print(beatAvg);
    Serial.print(" ");
    Serial.println(status);
  }

  return out;
}
