/* ===================================================================
   BRUTUS v2.0 — Audio Board Hardware Test  (ESP32 #2)
   ===================================================================
   Combined test for the INMP441 I2S microphone and the MAX98357A I2S
   speaker amp. Plays a continuous tone through the speaker and prints
   live mic readings to the Serial Monitor (115200 baud) once a second.

   This board is OPTIONAL in v2.0 — the phone app handles all real
   audio. Flash this only to verify the mic/speaker hardware works.

   Board: "ESP32 Dev Module" · esp32 core 3.x (needs ESP_I2S.h)
   =================================================================== */

#include <Arduino.h>
#include <ESP_I2S.h>

I2SClass mic;
I2SClass spk;

// --- INMP441 MIC PINS ---
#define MIC_PIN_BCLK      14
#define MIC_PIN_WS        15
#define MIC_PIN_DATA      32

// --- MAX98357A SPEAKER PINS ---
#define SPK_PIN_BCLK      26
#define SPK_PIN_LRC       27
#define SPK_PIN_DATA      25

#define SAMPLE_RATE       16000
#define SINE_SAMPLES      32
int16_t sine_wave[SINE_SAMPLES];

unsigned long last_print_time = 0;
long long sample_counter = 0;

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("=== COMBINED HARDWARE TEST STARTING ===");

  // Tone generation ke liye array setup karna
  for (int i = 0; i < SINE_SAMPLES; i++) {
    sine_wave[i] = (int16_t)(6000.0 * sin(2.0 * PI * i / SINE_SAMPLES));
  }

  // 1. Microphone Hardware Initialize karna
  mic.setPins(MIC_PIN_BCLK, MIC_PIN_WS, -1, MIC_PIN_DATA, -1);
  if (!mic.begin(I2S_MODE_STD, SAMPLE_RATE, I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_MONO, I2S_STD_SLOT_LEFT)) {
    Serial.println("CRITICAL ERROR: Mic failed to start! Check Pins 14, 15, 32");
    while (1);
  }
  Serial.println("SUCCESS: Mic initialized.");

  // 2. Speaker Hardware Initialize karna
  spk.setPins(SPK_PIN_BCLK, SPK_PIN_LRC, SPK_PIN_DATA, -1, -1);
  if (!spk.begin(I2S_MODE_STD, SAMPLE_RATE, I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO, I2S_STD_SLOT_BOTH)) {
    Serial.println("CRITICAL ERROR: Speaker failed to start! Check Pins 26, 27, 25");
    while (1);
  }
  Serial.println("SUCCESS: Speaker initialized.");
  Serial.println("Running Live Test... Watch the Serial Monitor and Speaker.");
}

void loop() {
  // --- PART 1: SPEAKER TESTING (Continuous Tone Output) ---
  int16_t stereo_sample[2];
  for (int i = 0; i < SINE_SAMPLES; i++) {
    stereo_sample[0] = sine_wave[i]; // Left
    stereo_sample[1] = sine_wave[i]; // Right
    spk.write((uint8_t*)stereo_sample, sizeof(stereo_sample));
  }

  // --- PART 2: MICROPHONE TESTING (Live Reading) ---
  int32_t mic_sample = 0;
  // Ek baar loop me mic se data fetch karna
  int bytes_read = mic.read((uint8_t*)&mic_sample, sizeof(mic_sample));

  if (bytes_read > 0 && mic_sample != 0) {
    sample_counter++;
  }

  // --- PART 3: DIAGNOSTIC LIVE REPORT (Har 1 Second me Monitor par dikhega) ---
  if (millis() - last_print_time >= 1000) {
    Serial.print("[STATUS] Speaker: PLAYING TONE | Mic Raw Value: ");
    Serial.print(mic_sample);
    Serial.print(" | Active Samples Received: ");
    Serial.println(sample_counter);

    // Counter reset taaki agle second ka check ho sake
    sample_counter = 0;
    last_print_time = millis();
  }
}
