// Seizure rules: pulse + accelerometer + gyroscope (MPU6050) + MAX30102.
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
float gyroBuffer[BUFFER_SIZE];
int motionIndex = 0;
float accelMag = 0;
float accelAvg = 0;
float gyroMag = 0;
float gyroAvg = 0;

void hardwareLogicInit() {
  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(100000);

  Serial.println("[SENSORS] MAX30102 + MPU6050 (accel + gyro + pulse)...");

  if (!particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("[SENSORS] MAX30102 not found");
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
    Serial.println("[SENSORS] MPU6050 not found");
  } else {
    mpu.initialize();
    mpu.setFullScaleAccelRange(MPU6050_ACCEL_FS_2);
    mpu.setFullScaleGyroRange(MPU6050_GYRO_FS_250);
    mpu.setDLPFMode(MPU6050_DLPF_BW_42);
    Wire.beginTransmission(0x68);
    Wire.write(0x6B);
    Wire.write(0x00);
    Wire.endTransmission(true);
    Serial.println("[SENSORS] MPU6050 OK (accel + gyro)");
  }
  delay(200);

  Serial.println("[SENSORS] Detection uses pulse + accel + gyro");
}

HardwareLogicState hardwareLogicTick() {
  HardwareLogicState out;
  int16_t ax = 0, ay = 0, az = 0, gx = 0, gy = 0, gz = 0;

  out.pulseAbnormal = false;
  out.accelAbnormal = false;
  out.gyroAbnormal = false;
  out.fingerPresent = false;
  out.beatAvg = beatAvg;

  if (gHrSensorOk) {
    long irValue = particleSensor.getIR();
    out.irValue = irValue;

    if (irValue >= 10000) {
      out.fingerPresent = true;
      if (checkForBeat(irValue)) {
        long delta = millis() - lastBeat;
        lastBeat = millis();
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
      if (beatAvg > 0) {
        out.pulseAbnormal = (beatAvg > HR_HIGH || beatAvg < HR_LOW);
      }
    } else {
      beatAvg = 0;
      out.beatAvg = 0;
    }
  }

  if (gMpuOk) {
    mpu.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);
  }
  out.ax = ax;
  out.ay = ay;
  out.az = az;
  out.gx = gx;
  out.gy = gy;
  out.gz = gz;

  accelMag = sqrtf((float)ax * ax + (float)ay * ay + (float)az * az);
  gyroMag = sqrtf((float)gx * gx + (float)gy * gy + (float)gz * gz);

  accelBuffer[motionIndex] = accelMag;
  gyroBuffer[motionIndex] = gyroMag;
  motionIndex = (motionIndex + 1) % BUFFER_SIZE;

  accelAvg = 0;
  gyroAvg = 0;
  for (int i = 0; i < BUFFER_SIZE; i++) {
    accelAvg += accelBuffer[i];
    gyroAvg += gyroBuffer[i];
  }
  accelAvg /= BUFFER_SIZE;
  gyroAvg /= BUFFER_SIZE;

  out.accelMag = accelMag;
  out.accelAvg = accelAvg;
  out.gyroMag = gyroMag;
  out.gyroAvg = gyroAvg;

  out.accelAbnormal = (accelAvg > ACCEL_AVG_THR) || (accelMag > ACCEL_PEAK_THR);
  out.gyroAbnormal = (gyroAvg > GYRO_AVG_THR) || (gyroMag > GYRO_PEAK_THR);

  // All three sensors must agree when finger is on sensor; motion-only fallback.
  if (out.fingerPresent && out.pulseAbnormal && out.accelAbnormal && out.gyroAbnormal) {
    strcpy(out.status, "SEIZURE HR+ACC+GYRO");
    out.isAbnormal = true;
  } else if (out.accelAbnormal && out.gyroAbnormal && accelMag > ACCEL_PEAK_THR) {
    strcpy(out.status, "SEIZURE ACC+GYRO");
    out.isAbnormal = true;
  } else {
    strcpy(out.status, "NORMAL");
    out.isAbnormal = false;
  }

  static unsigned long lastLog = 0;
  if (millis() - lastLog > 1000) {
    lastLog = millis();
    Serial.printf("[DATA] BPM=%d P=%d A=%d G=%d %s\n", beatAvg, out.pulseAbnormal,
                  out.accelAbnormal, out.gyroAbnormal, out.status);
  }

  return out;
}
