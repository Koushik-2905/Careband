// MINIMAL TEST — upload this alone to verify USB Serial (no OLED, no sensors).
// Tools -> Board -> ESP32 Dev Module, 115200 baud Serial Monitor, press EN after upload.

#define TEST_LED 27

void setup() {
  pinMode(TEST_LED, OUTPUT);
  Serial.begin(115200);
  delay(2000);
  Serial.println();
  Serial.println("NEUROGUARD BOOT TEST OK");
  Serial.println("If you read this, USB serial works.");
  Serial.println("Baud must be 115200 in Serial Monitor.");
}

void loop() {
  digitalWrite(TEST_LED, !digitalRead(TEST_LED));
  Serial.println("tick");
  delay(1000);
}
