<div align="center">

# Brutus AI

### An AI assistant that lives in two places at once: your phone, and a robot head that moves its face when it talks.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Arduino](https://img.shields.io/badge/Arduino-Uno-00979D?style=for-the-badge&logo=arduino&logoColor=white)](https://www.arduino.cc)
[![Gemini](https://img.shields.io/badge/Powered%20by-Gemini%20Live-8E75B2?style=for-the-badge&logo=google&logoColor=white)](https://ai.google.dev)
[![Sarvam](https://img.shields.io/badge/Indic%20Voice-Sarvam-FF6B00?style=for-the-badge)](https://www.sarvam.ai)
[![Android](https://img.shields.io/badge/Platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://developer.android.com)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)

<br/>

<img src="assets/screenshots/brutus_showcase_1.jpg" width="440" alt="Brutus, the physical robot head"/>
<img src="assets/screenshots/brutus_showcase_2.jpg" width="300" alt="Brutus in action"/>

<br/>
<sub>Talk to it, and its face talks back. Voice, vision, a face full of servos, and 25 plus tools.</sub>

</div>

<br/>

## What this is

Brutus is one project with two halves that need each other.

The first half is an Android app built in Flutter and driven by Google's Gemini Live API. You talk, it listens, it answers out loud, and it can actually do things on your phone: read your mail, search the web, run deep research, look through your camera, read your screen, open apps, send messages, generate images, and more.

The second half is a real robot head. Four servos move the eyes, the eyelids, and the mouth. An LED shows mood. When Brutus speaks, the mouth moves with the voice, the expression shifts to match the tone of what it is saying, and it can nod, wink, laugh, or look around on command. The phone drives all of it over Bluetooth Low Energy.

Two things worth calling out, because they were the hard parts:

* Brutus takes turns like a person. It hears your whole sentence, replies to that, and only then listens again. It does not talk over you, and it does not get set off by the tail end of its own voice coming back through the speaker.
* Brutus answers in whatever language you speak. Say something in Hindi and you get Hindi back. Switch to English mid chat and it switches with you.

<br/>

## At a glance

| Thing | Count |
|:--|:--|
| Feature screens | 15 |
| AI tools it can call | 25 plus |
| Robot animations | 20 (10 macros, 10 tricks) |
| Facial expressions | 6, each with a 0 to 100 intensity dial |
| Servos in the head | 4 (eye left/right, eye up/down, eyelid, mouth) |
| BLE command types | 11 |
| Riverpod providers | 12 |
| Native Kotlin channels | 5 (audio, screen, accessibility, notifications, automation) |
| AI providers supported | Gemini, Sarvam, Groq, Tavily, Hugging Face |
| Architecture | Feature first, Riverpod, GoRouter |

<br/>

## How it works

You speak into the phone. The audio streams to Gemini live over a socket. Gemini streams voice back, plus any tool calls it wants to run. The voice plays through a single native audio track, and at the same time the phone tells the robot how to move its mouth and face. Tools run on the phone and hand their results back to Gemini so the conversation keeps flowing.

```
        You speak
           │
           ▼
     ┌───────────┐        camera / screen frames
     │  Mic PCM  │◄──────────────────────────────┐
     └─────┬─────┘   (muted while Brutus talks)   │
           │                                      │
           ▼                                      │
     ┌──────────────────┐              ┌──────────┴────────┐
     │  Gemini Live API │◄────────────►│  Vision + Screen  │
     │   (web socket)   │              └───────────────────┘
     └───────┬──────────┘
             │
       ┌─────┴───────────────┐
       ▼                     ▼
  ┌──────────┐        ┌───────────────┐
  │  Voice   │        │  Tool calls   │
  │  stream  │        │  (25 plus)    │
  └────┬─────┘        └───────────────┘
       │
   ┌───┴───────────────────────────┐
   ▼                               ▼
┌───────────────┐        ┌──────────────────────┐
│  Speaker      │        │  Robot over BLE      │
│  (AudioTrack) │        │  mouth, eyes, mood,  │
└───────────────┘        │  LED, animations     │
                         └──────────────────────┘
```

<br/>

## Pick your voice and your brain

Brutus does not lock you into one provider. In Settings, under AI Providers, you choose who speaks and who thinks. Handy if you want Indian language voices, or you want to spend less, or you just want it to work with no network.

**Who speaks (text to speech)**

| Engine | What it is | Good for | Needs a key | Works offline |
|:--|:--|:--|:--:|:--:|
| Gemini | Brutus's live native voice (Puck or Aoede) | The most natural, in conversation feel | Yes | No |
| Sarvam Bulbul | 30 plus expressive Indian language voices | Hindi, Tamil, and other Indic speech | Yes | No |
| System | The phone's built in voice | A fallback that always works | No | Yes |

**Who thinks for research and the notes oracle (text model)**

| Engine | What it is | Good for | Needs a key |
|:--|:--|:--|:--:|
| Groq | Fast Llama class model, the default | Quick research and synthesis | Yes |
| Sarvam | Sarvam 30B, tuned for Indic reasoning | Strong understanding of Indian languages | Yes |

Your keys are stored in the phone's encrypted storage. Nothing is hardcoded, and nothing is committed to the repo.

<br/>

## Brutus next to the usual assistants

| Capability | Brutus | Google Assistant | Alexa | ChatGPT app |
|:--|:--:|:--:|:--:|:--:|
| Realtime streamed voice | Yes | Yes | Yes | Yes |
| A physical face that lip syncs | Yes | No | No | No |
| Expression that follows the tone of the reply | Yes | No | No | No |
| 20 named animations on command | Yes | No | No | No |
| Sees your screen and helps with it | Yes | Some | No | Yes |
| Live camera vision | Yes | Some | No | Yes |
| Types and taps for you on the phone | Yes | No | No | No |
| Reads and writes your Gmail | Yes | Yes | No | No |
| Deep research across many sources | Yes | No | No | Yes |
| Answers over your own documents | Yes | No | No | Yes |
| Answers in your language, every turn | Yes | Some | Some | Yes |
| You bring your own keys | Yes | No | No | No |
| Open source, yours to host | Yes | No | No | No |

<br/>

## Efficiency and where your data lives

A lot of the work happens on the phone itself, which keeps it fast and keeps your data close.

```
Runs on your phone, no cloud round trip:
  Screen text reading (OCR)     ██████████
  Face tracking for the eyes    ██████████
  Chat history and notes        ██████████
  API keys (encrypted)          ██████████
  App control and automation    ██████████

Uses the cloud when it has to:
  Voice and reasoning           ██████████   Gemini
  Indic voice and chat          ██████████   Sarvam
  Web and deep research         ██████████   Tavily, Groq
  Image generation              ██████████   Hugging Face
```

A few design choices that keep it light on its feet:

* One audio track stays open for the whole session, so there is no stop and start churn between voice chunks and no fight over audio focus with the mic.
* The mic stays open the whole time and chunks are simply dropped while Brutus talks, so there is no cost to restart recording every turn.
* Playback completion is measured from the real length of the audio, not from when data stopped arriving, so the mic reopens the instant Brutus is genuinely done and not a moment before.
* Camera and screen frames pause while audio is flowing, so a big image never chokes the voice socket.
* The chat history is capped and the Gemini session compresses its own context, so long conversations do not balloon memory or drop the connection.

<br/>

## App features

### Voice and conversation

| Feature | What it does |
|:--|:--|
| Realtime voice | Continuous mic streaming to Gemini Live over a socket |
| Takes turns | Hears your whole sentence, replies, then listens again |
| Speaks your language | Mirrors your language and script on every turn |
| No self echo | Never mistakes the tail of its own reply for your input |
| Live transcripts | See both sides of the conversation as it happens |
| Text fallback | Drops to text mode cleanly if the live link goes down |
| Chat history | Last 200 messages saved on the phone |
| Speak for me | Type something and Brutus reads it out in its own voice |

### Vision and screen

| Feature | What it does |
|:--|:--|
| Camera vision | Point the camera and Brutus sees and understands what is there |
| Screen share | Share your screen and Brutus helps with what is on it |
| Robot eyes see too | The optional ESP32 camera streams the robot's view into Gemini |
| Bandwidth modes | Standard and low data, so it works on a weak connection |
| Smart frame skip | Frames pause during audio to keep voice smooth |

### Eye tracking

Point the phone's back camera at the room and the face detector runs on the phone. Brutus maps whoever it sees to the eye servos, so the robot's eyes follow you around. No face in view and the eyes recenter on their own.

### Tools it can actually use

<table>
<tr>
<td valign="top">

**Talk to people**
<br/>Gmail read and compose
<br/>WhatsApp send
<br/>SMS composer
<br/>Phone calls
<br/>Contact lookup

</td>
<td valign="top">

**Find things out**
<br/>Web search (Tavily)
<br/>Deep research
<br/>Weather
<br/>Stock prices
<br/>Read text with the camera

</td>
<td valign="top">

**Get things done**
<br/>Notes
<br/>Oracle over your docs
<br/>Image generation
<br/>Maps
<br/>Timers

</td>
<td valign="top">

**Run the phone**
<br/>Open any app
<br/>Flashlight
<br/>Ringer mode
<br/>Type and tap for you
<br/>Read the screen
<br/>Read notifications
<br/>Settings panels

</td>
</tr>
</table>

### Look and feel

* Material 3, warm indigo palette
* An animated particle sphere that pulses with Brutus's voice
* Frosted glass navigation and smooth page transitions
* 15 screens: Home, Chat, Robot Control, Tools, Settings, Email, Notes, Research, Oracle, Gallery, Maps, Stocks, Weather, Search, Automation

<br/>

## The robot head

The face is four micro servos, an LED, a sound sensor, and an HM 10 Bluetooth module, all run by an Arduino Uno.

### Parts list

| Part | Qty | Pin | Job |
|:--|:--:|:--:|:--|
| Arduino Uno (or Nano) | 1 | | The brain of the head |
| HM 10 BLE module | 1 | D10 (RX), D11 (TX) | Talks to the phone |
| SG90 servo, eye left/right | 1 | D3 | Eyes side to side |
| SG90 servo, eye up/down | 1 | D5 | Eyes up and down |
| SG90 servo, eyelid | 1 | D6 | Blink and eyelids |
| SG90 servo, mouth | 1 | D9 | Jaw and lip sync |
| LED | 1 | D8 | Status and mood |
| Sound sensor | 1 | A0 | Idle mode lip flap |
| 5V supply, 2A or more | 1 | | Power for the servos |

Rough cost to build: about 15 to 25 US dollars.

### Wiring

```
                  ┌────────────────────────┐
                  │       Arduino Uno      │
                  │                        │
  HM10 TXD ─────► │ D10  (soft serial RX)  │
  HM10 RXD ◄───── │ D11  (soft serial TX)  │  use a voltage divider here
                  │                        │
  Eye L/R  ◄───── │ D3   (PWM)             │
  Eye U/D  ◄───── │ D5   (PWM)             │
  Eyelid   ◄───── │ D6   (PWM)             │
  Mouth    ◄───── │ D9   (PWM)             │
                  │                        │
  LED      ◄───── │ D8   (digital)         │
  Sound    ─────► │ A0   (analog)          │
                  │                        │
  5V ext   ─────► │ 5V                     │
  GND ──────────── │ GND  (shared ground)  │
                  └────────────────────────┘
```

> One thing to watch: the HM 10 RXD pin runs at 3.3V logic. Put a divider (a 1k and a 2k resistor) between Arduino D11 and the HM 10 RXD. The other direction, TXD into D10, is fine as is.

### The BLE protocol

The phone talks to the head over a BLE serial characteristic (`0000FFE1`). Commands are plain text, one per line.

| Command | Meaning | Example |
|:--|:--|:--|
| `E<n>` | Set expression 0 to 5 | `E0` for happy |
| `E<n>,<i>` | Expression with intensity 0 to 100 | `E1,50` |
| `M<a>` | Mouth angle 0 to 180 for lip sync | `M140` |
| `L<lr>,<ud>` | Look at, both eye axes | `L60,70` |
| `B` | Blink once | `B` |
| `I<0/1>` | Idle behavior on or off | `I1` |
| `S<0/1>` | Freeze, stop all autonomous motion | `S1` |
| `A<n>` | Play animation macro 0 to 9 | `A3` |
| `W<n>` | Play movement trick 0 to 9 | `W5` |
| `C<n>` | LED pattern, 0 off to 3 fast | `C2` |
| `H` | Heartbeat, replies `OK` | `H` |

### Expressions

| Index | Expression | Look |
|:--:|:--|:--|
| 0 | Happy | Relaxed eyes, small smile |
| 1 | Angry | Squinted eyes, tight jaw |
| 2 | Sad | Droopy eyes, gaze away, frown |
| 3 | Thinking | Eyes up and to the left, neutral mouth |
| 4 | Sleepy | Eyes almost closed |
| 5 | Surprised | Eyes wide, mouth open |

Every expression scales from 0 (neutral) to 100 (full) with the intensity value.

### Animations and tricks

Twenty ready made sequences run on the Arduino as non blocking keyframes, so the head stays responsive to new commands while it moves.

| Macros (A) | Tricks (W) |
|:--|:--|
| Nod, Shake, Look around | Crazy eyes, Chatter, Slow scan |
| Wink, Yawn, Laugh | Peekaboo, Double blink, Jaw drop |
| Eye roll, Mouth cycle | Drowsy, Side eye |
| Eye cycle, Wiggle | Happy bounce, Confused |

### It reacts on its own

When it is connected and auto drive is on, the head follows the conversation without being told.

| State | Expression | LED | Head |
|:--|:--|:--|:--|
| Listening | Happy | Solid | Eyes centered, attentive |
| Thinking | Thinking | Pulse | Eyes drift up |
| Connecting | Thinking | Fast blink | Waiting on the API |
| Speaking | Matches the tone | Solid | Mouth moves with the voice |
| Idle | Thinking | Pulse | Eyes centered |
| Error | Sad | Fast blink | Blink, mouth closed |

While Brutus talks, it reads emotion cues out of Gemini's reply and switches the expression and LED to match, so an angry sentence looks angry and a happy one looks happy.

### Say it out loud

Gemini can trigger the head straight from speech.

> "Brutus, nod your head" plays the nod.
> "Wink at them" plays the wink.
> "Do crazy eyes" plays the crazy eyes trick.
> "Act confused" plays the confused trick.

<br/>

## Setup

You need Flutter installed, an Android phone on Android 8 or newer, and a Gemini API key from [Google AI Studio](https://aistudio.google.com). That is enough to run the app. The robot is optional and comes later.

### Run the app in three steps

```bash
git clone https://github.com/Aditya060806/Brutus-app.git
cd Brutus-app/brutus_app
flutter pub get
flutter run --release
```

### Add your key

Open the app, go to Settings, then API Keys, and paste your Gemini key. That is it. Keys go into the phone's encrypted storage. The other keys (Groq, Tavily, Hugging Face, Sarvam) are optional and only needed for the features that use them, and you add them the same way whenever you want.

Prefer to keep keys in a file while developing? Copy the template and fill it in. This file is git ignored, so your keys never get committed.

```bash
cp lib/core/constants/app_config.example.dart lib/core/constants/app_config.dart
```

### Add the robot (optional)

1. Open `arduino/brutus_face_robot/brutus_face_robot.ino` in the Arduino IDE.
2. Pick your board and upload.
3. Power the servos from an external 5V 2A supply. USB alone cannot drive four servos.
4. In the app, open Robot Control, scan, and tap your HM 10 to connect.

> The HM 10 usually shows up as `HMSoft`, `BT05`, or `MLT-BT05`. There is no pairing step. It is BLE, not classic Bluetooth.

<br/>

## Project layout

```
brutus_app/
├── lib/
│   ├── core/         constants, router, theme, shared widgets
│   ├── data/
│   │   ├── services/ Gemini voice, Sarvam, audio, vision, BLE, and more
│   │   └── tools/    Tavily, weather, stocks
│   ├── features/     15 feature modules
│   └── providers/    Riverpod state notifiers
├── arduino/
│   └── brutus_face_robot/   robot firmware
├── android/
│   └── app/src/main/kotlin/ native audio, screen capture, accessibility
└── assets/
    ├── screenshots/  the photos in this README
    ├── images/
    └── animations/
```

### Under the hood

| Layer | Tech |
|:--|:--|
| Framework | Flutter 3, Dart 3 |
| State | Riverpod 2 |
| Navigation | GoRouter |
| Networking | Dio for REST, `dart:io` sockets for Gemini Live |
| Storage | Hive for data, encrypted storage for keys |
| Audio out | Native Kotlin AudioTrack at 24 kHz |
| Audio in | `record` for 16 kHz PCM streaming |
| Vision | `camera` frames into Gemini multimodal |
| Robot | `flutter_blue_plus` into the HM 10, then Arduino |
| On device ML | ML Kit for OCR and face detection |

<br/>

## The build, up close

<div align="center">
<table>
<tr>
<td align="center"><img src="assets/screenshots/robot-build-1.jpg" width="240" alt="Servo layout"/><br/><sub>Servo layout</sub></td>
<td align="center"><img src="assets/screenshots/robot-build-2.jpg" width="240" alt="Wiring"/><br/><sub>Wiring inside the head</sub></td>
<td align="center"><img src="assets/screenshots/robot-build-3.jpg" width="240" alt="Assembly"/><br/><sub>Assembled</sub></td>
</tr>
<tr>
<td align="center"><img src="assets/screenshots/robot-face.jpg" width="240" alt="Face close view"/><br/><sub>The face</sub></td>
<td align="center"><img src="assets/screenshots/app-screenshot-1.png" width="240" alt="App"/><br/><sub>The app</sub></td>
<td align="center"><img src="assets/screenshots/app-screenshot-2.jpg" width="240" alt="App in use"/><br/><sub>The app in use</sub></td>
</tr>
</table>
</div>

<br/>

## Permissions and why

| Permission | Why it is needed |
|:--|:--|
| Record audio | Stream your voice to Gemini |
| Camera | Vision and eye tracking |
| Internet | The live socket and every API call |
| Bluetooth scan and connect | Talk to the robot head |
| Foreground service | Keep screen capture alive |
| Media projection | Screen share with Gemini |
| Accessibility service | Type, tap, and read the screen for you |
| Notification listener | Read your notifications when asked |
| Read contacts | Look up people for calls and messages |

<br/>

## What is next

* A phone number you can call, so Brutus picks up and talks in realtime
* Desktop bridge
* iOS
* A wake word, "Hey Brutus"
* An on device fallback model for no network
* An RGB LED strip for real color moods
* A neck servo so the whole head can track you

<br/>

## Contributing

Pull requests are welcome. Fork it, make a branch, copy `app_config.example.dart` to `app_config.dart` and add your own keys, then open a PR.

<br/>

## Author

**Aditya Pandey**

* GitHub: [@Aditya060806](https://github.com/Aditya060806)
* Email: aditya060806@gmail.com

## License

MIT. See [LICENSE](LICENSE).

<div align="center">
<br/>
<sub>Built with Flutter, Gemini, Sarvam, and a lot of servos.</sub>
</div>
