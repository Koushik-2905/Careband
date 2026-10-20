#pragma once

#include <Arduino.h>
#include <math.h>

// Advanced seizure detector — integrated verbatim from bench-tested sketch.
class SeizureDetector {
private:
  const float ACCEL_MAG_THRESHOLD = 15.0f;
  const float FREQ_MIN = 3.0f;
  const float FREQ_MAX = 9.0f;
  const float HR_SPIKE_MARGIN = 35.0f;
  const unsigned long SUSTAINED_WINDOW_MS = 5000;

  float baselineBPM = 75.0f;
  unsigned long conditionStartTime = 0;
  bool timingActive = false;

  float lastAccelMag = 0.0f;
  unsigned long lastPeakTime = 0;
  float currentFrequency = 0.0f;

  void updateRestingBaseline(float currentBPM) {
    baselineBPM = (0.995f * baselineBPM) + (0.005f * currentBPM);
  }

public:
  bool debug_isShaking = false;
  bool debug_isTachycardic = false;
  float debug_timerSeconds = 0.0f;
  float debug_currentMag = 0.0f;

  bool detect(float aX, float aY, float aZ, float gX, float gY, float gZ, float currentBPM,
              unsigned long currentMillis) {
    float accelMag = sqrt((aX * aX) + (aY * aY) + (aZ * aZ));

    debug_currentMag = accelMag;

    if (accelMag > ACCEL_MAG_THRESHOLD && accelMag < lastAccelMag) {
      unsigned long timeSinceLastPeak = currentMillis - lastPeakTime;
      if (timeSinceLastPeak > 100) {
        float instantaneousFreq = 1000.0f / timeSinceLastPeak;
        currentFrequency = (currentFrequency * 0.5f) + (instantaneousFreq * 0.5f);
        lastPeakTime = currentMillis;
      }
    }
    lastAccelMag = accelMag;

    if (currentMillis - lastPeakTime > 1000) {
      currentFrequency = 0.0f;
    }

    debug_isShaking = (currentFrequency >= FREQ_MIN && currentFrequency <= FREQ_MAX);
    debug_isTachycardic = (currentBPM >= (baselineBPM + HR_SPIKE_MARGIN));

    if (debug_isShaking && debug_isTachycardic) {
      if (!timingActive) {
        timingActive = true;
        conditionStartTime = currentMillis;
        debug_timerSeconds = 0.0f;
      } else {
        debug_timerSeconds = (currentMillis - conditionStartTime) / 1000.0f;
        if (currentMillis - conditionStartTime >= SUSTAINED_WINDOW_MS) {
          return true;
        }
      }
    } else {
      timingActive = false;
      conditionStartTime = 0;
      debug_timerSeconds = 0.0f;

      if (!debug_isTachycardic && currentBPM > 40.0f) {
        updateRestingBaseline(currentBPM);
      }
    }
    return false;
  }

  float getBaselineBPM() { return baselineBPM; }
  float getCurrentFreq() { return currentFrequency; }
};
