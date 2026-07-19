// ESP32-CAM MJPEG stream for Brutus Sense Station.
//
// Self-contained single-file MJPEG server. The UNO Q's vision.py reads this
// with OpenCV at:  http://<CAM_IP>:81/stream
//
// Two network modes (set NETWORK_MODE below):
//   MODE_AP  : the camera makes its own Wi-Fi. It is reachable at 192.168.4.1,
//              which matches the default BRUTUS_STREAM_URL. Simplest for demos.
//   MODE_STA : the camera joins your travel router. Watch the serial monitor
//              for the printed IP, then set BRUTUS_STREAM_URL to that IP.
//
// Board: AI-Thinker ESP32-CAM (most common). If you have a different module,
// change the pin map. In Arduino IDE select "AI Thinker ESP32-CAM".
//
// Requires the ESP32 Arduino core (Boards Manager -> "esp32" by Espressif).

#include "esp_camera.h"
#include "img_converters.h"   // frame2jpg() for software JPEG encoding
#include <WiFi.h>

// ----- CONFIG ---------------------------------------------------------------
// Behavior: try to join your router (STA) first; if that fails within
// STA_CONNECT_TIMEOUT_MS, fall back to the camera's own AP (192.168.4.1).
// Set FORCE_AP = true to skip the router entirely and always run as an AP.

const bool FORCE_AP = false;
const unsigned long STA_CONNECT_TIMEOUT_MS = 15000;  // 15 s to join the router

// STA credentials (your travel router). Fill these in.
const char* STA_SSID = "Avik's S24 FE";
const char* STA_PASS = "avik1017";

// AP fallback credentials (the network the camera creates if STA fails).
const char* AP_SSID = "brutus-cam";
const char* AP_PASS = "brutuscam";  // >= 8 chars

const uint16_t STREAM_PORT = 81;

// ----- AI-Thinker ESP32-CAM pin map ----------------------------------------
#define PWDN_GPIO_NUM  32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM   0
#define SIOD_GPIO_NUM  26
#define SIOC_GPIO_NUM  27
#define Y9_GPIO_NUM    35
#define Y8_GPIO_NUM    34
#define Y7_GPIO_NUM    39
#define Y6_GPIO_NUM    36
#define Y5_GPIO_NUM    21
#define Y4_GPIO_NUM    19
#define Y3_GPIO_NUM    18
#define Y2_GPIO_NUM     5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM  23
#define PCLK_GPIO_NUM  22

// AI-Thinker on-board bright white LED (GPIO4, separate from the camera bus).
#define FLASH_LED_GPIO  4
bool flashOn = false;

WiFiServer server(STREAM_PORT);

// ----- Camera init ----------------------------------------------------------
bool initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0       = Y2_GPIO_NUM;
  config.pin_d1       = Y3_GPIO_NUM;
  config.pin_d2       = Y4_GPIO_NUM;
  config.pin_d3       = Y5_GPIO_NUM;
  config.pin_d4       = Y6_GPIO_NUM;
  config.pin_d5       = Y7_GPIO_NUM;
  config.pin_d6       = Y8_GPIO_NUM;
  config.pin_d7       = Y9_GPIO_NUM;
  config.pin_xclk     = XCLK_GPIO_NUM;
  config.pin_pclk     = PCLK_GPIO_NUM;
  config.pin_vsync    = VSYNC_GPIO_NUM;
  config.pin_href     = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn     = PWDN_GPIO_NUM;
  config.pin_reset    = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;

  // This sensor does not support hardware JPEG, so we capture RGB565 (supported
  // by every sensor) and software-encode to JPEG in the stream. RGB565 frames
  // are large, so keep the resolution modest and prefer PSRAM.
  config.pixel_format = PIXFORMAT_RGB565;
  config.frame_size   = psramFound() ? FRAMESIZE_QVGA : FRAMESIZE_QQVGA;
  config.fb_count     = 1;
  config.grab_mode    = CAMERA_GRAB_LATEST;
  config.fb_location  = psramFound() ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM;

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed: 0x%x\n", err);
    return false;
  }
  Serial.printf("Camera ready (RGB565, %s). PSRAM: %s\n",
                psramFound() ? "QVGA" : "QQVGA",
                psramFound() ? "yes" : "no");
  return true;
}

// ----- Wi-Fi bring-up -------------------------------------------------------
void startAP() {
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.printf("AP mode. Join '%s' (pass '%s').\n", AP_SSID, AP_PASS);
  Serial.print("Stream at: http://");
  Serial.print(WiFi.softAPIP());
  Serial.printf(":%u/stream\n", STREAM_PORT);
}

void initWiFi() {
  if (FORCE_AP) {
    startAP();
    return;
  }

  // Try to join the router first.
  WiFi.mode(WIFI_STA);
  WiFi.begin(STA_SSID, STA_PASS);
  Serial.printf("Joining Wi-Fi '%s'", STA_SSID);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED &&
         millis() - start < STA_CONNECT_TIMEOUT_MS) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("\nConnected. Stream at: http://");
    Serial.print(WiFi.localIP());
    Serial.printf(":%u/stream\n", STREAM_PORT);
    Serial.println(">>> Set BRUTUS_STREAM_URL on the UNO Q to the IP above.");
  } else {
    Serial.println("\nRouter join failed; falling back to AP mode.");
    startAP();
  }
}

// ----- MJPEG streaming ------------------------------------------------------
void streamTo(WiFiClient& client) {
  // Multipart MJPEG header. OpenCV/FFmpeg reads this directly.
  client.print(
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n"
    "Cache-Control: no-cache\r\n"
    "Connection: close\r\n\r\n"
  );

  while (client.connected()) {
    camera_fb_t* fb = esp_camera_fb_get();
    if (!fb) {
      Serial.println("Frame capture failed");
      break;
    }

    // Software-encode the RGB565 frame to JPEG (quality 80).
    uint8_t* jpg_buf = NULL;
    size_t   jpg_len = 0;
    bool ok = frame2jpg(fb, 80, &jpg_buf, &jpg_len);
    esp_camera_fb_return(fb);
    if (!ok) {
      Serial.println("JPEG encode failed");
      break;
    }

    client.printf(
      "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n",
      (unsigned)jpg_len
    );
    client.write(jpg_buf, jpg_len);
    client.print("\r\n");
    free(jpg_buf);              // frame2jpg allocates; must free each frame

    // Small yield; the MPU only needs event-rate FPS.
    delay(30);
  }
}

// ----- Single-frame snapshot (GET /capture) ---------------------------------
// Much cheaper than the continuous stream when the app just needs one frame,
// e.g. to send to Gemini vision for "what do you see". Returns one JPEG.
void captureTo(WiFiClient& client) {
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
    client.print("HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\n\r\n");
    return;
  }
  uint8_t* jpg_buf = NULL;
  size_t   jpg_len = 0;
  bool ok = frame2jpg(fb, 80, &jpg_buf, &jpg_len);
  esp_camera_fb_return(fb);
  if (!ok) {
    client.print("HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\n\r\n");
    return;
  }
  client.printf(
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: image/jpeg\r\n"
    "Content-Length: %u\r\n"
    "Access-Control-Allow-Origin: *\r\n"
    "Connection: close\r\n\r\n",
    (unsigned)jpg_len
  );
  client.write(jpg_buf, jpg_len);
  free(jpg_buf);
}

// ----- Status JSON (GET /status) --------------------------------------------
void statusTo(WiFiClient& client) {
  String ip = (WiFi.getMode() == WIFI_AP)
                  ? WiFi.softAPIP().toString()
                  : WiFi.localIP().toString();
  String json = String("{\"name\":\"brutus-cam\",\"ip\":\"") + ip +
                "\",\"flash\":" + (flashOn ? "true" : "false") +
                ",\"psram\":" + (psramFound() ? "true" : "false") + "}";
  client.print("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
               "Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n");
  client.print(json);
}

void setFlash(bool on) {
  flashOn = on;
  digitalWrite(FLASH_LED_GPIO, on ? HIGH : LOW);
}

void handleClient(WiFiClient& client) {
  // Read the request line to route the endpoints.
  String reqLine = client.readStringUntil('\n');
  // Drain remaining headers.
  while (client.available()) {
    String line = client.readStringUntil('\n');
    if (line == "\r") break;
  }

  if (reqLine.indexOf("/stream") >= 0) {
    streamTo(client);
  } else if (reqLine.indexOf("/capture") >= 0) {
    captureTo(client);
  } else if (reqLine.indexOf("/status") >= 0) {
    statusTo(client);
  } else if (reqLine.indexOf("/flash") >= 0) {
    // /flash?on=1 turns the LED on; anything else off.
    setFlash(reqLine.indexOf("on=1") >= 0);
    client.print("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n"
                 "Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n");
    client.print(flashOn ? "flash on" : "flash off");
  } else {
    // Simple landing page with links to every endpoint.
    client.print(
      "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n"
      "<h3>Brutus ESP32-CAM</h3>"
      "<p>Live stream: <a href=\"/stream\">/stream</a></p>"
      "<p>Snapshot: <a href=\"/capture\">/capture</a></p>"
      "<p>Status: <a href=\"/status\">/status</a></p>"
      "<p>Flash: <a href=\"/flash?on=1\">on</a> &middot; <a href=\"/flash?on=0\">off</a></p>"
    );
  }
  client.stop();
}

// ----- Arduino entry points -------------------------------------------------
void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(false);

  pinMode(FLASH_LED_GPIO, OUTPUT);
  digitalWrite(FLASH_LED_GPIO, LOW);  // flash off at boot

  if (!initCamera()) {
    Serial.println("Halting: camera not available.");
    while (true) delay(1000);
  }
  initWiFi();
  server.begin();
  Serial.println("Stream server started.");
}

void loop() {
  WiFiClient client = server.available();
  if (client) {
    handleClient(client);
  }
}
