/* ===================================================================
   BRUTUS v2.0 — Humanoid Body/Brain Controller  (ESP32 #1)
   ===================================================================
   BLE server the Brutus phone app connects to directly — NO HM-10
   module needed (the ESP32 has Bluetooth built in).

   ── BLE profile (HM-10 compatible — matches the existing app) ──
     Service        : 0000FFE0-0000-1000-8000-00805F9B34FB
     Characteristic : 0000FFE1-0000-1000-8000-00805F9B34FB
                      (app WRITES commands, robot NOTIFIES replies)
     Advertised name: "BrutusV2"

   ── Primary command protocol (what the app sends, '\n' terminated) ──
     E<n>        expression 0-5 (0 happy, 1 angry, 2 sad, 3 thinking,
                                 4 sleepy, 5 surprised)
     E<n>,<i>    expression with intensity 0-100
     M<a>        mouth angle 0-180 (lip-sync, ~40 Hz)
     L<lr>,<ud>  eye look-at (both axes 0-180)
     B           blink now
     I<0|1>      idle fallback off/on (robot's own micro-animations)
     S<0|1>      freeze mode off/on (disables ALL autonomous motion)
     A<n>        play animation macro 0-9 (nod, shake, look_around,
                 wink, yawn, laugh, eye_roll, mouth_cycle, eye_cycle,
                 wiggle)
     W<n>        play movement trick 0-9 (crazy_eyes, chatter,
                 slow_scan, peekaboo, double_blink, jaw_drop, drowsy,
                 side_eye, happy_bounce, confused)
     C<n>        LED pattern (0 off, 1 solid, 2 pulse, 3 fast blink)
     H           heartbeat — replies "OK\n"

   ── Extra verbose commands (testing via nRF Connect etc.) ──
     MOVE:F|B|S      drive motor forward / back / stop
     NECK:<0-180>    neck servo
     HANDL:<0-180>   left hand      HANDR:<0-180>  right hand
     WAVE            wave the right hand
     LED:<0-2>       LED colour: 0 off, 1 blue, 2 green
     BUZZ:<0-1>      buzzer off/on
     AVOID:<0-1>     autonomous walk + obstacle-avoid off/on
     PING            replies "OK"

   ── UPLOAD ──
     Board "ESP32 Dev Module", esp32 core 3.x, Upload Speed 115200.
     Board must be BARE while flashing (no robot wiring attached).
   =================================================================== */

#include <ESP32Servo.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
// Brownout register access — lets us relax the aggressive brownout reset
// that reboots the board on brief voltage dips (see setup()).
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

// ===================================================================
// 1. PIN MAP (matches the existing wiring — change ONLY if you rewire)
// ===================================================================
// --- TB6612FNG motor driver (drive base) ---
const int PIN_PWMA = 21;  // Motor A speed (PWM)
const int PIN_AIN1 = 19;  // Motor A dir 1
const int PIN_AIN2 = 22;  // Motor A dir 2
const int PIN_STBY = 23;  // Standby (HIGH = driver enabled)

// --- 7 servos ---
const int PIN_LEFT_EYE_LR = 13;
const int PIN_EYE_UD      = 12;  // NOTE: GPIO12 is a boot "strapping" pin.
                                 // If the board ever fails to boot, move
                                 // this servo's signal wire to GPIO32 and
                                 // set PIN_EYE_UD = 32.
const int PIN_EYELID      = 14;
const int PIN_MOUTH       = 27;
const int PIN_NECK        = 26;
const int PIN_LEFT_HAND   = 25;
const int PIN_RIGHT_HAND  = 33;

// --- HC-SR04 ultrasonic ---
const int PIN_ULTRA_TRIG = 5;
const int PIN_ULTRA_ECHO = 18;

// --- Eye LEDs ---
const int PIN_EYE_BLUE  = 2;
const int PIN_EYE_GREEN = 4;

// --- Buzzer ---
const int PIN_BUZZER = 15;

// --- Motor speed 0..255 ---
const int MOTOR_SPEED = 200;

// ===================================================================
// 2. BLE  (HM-10 compatible profile — the app connects to this)
// ===================================================================
#define SERVICE_UUID "0000FFE0-0000-1000-8000-00805F9B34FB"
#define CHAR_UUID    "0000FFE1-0000-1000-8000-00805F9B34FB"

BLEServer* gServer = nullptr;
BLECharacteristic* gChar = nullptr;
bool gConnected = false;

// Commands received in the BLE callback (which runs on a DIFFERENT core
// than loop()) are handed over through fixed char buffers + a volatile
// flag. We do NOT share an Arduino String across the two cores — that can
// corrupt the heap and cause random crashes/resets.
#define CMD_MAX 64
char gRxBuf[CMD_MAX];        // assembled only inside the BLE task
uint8_t gRxLen = 0;
char gPendingCmd[CMD_MAX];   // handed to loop()
volatile bool gHasLine = false;

// ===================================================================
// 3. SERVOS + SMOOTHING
// ===================================================================
Servo servoEyeLR, servoEyeUD, servoEyelid, servoMouth;
Servo servoNeck, servoHandL, servoHandR;

// Non-blocking servo interpolation: every tick each servo steps toward its
// target by SERVO_STEP degrees. Mouth is exempt (snaps) for tight lip-sync.
const int SERVO_STEP = 4;

int curEyeLR = 90, tgtEyeLR = 90;
int curEyeUD = 90, tgtEyeUD = 90;
int curLid   = 90, tgtLid   = 90;
int curNeck  = 90, tgtNeck  = 90;
int curHandL = 90, tgtHandL = 90;
int curHandR = 90, tgtHandR = 90;
int curMouth = 0;  // snaps directly

int stepToward(int cur, int tgt, int step) {
  if (cur < tgt) return min(cur + step, tgt);
  if (cur > tgt) return max(cur - step, tgt);
  return cur;
}

void updateServos() {
  curEyeLR = stepToward(curEyeLR, tgtEyeLR, SERVO_STEP);
  curEyeUD = stepToward(curEyeUD, tgtEyeUD, SERVO_STEP);
  curLid   = stepToward(curLid,   tgtLid,   SERVO_STEP);
  curNeck  = stepToward(curNeck,  tgtNeck,  SERVO_STEP);
  curHandL = stepToward(curHandL, tgtHandL, SERVO_STEP);
  curHandR = stepToward(curHandR, tgtHandR, SERVO_STEP);
  servoEyeLR.write(curEyeLR);
  servoEyeUD.write(curEyeUD);
  servoEyelid.write(curLid);
  servoNeck.write(curNeck);
  servoHandL.write(curHandL);
  servoHandR.write(curHandR);
  servoMouth.write(curMouth);
}

// ===================================================================
// 4. STATE
// ===================================================================
bool avoidMode   = false;  // autonomous walk + obstacle avoid
bool freezeMode  = false;  // disables all autonomous motion
bool idleEnabled = true;   // robot's own blink/eye-drift (I command)

int ledColor   = 1;  // 0 off, 1 blue, 2 green   (LED: command)
int ledPattern = 1;  // 0 off, 1 solid, 2 pulse, 3 fast  (C command)
bool buzzerOn = false;

unsigned long lastServoTick = 0;
const long SERVO_INTERVAL = 20;  // 50 Hz servo refresh

unsigned long lastBlinkAt = 0;
long nextBlinkGap = 4000;
unsigned long lastEyeIdleAt = 0;
long nextEyeIdleGap = 1500;

unsigned long lastDistanceAt = 0;
const long DISTANCE_INTERVAL = 120;  // read ultrasonic at most ~8x/sec
long lastDistanceCm = 999;

// non-blocking blink
enum BlinkPhase { BLINK_NONE, BLINK_CLOSING, BLINK_OPENING };
BlinkPhase blinkPhase = BLINK_NONE;
unsigned long blinkAt = 0;
int blinkRestoreLid = 90;

// wave routine
bool waveActive = false;
int waveStep = 0;
unsigned long waveAt = 0;

// ===================================================================
// 5. EXPRESSIONS  (app order: 0 happy 1 angry 2 sad 3 thinking
//                  4 sleepy 5 surprised)  { neck, lid, eyeLR, eyeUD, mouth }
// ===================================================================
struct Expr { int neck, lid, eyeLR, eyeUD, mouth; };

const Expr EXPRESSIONS[6] = {
  //  neck  lid  eyeLR eyeUD mouth
  {    90, 110,   90,   80,   35 },  // 0 happy   — relaxed, slight smile
  {    85,  55,   90,   70,   10 },  // 1 angry   — squint, jaw tight
  {    80,  60,   75,  115,    5 },  // 2 sad     — droopy, averted gaze
  {    95,  90,   60,   70,    0 },  // 3 thinking— eyes up-left
  {    90,  30,   90,  100,    0 },  // 4 sleepy  — nearly closed
  {    95, 160,   90,   85,   65 },  // 5 surprised — wide eyes, mouth open
};

// Scale a preset toward neutral (90 / mouth 0) by intensity 0-100 —
// same formula the original Brutus head used.
void applyExpression(int idx, int intensity) {
  if (idx < 0 || idx > 5) return;
  intensity = constrain(intensity, 0, 100);
  const Expr& e = EXPRESSIONS[idx];
  tgtNeck  = 90 + (e.neck  - 90) * intensity / 100;
  tgtLid   = 90 + (e.lid   - 90) * intensity / 100;
  tgtEyeLR = 90 + (e.eyeLR - 90) * intensity / 100;
  tgtEyeUD = 90 + (e.eyeUD - 90) * intensity / 100;
  curMouth = constrain(e.mouth * intensity / 100, 0, 180);
}

void neutralPose() {
  tgtNeck = 90; tgtLid = 90; tgtEyeLR = 90; tgtEyeUD = 90; curMouth = 0;
  tgtHandL = 90; tgtHandR = 90;
}

// ===================================================================
// 6. KEYFRAME ENGINE  (animations A0-A9, tricks W0-W9)
//    Each keyframe: hold time (ms) + servo targets (-1 = leave as-is).
// ===================================================================
struct KF { uint16_t ms; int16_t neck, lid, eyeLR, eyeUD, mouth, handL, handR; };

//                      ms  neck lid  eLR  eUD  mou  hnL  hnR
const KF ANIM_NOD[] = {
  { 300, -1, -1, -1,  60, -1, -1, -1 },
  { 300, -1, -1, -1, 120, -1, -1, -1 },
  { 300, -1, -1, -1,  60, -1, -1, -1 },
  { 300, -1, -1, -1,  90, -1, -1, -1 },
};
const KF ANIM_SHAKE[] = {
  { 300,  60, -1, -1, -1, -1, -1, -1 },
  { 300, 120, -1, -1, -1, -1, -1, -1 },
  { 300,  60, -1, -1, -1, -1, -1, -1 },
  { 300,  90, -1, -1, -1, -1, -1, -1 },
};
const KF ANIM_LOOK_AROUND[] = {
  { 400, -1, -1,  40, -1, -1, -1, -1 },
  { 400, -1, -1, 140, -1, -1, -1, -1 },
  { 300, -1, -1,  90,  60, -1, -1, -1 },
  { 300, -1, -1,  90, 110, -1, -1, -1 },
  { 300, -1, -1,  90,  90, -1, -1, -1 },
};
const KF ANIM_WINK[] = {
  { 150, -1,  20, -1, -1, -1, -1, -1 },
  { 150, -1,  90, -1, -1, -1, -1, -1 },
  { 250, -1, 110, -1, -1, 35, -1, -1 },
  { 200, -1,  90, -1, -1,  0, -1, -1 },
};
const KF ANIM_YAWN[] = {
  { 600, -1,  60, -1, -1, 70, -1, -1 },
  { 400, -1,  40, -1, 100, 70, -1, -1 },
  { 300, -1,  40, -1, -1,  0, -1, -1 },
  { 200, -1,  90, -1,  90,  0, -1, -1 },
};
const KF ANIM_LAUGH[] = {
  { 120, -1, 110, -1, 80, 50, -1, -1 },
  { 120, -1, -1, -1, -1, 10, -1, -1 },
  { 120, -1, -1, -1, -1, 50, -1, -1 },
  { 120, -1, -1, -1, -1, 10, -1, -1 },
  { 120, -1, -1, -1, -1, 50, -1, -1 },
  { 200, -1,  90, -1, 90,  0, -1, -1 },
};
const KF ANIM_EYE_ROLL[] = {
  { 250, -1, -1,  40,  60, -1, -1, -1 },
  { 250, -1, -1,  90,  50, -1, -1, -1 },
  { 250, -1, -1, 140,  60, -1, -1, -1 },
  { 250, -1, -1,  90, 110, -1, -1, -1 },
  { 250, -1, -1,  90,  90, -1, -1, -1 },
};
const KF ANIM_MOUTH_CYCLE[] = {
  { 250, -1, -1, -1, -1, 60, -1, -1 },
  { 250, -1, -1, -1, -1,  0, -1, -1 },
  { 250, -1, -1, -1, -1, 60, -1, -1 },
  { 250, -1, -1, -1, -1,  0, -1, -1 },
};
const KF ANIM_EYE_CYCLE[] = {
  { 250, -1,  20, -1, -1, -1, -1, -1 },
  { 250, -1,  90, -1, -1, -1, -1, -1 },
  { 250, -1,  20, -1, -1, -1, -1, -1 },
  { 250, -1,  90, -1, -1, -1, -1, -1 },
};
const KF ANIM_WIGGLE[] = {
  { 150,  70, -1, -1, -1, -1, 110,  70 },
  { 150, 110, -1, -1, -1, -1,  70, 110 },
  { 150,  70, -1, -1, -1, -1, 110,  70 },
  { 150, 110, -1, -1, -1, -1,  70, 110 },
  { 200,  90, -1, -1, -1, -1,  90,  90 },
};

const KF TRICK_CRAZY_EYES[] = {
  { 100, -1, -1,  40,  70, -1, -1, -1 },
  { 100, -1, -1, 140, 110, -1, -1, -1 },
  { 100, -1, -1,  60,  60, -1, -1, -1 },
  { 100, -1, -1, 120, 110, -1, -1, -1 },
  { 150, -1, -1,  90,  90, -1, -1, -1 },
};
const KF TRICK_CHATTER[] = {
  { 80, -1, -1, -1, -1, 25, -1, -1 },
  { 80, -1, -1, -1, -1,  0, -1, -1 },
  { 80, -1, -1, -1, -1, 25, -1, -1 },
  { 80, -1, -1, -1, -1,  0, -1, -1 },
  { 80, -1, -1, -1, -1, 25, -1, -1 },
  { 80, -1, -1, -1, -1,  0, -1, -1 },
};
const KF TRICK_SLOW_SCAN[] = {
  { 1000, -1, -1,  30, -1, -1, -1, -1 },
  { 2000, -1, -1, 150, -1, -1, -1, -1 },
  { 1000, -1, -1,  90, -1, -1, -1, -1 },
};
const KF TRICK_PEEKABOO[] = {
  { 800, -1,   5, -1, -1,  0, -1, -1 },
  { 400, -1, 160, -1, -1, 60, -1, -1 },
  { 300, -1,  90, -1, -1,  0, -1, -1 },
};
const KF TRICK_DOUBLE_BLINK[] = {
  { 120, -1,  15, -1, -1, -1, -1, -1 },
  { 120, -1,  90, -1, -1, -1, -1, -1 },
  { 120, -1,  15, -1, -1, -1, -1, -1 },
  { 120, -1,  90, -1, -1, -1, -1, -1 },
};
const KF TRICK_JAW_DROP[] = {
  { 300, -1, 120, -1, -1, 20, -1, -1 },
  { 300, -1, 140, -1, -1, 40, -1, -1 },
  { 600, -1, 160, -1, -1, 75, -1, -1 },
  { 300, -1,  90, -1, -1,  0, -1, -1 },
};
const KF TRICK_DROWSY[] = {
  { 600, -1, 60, -1, 100, -1, -1, -1 },
  { 600, -1, 30, -1, 105, -1, -1, -1 },
  { 800, -1, 10, -1, 110, -1, -1, -1 },
  { 200, -1, 90, -1,  90, -1, -1, -1 },
};
const KF TRICK_SIDE_EYE[] = {
  {  250, -1, 70,  40, -1, -1, -1, -1 },
  { 1000, -1, -1, -1, -1, -1, -1, -1 },
  {  300, -1, 90,  90, -1, -1, -1, -1 },
};
const KF TRICK_HAPPY_BOUNCE[] = {
  { 200, -1, 110, -1,  70, 40, 120,  60 },
  { 200, -1, -1, -1, 110, -1,  60, 120 },
  { 200, -1, -1, -1,  70, -1, 120,  60 },
  { 200, -1, -1, -1, 110, -1,  60, 120 },
  { 250, -1,  90, -1,  90,  0,  90,  90 },
};
const KF TRICK_CONFUSED[] = {
  { 400,  75, -1, -1, -1, -1, -1, -1 },
  { 400, -1, -1, 120,  70, -1, -1, -1 },
  { 400, 105, -1, -1, -1, -1, -1, -1 },
  { 400, -1, -1,  60,  70, -1, -1, -1 },
  { 400,  90, -1,  90,  90, -1, -1, -1 },
};

struct Seq { const KF* kf; uint8_t n; };
#define SEQ(a) { a, (uint8_t)(sizeof(a) / sizeof(a[0])) }

const Seq ANIMS[10] = {
  SEQ(ANIM_NOD), SEQ(ANIM_SHAKE), SEQ(ANIM_LOOK_AROUND), SEQ(ANIM_WINK),
  SEQ(ANIM_YAWN), SEQ(ANIM_LAUGH), SEQ(ANIM_EYE_ROLL), SEQ(ANIM_MOUTH_CYCLE),
  SEQ(ANIM_EYE_CYCLE), SEQ(ANIM_WIGGLE),
};
const Seq TRICKS[10] = {
  SEQ(TRICK_CRAZY_EYES), SEQ(TRICK_CHATTER), SEQ(TRICK_SLOW_SCAN),
  SEQ(TRICK_PEEKABOO), SEQ(TRICK_DOUBLE_BLINK), SEQ(TRICK_JAW_DROP),
  SEQ(TRICK_DROWSY), SEQ(TRICK_SIDE_EYE), SEQ(TRICK_HAPPY_BOUNCE),
  SEQ(TRICK_CONFUSED),
};

const KF* seqActive = nullptr;
uint8_t seqLen = 0, seqIdx = 0;
unsigned long seqAt = 0;

void applyKF(const KF& k) {
  if (k.neck  >= 0) tgtNeck  = k.neck;
  if (k.lid   >= 0) tgtLid   = k.lid;
  if (k.eyeLR >= 0) tgtEyeLR = k.eyeLR;
  if (k.eyeUD >= 0) tgtEyeUD = k.eyeUD;
  if (k.mouth >= 0) curMouth = k.mouth;
  if (k.handL >= 0) tgtHandL = k.handL;
  if (k.handR >= 0) tgtHandR = k.handR;
}

void startSequence(const Seq& s) {
  if (freezeMode) return;
  seqActive = s.kf;
  seqLen = s.n;
  seqIdx = 0;
  seqAt = millis();
  applyKF(seqActive[0]);
}

void updateSequence() {
  if (seqActive == nullptr) return;
  if (millis() - seqAt < seqActive[seqIdx].ms) return;
  seqIdx++;
  if (seqIdx >= seqLen) {
    seqActive = nullptr;
    return;
  }
  seqAt = millis();
  applyKF(seqActive[seqIdx]);
}

// ===================================================================
// 7. OUTPUT HELPERS
// ===================================================================
void updateLed() {
  bool on;
  switch (ledPattern) {
    case 1:  on = true; break;
    case 2:  on = ((millis() / 500) % 2) == 0; break;  // pulse ~1 Hz
    case 3:  on = ((millis() / 100) % 2) == 0; break;  // fast ~5 Hz
    default: on = false; break;                        // 0 = off
  }
  digitalWrite(PIN_EYE_BLUE,  (ledColor == 1 && on) ? HIGH : LOW);
  digitalWrite(PIN_EYE_GREEN, (ledColor == 2 && on) ? HIGH : LOW);
}

void setBuzzer(bool on) {
  buzzerOn = on;
  digitalWrite(PIN_BUZZER, on ? HIGH : LOW);
}

void motorForward() {
  digitalWrite(PIN_AIN1, HIGH);
  digitalWrite(PIN_AIN2, LOW);
  ledcWrite(PIN_PWMA, MOTOR_SPEED);
}

void motorBack() {
  digitalWrite(PIN_AIN1, LOW);
  digitalWrite(PIN_AIN2, HIGH);
  ledcWrite(PIN_PWMA, MOTOR_SPEED);
}

void motorStop() {
  digitalWrite(PIN_AIN1, LOW);
  digitalWrite(PIN_AIN2, LOW);
  ledcWrite(PIN_PWMA, 0);
}

void startBlink() {
  if (blinkPhase != BLINK_NONE) return;
  blinkRestoreLid = tgtLid;
  blinkPhase = BLINK_CLOSING;
  blinkAt = millis();
  tgtLid = 15;
  curLid = 15;  // snap closed for a crisp blink
}

void updateBlink() {
  if (blinkPhase == BLINK_NONE) return;
  const unsigned long now = millis();
  if (blinkPhase == BLINK_CLOSING && now - blinkAt > 90) {
    blinkPhase = BLINK_OPENING;
    blinkAt = now;
    tgtLid = blinkRestoreLid;
  } else if (blinkPhase == BLINK_OPENING && now - blinkAt > 90) {
    blinkPhase = BLINK_NONE;
    tgtLid = blinkRestoreLid;
  }
}

void startWave() {
  waveActive = true;
  waveStep = 0;
  waveAt = 0;  // fire immediately
}

void updateWave() {
  if (!waveActive) return;
  const unsigned long now = millis();
  if (now - waveAt < 220) return;
  waveAt = now;
  switch (waveStep) {
    case 0: tgtHandR = 160; break;
    case 1: tgtHandR = 110; break;
    case 2: tgtHandR = 160; break;
    case 3: tgtHandR = 110; break;
    case 4: tgtHandR = 160; break;
    default:
      tgtHandR = 90;
      waveActive = false;
      break;
  }
  waveStep++;
}

// ===================================================================
// 8. ULTRASONIC (only used in AVOID mode)
// ===================================================================
long readDistanceCm() {
  digitalWrite(PIN_ULTRA_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_ULTRA_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_ULTRA_TRIG, LOW);
  long dur = pulseIn(PIN_ULTRA_ECHO, HIGH, 20000);  // 20 ms timeout (~3.4 m)
  if (dur == 0) return 999;  // nothing in range
  return dur * 0.034 / 2;
}

// ===================================================================
// 9. COMMAND PARSER  (HM-10 single-letter + verbose)
// ===================================================================
void notifyStr(const char* msg) {
  if (gConnected && gChar != nullptr) {
    String out = String(msg) + "\n";
    gChar->setValue((uint8_t*)out.c_str(), out.length());
    gChar->notify();
  }
}

void setFreeze(bool on) {
  freezeMode = on;
  if (on) {
    avoidMode = false;
    motorStop();
    seqActive = nullptr;
    waveActive = false;
  }
}

// Single-letter HM-10 protocol (what the Brutus app sends).
void handleShortCommand(const String& line) {
  const char c = toupper(line.charAt(0));
  const String a = line.substring(1);
  switch (c) {
    case 'E': {  // E<n> or E<n>,<i>
      int comma = a.indexOf(',');
      int n = (comma < 0 ? a : a.substring(0, comma)).toInt();
      int i = (comma < 0) ? 100 : a.substring(comma + 1).toInt();
      applyExpression(n, i);
      break;
    }
    case 'M':  // mouth angle (lip-sync)
      curMouth = constrain(a.toInt(), 0, 180);
      break;
    case 'L': {  // L<lr>,<ud>
      int comma = a.indexOf(',');
      if (comma > 0) {
        tgtEyeLR = constrain(a.substring(0, comma).toInt(), 0, 180);
        tgtEyeUD = constrain(a.substring(comma + 1).toInt(), 0, 180);
      }
      break;
    }
    case 'B': startBlink(); break;
    case 'I': idleEnabled = (a.toInt() == 1); break;
    case 'S': setFreeze(a.toInt() == 1); break;
    case 'A': {
      int n = a.toInt();
      if (n >= 0 && n <= 9) startSequence(ANIMS[n]);
      break;
    }
    case 'W': {
      int n = a.toInt();
      if (n >= 0 && n <= 9) startSequence(TRICKS[n]);
      break;
    }
    case 'C': ledPattern = constrain(a.toInt(), 0, 3); break;
    case 'H': notifyStr("OK"); break;
    default: break;  // unknown — ignore
  }
}

// Verbose protocol (testing / future app features).
void handleVerboseCommand(String cmd, String arg) {
  cmd.toUpperCase();
  if (cmd == "PING") { notifyStr("OK"); return; }
  if (cmd == "MOVE") {
    arg.trim(); arg.toUpperCase();
    if (freezeMode) return;
    if (arg == "F") motorForward();
    else if (arg == "B") motorBack();
    else motorStop();
    return;
  }
  if (cmd == "NECK")  { tgtNeck  = constrain(arg.toInt(), 0, 180); return; }
  if (cmd == "LID")   { tgtLid   = constrain(arg.toInt(), 0, 180); return; }
  if (cmd == "MOUTH") { curMouth = constrain(arg.toInt(), 0, 180); return; }
  if (cmd == "HANDL") { tgtHandL = constrain(arg.toInt(), 0, 180); return; }
  if (cmd == "HANDR") { tgtHandR = constrain(arg.toInt(), 0, 180); return; }
  if (cmd == "EYES") {
    int c = arg.indexOf(',');
    if (c > 0) {
      tgtEyeLR = constrain(arg.substring(0, c).toInt(), 0, 180);
      tgtEyeUD = constrain(arg.substring(c + 1).toInt(), 0, 180);
    }
    return;
  }
  if (cmd == "BLINK") { startBlink(); return; }
  if (cmd == "WAVE")  { startWave(); return; }
  if (cmd == "EXPR")  { applyExpression(arg.toInt(), 100); return; }
  if (cmd == "LED")   { ledColor = constrain(arg.toInt(), 0, 2); return; }
  if (cmd == "BUZZ")  { setBuzzer(arg.toInt() == 1); return; }
  if (cmd == "FREEZE") { setFreeze(arg.toInt() == 1); return; }
  if (cmd == "AVOID") {
    avoidMode = (arg.toInt() == 1) && !freezeMode;
    if (!avoidMode) motorStop();
    return;
  }
}

void handleCommand(String line) {
  line.trim();
  if (line.length() == 0) return;

  int colon = line.indexOf(':');
  if (colon >= 0) {
    handleVerboseCommand(line.substring(0, colon), line.substring(colon + 1));
    return;
  }
  // Colon-less verbose words
  String upper = line;
  upper.toUpperCase();
  if (upper == "PING")  { notifyStr("OK"); return; }
  if (upper == "BLINK") { startBlink(); return; }
  if (upper == "WAVE")  { startWave(); return; }

  // Everything else: single-letter HM-10 protocol (E2,50 / M140 / A3 / H ...)
  handleShortCommand(line);
}

// ===================================================================
// 10. BLE CALLBACKS
// ===================================================================
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    gConnected = true;
  }
  void onDisconnect(BLEServer* s) override {
    gConnected = false;
    motorStop();                    // safety: never keep driving after a drop
    s->getAdvertising()->start();   // allow reconnection
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String chunk = String(c->getValue().c_str());
    for (unsigned int i = 0; i < chunk.length(); i++) {
      char ch = chunk[i];
      if (ch == '\n' || ch == '\r') {
        if (gRxLen > 0) {
          gRxBuf[gRxLen] = 0;
          // Only hand over when loop() has consumed the previous line, so
          // we never touch the shared buffer while loop() is reading it.
          if (!gHasLine) {
            strncpy(gPendingCmd, gRxBuf, CMD_MAX);
            gPendingCmd[CMD_MAX - 1] = 0;
            gHasLine = true;
          }
          gRxLen = 0;
        }
      } else if (gRxLen < CMD_MAX - 1) {
        gRxBuf[gRxLen++] = ch;
      } else {
        gRxLen = 0;  // overflow guard
      }
    }
  }
};

void setupBle() {
  BLEDevice::init("BrutusV2");
  gServer = BLEDevice::createServer();
  gServer->setCallbacks(new ServerCallbacks());

  BLEService* svc = gServer->createService(SERVICE_UUID);

  // Single HM-10-style characteristic: app writes commands AND subscribes
  // to notifications on the same FFE1 characteristic.
  gChar = svc->createCharacteristic(
      CHAR_UUID,
      BLECharacteristic::PROPERTY_READ |
          BLECharacteristic::PROPERTY_WRITE |
          BLECharacteristic::PROPERTY_WRITE_NR |
          BLECharacteristic::PROPERTY_NOTIFY);
  gChar->addDescriptor(new BLE2902());
  gChar->setCallbacks(new RxCallbacks());

  svc->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  adv->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
}

// ===================================================================
// 11. SETUP
// ===================================================================
void setup() {
  Serial.begin(115200);

  // ── Stop random resets on power dips ──
  // The battery rail sags when servos/the motor pull current at once, and
  // the ESP32's brownout detector then RESETS the board ("runs a few
  // seconds then stops" symptom). Disabling it stops the reboot loop.
  // This is a MITIGATION — the real cure is a stronger 5V supply (>=3A)
  // plus a 1000 uF capacitor across the servo power rail.
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

  // Motor driver
  pinMode(PIN_AIN1, OUTPUT);
  pinMode(PIN_AIN2, OUTPUT);
  pinMode(PIN_STBY, OUTPUT);
  ledcAttach(PIN_PWMA, 5000, 8);  // 5 kHz, 8-bit
  digitalWrite(PIN_STBY, HIGH);
  motorStop();

  // Servo timers
  ESP32PWM::allocateTimer(0);
  ESP32PWM::allocateTimer(1);
  ESP32PWM::allocateTimer(2);
  ESP32PWM::allocateTimer(3);

  // Attach servos one at a time with a small gap so they don't all draw
  // start-up current at the same instant (reduces the boot voltage dip).
  servoEyeLR.attach(PIN_LEFT_EYE_LR, 500, 2400); delay(40);
  servoEyeUD.attach(PIN_EYE_UD, 500, 2400);      delay(40);
  servoEyelid.attach(PIN_EYELID, 500, 2400);     delay(40);
  servoMouth.attach(PIN_MOUTH, 500, 2400);       delay(40);
  servoNeck.attach(PIN_NECK, 500, 2400);         delay(40);
  servoHandL.attach(PIN_LEFT_HAND, 500, 2400);   delay(40);
  servoHandR.attach(PIN_RIGHT_HAND, 500, 2400);

  pinMode(PIN_EYE_BLUE, OUTPUT);
  pinMode(PIN_EYE_GREEN, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_ULTRA_TRIG, OUTPUT);
  pinMode(PIN_ULTRA_ECHO, INPUT);

  neutralPose();
  updateServos();

  setupBle();
  Serial.println("BrutusV2 ready — advertising over BLE as \"BrutusV2\"");
}

// ===================================================================
// 12. LOOP
// ===================================================================
void loop() {
  // 1) Drain any pending BLE command line (copy it out before clearing
  //    the flag so the BLE task can immediately queue the next one).
  if (gHasLine) {
    char line[CMD_MAX];
    strncpy(line, gPendingCmd, CMD_MAX);
    line[CMD_MAX - 1] = 0;
    gHasLine = false;
    handleCommand(String(line));
  }

  const unsigned long now = millis();

  // 2) Autonomous obstacle-avoid (only when explicitly enabled).
  if (avoidMode && !freezeMode) {
    if (now - lastDistanceAt >= DISTANCE_INTERVAL) {
      lastDistanceAt = now;
      lastDistanceCm = readDistanceCm();

      if (lastDistanceCm > 0 && lastDistanceCm < 30) {
        // Obstacle: stop, alert face, green eyes, chirp.
        motorStop();
        applyExpression(5, 100);  // surprised
        ledColor = 2;             // green
        ledPattern = 3;           // fast blink
        setBuzzer(((now / 200) % 2) == 0);
        notifyStr("OBSTACLE");
      } else {
        motorForward();
        ledColor = 1;   // blue = clear
        ledPattern = 1; // solid
        setBuzzer(false);
      }
    }
  }

  // 3) Idle micro-animation — only when enabled (I1), not frozen, and no
  //    scripted sequence is running. Keeps the face "alive" without
  //    fighting app commands.
  if (idleEnabled && !freezeMode && seqActive == nullptr) {
    if (now - lastBlinkAt > (unsigned long)nextBlinkGap) {
      lastBlinkAt = now;
      nextBlinkGap = random(3000, 6000);
      startBlink();
    }
    // gentle eye drift only when the eyes are near center
    if (!avoidMode && now - lastEyeIdleAt > (unsigned long)nextEyeIdleGap) {
      lastEyeIdleAt = now;
      nextEyeIdleGap = random(1200, 3000);
      if (abs(tgtEyeLR - 90) < 25 && abs(tgtEyeUD - 90) < 25) {
        tgtEyeLR = random(75, 106);
        tgtEyeUD = random(80, 101);
      }
    }
  }

  updateBlink();
  updateWave();
  updateSequence();
  updateLed();

  // 4) Smooth servo tick.
  if (now - lastServoTick >= SERVO_INTERVAL) {
    lastServoTick = now;
    updateServos();
  }
}
