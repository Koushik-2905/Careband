// NeuroGuard ESP32 Firmware v2.0 — GPS: phone BLE, SIM cell fallback
#include "config.h"
#if DISABLE_BROWNOUT
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#endif
#include "detection.h"
#include "seizure_tflite.h"
#include "hardware_logic.h"
#include "gsm_location.h"

#include <Wire.h>
#include <HardwareSerial.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

#if !SIMULATION_MODE
#include <MPU6050.h>
#include <Adafruit_SSD1306.h>
#if ENABLE_HR_SENSOR && !USE_HARDWARE_LOGIC
#include <MAX30105.h>
#endif
#endif

#if ENABLE_GSM
HardwareSerial gsmSerial(2);
#endif

#if !SIMULATION_MODE
Adafruit_SSD1306 oled(128, 64, &Wire, -1);
static bool oledOk = false;
#endif

HardwareLogicState hwState;

BLECharacteristic *alertChar = nullptr;
BLECharacteristic *dataChar = nullptr;
BLECharacteristic *gpsWriteChar = nullptr;
bool deviceConnected = false;

DetectionContext detCtx;
DeviceState state = MONITORING;
unsigned long tDetect = 0;
bool cancelFlag = false;

float gpslat = 0.0f, gpslng = 0.0f;
bool gpsValidPhone = false;
bool gpsValidSim = false;
unsigned long lastGPSReceived = 0;
unsigned long lastSimLocationAttempt = 0;

static bool hasGpsFix() { return gpsValidPhone || gpsValidSim; }

static bool trySimLocationFallback() {
#if ENABLE_GSM && ENABLE_GSM_LBS && !SIMULATION_MODE
  float lat = 0, lng = 0;
  if (gsmFetchRoughLocation(gsmSerial, &lat, &lng)) {
    gpslat = lat;
    gpslng = lng;
    gpsValidSim = true;
    Serial.printf("[GPS] SIM rough location: %.6f, %.6f\n", gpslat, gpslng);
    return true;
  }
#endif
  return false;
}

void showOLED(const char *l1, const char *l2, const char *l3);
void showBpmOLED(int bpm);
void showPressToStopOLED();
void initOLED();
void initMPU();
void initGSM();
void initBLE();
void readIMU();
void dispatchAlerts();
void activateLocal();
void doCancel();
void sendSMS(const char *num, const char *msg);
void broadcastData();
void IRAM_ATTR handleSOS();
void scanI2C();

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *s) {
    deviceConnected = true;
  }
  void onDisconnect(BLEServer *s) {
    deviceConnected = false;
    BLEDevice::startAdvertising();
  }
};

class GPSWriteCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String s = String(pChar->getValue().c_str());
    if (s.length() < 5) return;
    int commaIdx = s.indexOf(',');
    if (commaIdx < 0) return;
    float lat = s.substring(0, commaIdx).toFloat();
    float lng = s.substring(commaIdx + 1).toFloat();
    if (lat >= -90.0f && lat <= 90.0f && lng >= -180.0f && lng <= 180.0f) {
      gpslat = lat;
      gpslng = lng;
      gpsValidPhone = true;
      gpsValidSim = false;
      lastGPSReceived = millis();
      Serial.printf("[GPS] Received from phone: %.6f, %.6f\n", gpslat, gpslng);
    }
  }
};

class ConfigWriteCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    Serial.print("[CONFIG] ");
    Serial.println(pChar->getValue().c_str());
  }
};

void scanI2C() {
  Serial.println("[I2C] Scan 0x01-0x7F:");
  int n = 0;
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("  device 0x%02X\n", addr);
      n++;
    }
  }
  if (n == 0) Serial.println("  (none — check wiring 21/22, 3.3V, GND)");
}

void setup() {
#if DISABLE_BROWNOUT
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
#endif

  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  pinMode(VIB_MOTOR_PIN, OUTPUT);
  digitalWrite(VIB_MOTOR_PIN, LOW);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);

  Serial.begin(SERIAL_BAUD);
  delay(2000);
  Serial.flush();
  Serial.println();
  Serial.println("NEUROGUARD BOOT");
#if BOOT_SAFE_MODE
  Serial.println("SAFE MODE");
#endif
  Serial.print("BAUD=");
  Serial.println(SERIAL_BAUD);
  Serial.print("BUZZER GPIO ");
  Serial.println(BUZZER_PIN);

  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(100000);
#if defined(Wire.setTimeOut)
  Wire.setTimeOut(I2C_TIMEOUT_MS);
#endif
  Serial.print("I2C SDA=");
  Serial.print(I2C_SDA);
  Serial.print(" SCL=");
  Serial.println(I2C_SCL);
  delay(100);
#if !BOOT_SKIP_I2C
  scanI2C();
#endif

  pinMode(SOS_BTN_PIN, INPUT_PULLUP);

#if !BOOT_SKIP_I2C
#if USE_HARDWARE_LOGIC && !SIMULATION_MODE
  hardwareLogicInit();
#else
  initMPU();
#endif
  initOLED();
#else
  Serial.println("I2C skipped — unplug test or set BOOT_SKIP_I2C 0");
#endif

#if ENABLE_GSM
  initGSM();
#endif
#if ENABLE_BLE_ON_BOOT
  initBLE();
#endif
#if ENABLE_ML
  initMlModel();
#endif

  attachInterrupt(digitalPinToInterrupt(SOS_BTN_PIN), handleSOS, FALLING);

  showBpmOLED(detCtx.hrBPM);
  Serial.println("[BOOT] Ready @ 115200 baud");
  Serial.println("[BOOT] Expect OLED: Place finger / Avg BPM");
}

void loop() {
  static unsigned long tSample = 0;
  static unsigned long tHw = 0;
  static unsigned long tMl = 0;

#if USE_HARDWARE_LOGIC && !SIMULATION_MODE
  if (millis() - tHw >= HARDWARE_TICK_MS) {
    tHw = millis();
    hwState = hardwareLogicTick();
    detCtx.hrBPM = hwState.beatAvg;

    if (state == MONITORING && hwState.isAbnormal && hwState.fingerPresent) {
      state = DETECTED;
      tDetect = millis();
      activateLocal();
      Serial.printf("[DETECT] Hardware rule: %s\n", hwState.status);
    }
  }
#endif

  if (millis() - tSample >= 10) {
    tSample = millis();
    readIMU();

#if ENABLE_ML
    if (gMlReady && detCtx.bufFull && millis() - tMl >= ML_INFERENCE_INTERVAL_MS) {
      tMl = millis();
      detCtx.mlSeizureScore = runSeizureInference(detCtx);
      Serial.printf("[ML] Seizure score: %.2f\n", detCtx.mlSeizureScore);
    }
#endif

    if (detCtx.bufFull) {
#if !USE_HARDWARE_LOGIC
      detCtx.confidence = analyzePattern(detCtx);
#else
      detCtx.confidence = detCtx.mlSeizureScore;
      if (hwState.isAbnormal) {
        if (detCtx.confidence < 0.92f) detCtx.confidence = 0.92f;
      }
#endif

      bool mlTrigger = gMlReady && (detCtx.mlSeizureScore >= ML_ALERT_THR);
      if (state == MONITORING && (mlTrigger
#if !USE_HARDWARE_LOGIC
          || detCtx.confidence > CONFIDENCE_THR
#endif
          )) {
        state = DETECTED;
        tDetect = millis();
        activateLocal();
        Serial.printf("[DETECT] ML/threshold confidence: %.2f\n", detCtx.confidence);
      }
    }
  }

  if (state == DETECTED) {
    unsigned long elapsed = millis() - tDetect;
    if (cancelFlag) {
      doCancel();
    } else if (elapsed >= CANCEL_WINDOW_MS) {
      digitalWrite(BUZZER_PIN, HIGH);
      dispatchAlerts();
      state = ALERT_SENT;
    } else {
      showPressToStopOLED();
    }
  }

  if (state == MONITORING) {
    static unsigned long tOled = 0;
    static unsigned long tAlive = 0;
    if (millis() - tOled >= 500) {
      tOled = millis();
      showBpmOLED(detCtx.hrBPM);
    }
    if (millis() - tAlive >= 2000) {
      tAlive = millis();
      Serial.print("ALIVE BPM=");
      Serial.print(detCtx.hrBPM);
      Serial.print(" OLED=");
      Serial.println(oledOk ? "OK" : "NO");
    }
  }

  if (deviceConnected) broadcastData();

  if (gpsValidPhone && millis() - lastGPSReceived > GPS_STALE_MS) {
    gpsValidPhone = false;
    Serial.println("[GPS] Phone fix stale — trying SIM fallback");
#if ENABLE_GSM && ENABLE_GSM_LBS
    if (!gpsValidSim && millis() - lastSimLocationAttempt > 60000) {
      lastSimLocationAttempt = millis();
      trySimLocationFallback();
    }
#endif
  }

#if ENABLE_GSM && ENABLE_GSM_LBS && !SIMULATION_MODE
  if (!gpsValidPhone && !gpsValidSim && millis() - lastSimLocationAttempt > 120000) {
    lastSimLocationAttempt = millis();
    trySimLocationFallback();
  }
#endif

  if (state == ALERT_SENT && millis() - tDetect > 60000) {
    state = MONITORING;
    cancelFlag = false;
    digitalWrite(BUZZER_PIN, LOW);
    showBpmOLED(detCtx.hrBPM);
  }
}

void dispatchAlerts() {
#if ENABLE_GSM && ENABLE_GSM_LBS
  if (!gpsValidPhone) {
    trySimLocationFallback();
  }
#endif

  char loc[160];
  if (hasGpsFix()) {
    if (gpsValidSim && !gpsValidPhone)
      snprintf(loc, 160, "maps.google.com/?q=%.6f,%.6f (approx cell)", gpslat, gpslng);
    else
      snprintf(loc, 160, "maps.google.com/?q=%.6f,%.6f", gpslat, gpslng);
  } else {
    strcpy(loc, "Location unavailable");
  }

  char sms[280];
  snprintf(sms, 280, "NEUROGUARD ALERT: Seizure! HR:%dBPM Conf:%.0f%% %s", detCtx.hrBPM,
           (double)(detCtx.confidence * 100), loc);

#if ENABLE_GSM
  for (int i = 0; i < CONTACT_COUNT; i++) {
    sendSMS(CONTACTS[i], sms);
    delay(2000);
  }
#else
  Serial.println(sms);
#endif

  if (deviceConnected && alertChar) {
    StaticJsonDocument<160> doc;
    doc["type"] = "SEIZURE_ALERT";
    doc["conf"] = (int)(detCtx.confidence * 100);
    doc["hr"] = detCtx.hrBPM;
    doc["lat"] = gpslat;
    doc["lng"] = gpslng;
    doc["valid"] = hasGpsFix();
    if (gpsValidPhone)
      doc["locSrc"] = "phone";
    else if (gpsValidSim)
      doc["locSrc"] = "sim";
    else
      doc["locSrc"] = "none";
    char buf[160];
    serializeJson(doc, buf);
    alertChar->setValue(buf);
    alertChar->notify();
  }

  showOLED("ALERT SENT!", "SMS + BLE", "Help coming...");
  Serial.println("[ALERT] All notifications dispatched");
}

void activateLocal() {
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(LED_PIN, HIGH);
  digitalWrite(VIB_MOTOR_PIN, HIGH);
}

void doCancel() {
  state = CANCELLED;
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(LED_PIN, LOW);
  digitalWrite(VIB_MOTOR_PIN, LOW);
  cancelFlag = false;
  showBpmOLED(detCtx.hrBPM);
  state = MONITORING;
}

void IRAM_ATTR handleSOS() {
  if (state == DETECTED)
    cancelFlag = true;
  else if (state == MONITORING) {
    state = DETECTED;
    tDetect = millis() - CANCEL_WINDOW_MS;
  }
}

void sendSMS(const char *num, const char *msg) {
#if ENABLE_GSM
  gsmSerial.println("AT+CMGF=1");
  delay(500);
  gsmSerial.print("AT+CMGS=\"");
  gsmSerial.print(num);
  gsmSerial.println("\"");
  delay(500);
  gsmSerial.print(msg);
  delay(100);
  gsmSerial.write(26);
  delay(3000);
#endif
}

void broadcastData() {
  static unsigned long last = 0;
  if (millis() - last < 1000 || !dataChar) return;
  last = millis();
  StaticJsonDocument<200> doc;
  doc["state"] = (int)state;
  doc["hr"] = detCtx.hrBPM;
  doc["conf"] = detCtx.confidence;
  doc["ml"] = detCtx.mlSeizureScore;
  doc["gpsOk"] = hasGpsFix();
  doc["lat"] = gpslat;
  doc["lng"] = gpslng;
  if (gpsValidPhone)
    doc["locSrc"] = "phone";
  else if (gpsValidSim)
    doc["locSrc"] = "sim";
  else
    doc["locSrc"] = "none";
  char buf[200];
  serializeJson(doc, buf);
  dataChar->setValue(buf);
  dataChar->notify();
}

void readIMU() {
#if SIMULATION_MODE
  float t = millis() / 1000.0f;
  detCtx.aX[detCtx.bufIdx] = sinf(t * 8.0f) * 0.1f;
  detCtx.aY[detCtx.bufIdx] = cosf(t * 8.0f) * 0.1f;
  detCtx.aZ[detCtx.bufIdx] = 1.0f;
  detCtx.gX[detCtx.bufIdx] = detCtx.gY[detCtx.bufIdx] = detCtx.gZ[detCtx.bufIdx] = 0;
#else
  int16_t ax = 0, ay = 0, az = 0, gx = 0, gy = 0, gz = 0;
  if (gMpuOk) {
    mpu.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);
  }
  detCtx.aX[detCtx.bufIdx] = ax / 16384.0f;
  detCtx.aY[detCtx.bufIdx] = ay / 16384.0f;
  detCtx.aZ[detCtx.bufIdx] = az / 16384.0f;
  detCtx.gX[detCtx.bufIdx] = gx / 131.0f;
  detCtx.gY[detCtx.bufIdx] = gy / 131.0f;
  detCtx.gZ[detCtx.bufIdx] = gz / 131.0f;
#endif
  detCtx.bufIdx = (detCtx.bufIdx + 1) % WINDOW_SIZE;
  if (detCtx.bufIdx == 0) detCtx.bufFull = true;
}

void initMPU() {
#if !SIMULATION_MODE && !USE_HARDWARE_LOGIC
  mpu.initialize();
  mpu.setFullScaleAccelRange(MPU6050_ACCEL_FS_2);
  mpu.setFullScaleGyroRange(MPU6050_GYRO_FS_250);
  mpu.setDLPFMode(MPU6050_DLPF_BW_42);
#if ENABLE_HR_SENSOR
  MAX30105 particleSensor;
  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("[HR] MAX30105 not found");
  } else {
    particleSensor.setup();
    particleSensor.setPulseAmplitudeRed(0x0A);
    particleSensor.setPulseAmplitudeIR(0x0A);
  }
#endif
#endif
}

void initOLED() {
#if ENABLE_OLED && !SIMULATION_MODE
  oledOk = false;
  if (oled.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    oledOk = true;
    Serial.println("[OLED] OK @ 0x3C");
  } else if (oled.begin(SSD1306_SWITCHCAPVCC, 0x3D)) {
    oledOk = true;
    Serial.println("[OLED] OK @ 0x3D");
  } else {
    Serial.println("[OLED] init failed — check SDA/SCL/VCC/GND (same bus as sensors)");
    return;
  }
  oled.clearDisplay();
  oled.setTextSize(1);
  oled.setTextColor(SSD1306_WHITE);
  oled.setCursor(0, 0);
  oled.println("NeuroGuard");
  oled.println("Starting...");
  oled.display();
#endif
}

void initGSM() {
#if ENABLE_GSM && !SIMULATION_MODE
  gsmSerial.begin(9600, SERIAL_8N1, GSM_RX, GSM_TX);
  delay(3000);
  gsmSerial.println("AT");
  delay(500);
  gsmSerial.println("AT+CMGF=1");
  delay(500);
  gsmSerial.println("AT+CREG=1");
  delay(500);
  Serial.println("[GSM] SMS + cell location (LBS) ready");
#endif
}

void showBpmOLED(int bpm) {
#if ENABLE_OLED && !SIMULATION_MODE
  if (!oledOk) return;
  oled.clearDisplay();
  oled.setTextColor(SSD1306_WHITE);
  oled.setTextSize(2);
  oled.setCursor(0, 12);
  if (!gHrSensorOk) {
    oled.println("No HR");
    oled.setTextSize(1);
    oled.println("sensor");
  } else if (bpm <= 0) {
    oled.println("Place");
    oled.setTextSize(1);
    oled.println("finger");
  } else {
    char buf[20];
    snprintf(buf, sizeof(buf), "Avg %d", bpm);
    oled.println(buf);
    oled.setTextSize(1);
    oled.setCursor(0, 44);
    oled.println("BPM");
  }
  oled.display();
#else
  Serial.printf("[OLED] Avg %d BPM\n", bpm);
#endif
}

void showPressToStopOLED() {
#if ENABLE_OLED && !SIMULATION_MODE
  if (!oledOk) return;
  oled.clearDisplay();
  oled.setTextColor(SSD1306_WHITE);
  oled.setTextSize(2);
  oled.setCursor(0, 20);
  oled.println("press to stop");
  oled.display();
#else
  Serial.println("[OLED] press to stop");
#endif
}

void showOLED(const char *l1, const char *l2, const char *l3) {
#if ENABLE_OLED && !SIMULATION_MODE
  if (!oledOk) return;
  oled.clearDisplay();
  oled.setTextColor(SSD1306_WHITE);
  oled.setTextSize(1);
  oled.setCursor(0, 0);
  oled.println(l1);
  oled.setCursor(0, 22);
  oled.println(l2);
  oled.setCursor(0, 44);
  oled.println(l3);
  oled.display();
#else
  Serial.printf("[OLED] %s | %s | %s\n", l1, l2, l3);
#endif
}

void initBLE() {
  BLEDevice::init("NeuroGuard");
  BLEServer *srv = BLEDevice::createServer();
  srv->setCallbacks(new ServerCallbacks());
  BLEService *svc = srv->createService(SERVICE_UUID);

  gpsWriteChar = svc->createCharacteristic(
      CHAR_UUID_GPS_WRITE,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  gpsWriteChar->setCallbacks(new GPSWriteCallback());

  BLECharacteristic *configChar = svc->createCharacteristic(
      CHAR_UUID_CONFIG, BLECharacteristic::PROPERTY_WRITE);
  configChar->setCallbacks(new ConfigWriteCallback());

  alertChar = svc->createCharacteristic(CHAR_UUID_ALERT, BLECharacteristic::PROPERTY_NOTIFY);
  alertChar->addDescriptor(new BLE2902());

  dataChar = svc->createCharacteristic(CHAR_UUID_DATA, BLECharacteristic::PROPERTY_NOTIFY);
  dataChar->addDescriptor(new BLE2902());

  svc->start();
  BLEDevice::startAdvertising();
  Serial.println("[BLE] Advertising as 'NeuroGuard'");
}
