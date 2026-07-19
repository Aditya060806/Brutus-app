# ESP32-CAM MJPEG stream (Brutus Sense Station)

Serves an MJPEG stream that the UNO Q's `vision.py` reads with OpenCV at
`http://<CAM_IP>:81/stream`.

## Arduino IDE setup

1. Install the **ESP32 core**: Boards Manager -> search "esp32" (Espressif) -> Install.
2. Select board: **Tools -> Board -> ESP32 Arduino -> "AI Thinker ESP32-CAM"**.
3. Open `esp32cam_stream.ino`.

## Network behavior (STA-first, AP-fallback)

The sketch tries to join your router first, then falls back to its own AP:

1. Set `STA_SSID` / `STA_PASS` (top of the sketch) to your travel router.
2. On boot it tries to join that router for `STA_CONNECT_TIMEOUT_MS` (15 s).
   - **Success:** it prints its router IP on Serial (115200). Set
     `BRUTUS_STREAM_URL` on the UNO Q to `http://<that-ip>:81/stream`. Now the
     camera, the UNO Q, and your laptop all share one network with internet.
   - **Failure:** it starts its own AP `brutus-cam` / `brutuscam` at
     **192.168.4.1**, which matches the default `BRUTUS_STREAM_URL`. Join that
     network to reach the stream.
3. Set `FORCE_AP = true` if you want to always run as an AP and skip the router.

## Flashing with the ESP32-CAM-MB (micro-USB dock) -- what you have

The ESP32-CAM-MB dock has a CH340 USB-serial chip built in, so **no USB-TTL
adapter and no GPIO0 jumper needed**. Just:

1. Seat the ESP32-CAM firmly into the MB dock (pins fully in).
2. Plug a **micro-USB data cable** (not charge-only) into the MB dock.
3. If Windows doesn't detect a COM port, install the **CH340 driver** and replug.
4. In Arduino IDE: **Tools -> Board -> "AI Thinker ESP32-CAM"**, and select the
   **Port** (the COM port that appeared).
5. Click **Upload**.

Auto-reset: the MB dock usually resets into bootloader automatically. If Upload
stalls at *"Connecting........_____"*, **hold the BOOT/IO0 button** on the dock
while it connects, release once flashing starts. Press **RST** after upload to
run the sketch.

> Recommended upload speed: Tools -> Upload Speed -> 460800 (drop to 115200 if
> you get sync/timeout errors).

## Verify

Open `http://<CAM_IP>:81/stream` in a browser on the same network. You should
see live video. If it loads, OpenCV will too.

## Notes

- Default resolution is **QVGA (320x240)** at JPEG quality 12 to keep bandwidth
  low; `vision.py` downscales to 320 wide anyway. Bump `FRAMESIZE_*` in the
  sketch if you want a larger picture.
- If `esp_camera_init` fails (0x105 / no PSRAM etc.), power the board from a
  solid 5V source, brownouts on weak USB power are the usual cause.
- **"JPEG format is not supported on this sensor":** your module's sensor can't
  produce hardware JPEG (some clones ship non-OV2640 sensors). The sketch
  handles this by capturing RGB565 and software-encoding to JPEG via
  `frame2jpg()`. Also reseat the camera ribbon (FFC) connector, a loose cable
  can make the sensor misreport its capabilities.
- Pin map is for the AI-Thinker module. Other modules (ESP32-S3-CAM, M5, etc.)
  need a different pin map, tell me which one and I'll swap it.
