#pragma once

#include <Arduino.h>
#include <MPU6050.h>
#include "MAX30105.h"

extern MPU6050 mpu;
extern MAX30105 particleSensor;

struct HardwareLogicState {
  long irValue = 0;
  int beatAvg = 0;
  int16_t ax = 0, ay = 0, az = 0;
  int16_t gx = 0, gy = 0, gz = 0;
  float accelMag = 0;
  float accelAvg = 0;
  float gyroMag = 0;
  float gyroAvg = 0;
  bool pulseAbnormal = false;
  bool accelAbnormal = false;
  bool gyroAbnormal = false;
  char status[48] = "NORMAL";
  bool isAbnormal = false;
  bool fingerPresent = false;
};

extern bool gHrSensorOk;
extern bool gMpuOk;

void hardwareLogicInit();
HardwareLogicState hardwareLogicTick();
