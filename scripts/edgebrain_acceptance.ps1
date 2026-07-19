<#
  EdgeBrain standalone acceptance test.

  Proves Brutus's brain runs entirely on the phone. The bar:
    1. Phone is offline except WiFi (radios off, WiFi on so adb over network or
       a USB cable still reaches it, but no cellular / no internet egress).
    2. The EdgeBrain foreground service is running and its models are loaded on
       the Hexagon NPU.
    3. curl to the hub on localhost returns tokens generated on device.
    4. Then you open the Flutter app in Edge brain mode and the robot nods.

  The hub exposes:
    HTTP  http://127.0.0.1:<HttpPort>   /health  /chat  /vlm  /intent
    WS    ws://127.0.0.1:<WsPort>/voice  the PCM voice channel the app uses

  Usage:
    powershell -ExecutionPolicy Bypass -File scripts/edgebrain_acceptance.ps1
    powershell ... -HttpPort 8080 -WsPort 8765 -SetAirplane
#>

param(
  [int]$HttpPort = 8080,
  [int]$WsPort   = 8765,
  [switch]$SetAirplane
)

$ErrorActionPreference = "Stop"
function Ok($m)   { Write-Host "  PASS  $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "  FAIL  $m" -ForegroundColor Red }
function Info($m) { Write-Host "  ..    $m" -ForegroundColor Gray }
function Head($m) { Write-Host "`n== $m ==" -ForegroundColor Cyan }

# 1. adb + a device
Head "Device"
try { $null = adb version } catch { Bad "adb not on PATH. Install platform-tools."; exit 1 }
$devices = (adb devices) -split "`n" | Where-Object { $_ -match "\tdevice$" }
if (-not $devices) { Bad "No device. Plug in the phone and enable USB debugging."; exit 1 }
Ok "Device connected"

# 2. Offline except WiFi (optional, radios vary by phone)
Head "Network"
if ($SetAirplane) {
  Info "Turning airplane mode on, then WiFi back on"
  # Modern, no root needed on most devices:
  adb shell cmd connectivity airplane-mode enable  2>$null
  Start-Sleep -Seconds 2
  adb shell svc wifi enable 2>$null
  Start-Sleep -Seconds 3
}
$airplane = (adb shell settings get global airplane_mode_on).Trim()
$wifi     = (adb shell settings get global wifi_on).Trim()
Info "airplane_mode_on=$airplane  wifi_on=$wifi"
if ($airplane -eq "1") { Ok "Airplane mode on (cellular off)" } else { Info "Airplane mode off. For the true offline demo, run with -SetAirplane." }

# 3. Reach the hub. Forward the device port to the host so we can use curl.exe.
Head "Hub reachability"
adb forward tcp:$HttpPort tcp:$HttpPort | Out-Null
Info "adb forward tcp:$HttpPort -> device $HttpPort"
$base = "http://127.0.0.1:$HttpPort"

try {
  $health = curl.exe -s --max-time 5 "$base/health"
  if ($health) { Ok "/health -> $health" } else { Bad "/health empty. Is the EdgeBrain service started?"; exit 1 }
} catch { Bad "Cannot reach $base/health. Start the EdgeBrain foreground service."; exit 1 }

# 4. /chat returns on-device tokens
Head "Chat on the NPU"
$chatBody = '{"prompt":"In one short sentence, who are you?","max_tokens":64}'
$chat = curl.exe -s --max-time 60 -X POST "$base/chat" -H "Content-Type: application/json" -d $chatBody
if ($chat -and $chat.Length -gt 0) {
  Ok "/chat returned tokens:"
  Write-Host "        $chat" -ForegroundColor White
  Info "Confirm in the service log that the backend is qnn / npu, not cpu."
} else { Bad "/chat returned nothing." }

# 5. /intent (function calling)
Head "Intent"
$intentBody = '{"text":"nod your head twice"}'
$intent = curl.exe -s --max-time 30 -X POST "$base/intent" -H "Content-Type: application/json" -d $intentBody
if ($intent) { Ok "/intent -> $intent" } else { Info "/intent returned nothing (wire this endpoint if you have not yet)." }

# 6. /vlm needs an image; just probe that it exists
Head "Vision"
$vlm = curl.exe -s --max-time 10 -o NUL -w "%{http_code}" "$base/vlm"
Info "/vlm probe HTTP $vlm (send a base64 image to actually test FastVLM)"

# 7. The one-liner from the phone itself, for the demo
Head "On-device one-liner (what the judges can watch)"
Write-Host '  adb shell curl -s -X POST http://127.0.0.1:'$HttpPort'/chat -H "Content-Type: application/json" -d "{\"prompt\":\"hello\"}"' -ForegroundColor Yellow

Head "Next"
Write-Host "  Open the app, Settings, AI Providers, set Brain to On-device EdgeBrain."
Write-Host "  Power Brutus on. Say 'nod your head'. The robot should nod with no internet."
Write-Host ""
