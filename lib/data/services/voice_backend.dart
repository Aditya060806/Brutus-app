/// A swappable "brain" that Brutus's [ChatNotifier] drives for a live
/// conversation. Both the cloud brain ([GeminiVoiceService], Gemini Live over
/// the internet) and the on-device brain ([EdgeBrainService], the EdgeBrain hub
/// on localhost) implement this exact surface, so the chat, robot, emotion, and
/// playback layers never need to know which one is running.
///
/// ## The event contract (the [messages] stream)
///
/// Every backend MUST emit the same map shapes that [ChatNotifier] already
/// understands. Keeping this contract identical is what lets the EdgeBrain hub
/// stand in for Gemini Live with no change to the app or the robot layer:
///
///   * `{'setupComplete': true}` once the session is ready.
///   * `{'inputTranscription': String}` for what the user said (streamed).
///   * `{'outputTranscription': String}` for what Brutus is saying (streamed).
///     The FIRST such chunk may carry a leading `[EMOTION:xxx]` tag, exactly as
///     Gemini emits it, so the robot/emotion layer survives untouched.
///   * `{'serverContent': {'modelTurn': {'parts': [{'inlineData': {'data':
///     base64Pcm24k}}]}}}` for a chunk of 24 kHz mono PCM voice.
///   * `{'serverContent': {'turnComplete': true}}` when Brutus finishes a turn.
///   * `{'serverContent': {'interrupted': true}}` on barge-in.
///   * `{'toolCall': {'functionCalls': [{'id','name','args'}]}}` to run a tool.
///   * `{'type': 'reconnecting' | 'reconnected' | 'error' | 'disconnected',
///     'message'?: String}` for connection lifecycle.
///
/// Audio in is always 16 kHz mono PCM (base64) via [sendAudioChunk]; audio out
/// is always 24 kHz mono PCM (base64) inside `inlineData`. The EdgeBrain hub is
/// responsible for wrapping its text models with on-device speech-to-text and
/// text-to-speech so it can honour this PCM-in / PCM-out contract.
abstract interface class VoiceBackend {
  /// Broadcast stream of protocol events (shapes documented above).
  Stream<Map<String, dynamic>> get messages;

  /// True once a session is live (socket open, setup complete).
  bool get isConnected;

  /// True when the backend streams native audio (as opposed to a REST/text
  /// only fallback). Drives whether [ChatNotifier] starts the continuous mic.
  bool get isLiveMode;

  /// True while the mic is muted (audio chunks are dropped, session stays up).
  bool get isMicMuted;

  /// Open a session. Should push `{'setupComplete': true}` (or an error event)
  /// onto [messages]. Safe to await; must not throw for expected failures
  /// (missing key, hub not running) and instead surface an error event.
  Future<void> connect();

  /// Close the session for good (user powered off). No auto reconnect after.
  void disconnect();

  /// Drop the backend and release its resources.
  void dispose();

  /// Mute or unmute the mic without tearing down the session. While muted,
  /// [sendAudioChunk] payloads are silently dropped.
  void setMute(bool muted);

  /// Feed one chunk of 16 kHz mono PCM (base64). Ignored while muted / offline.
  void sendAudioChunk(String base64Audio);

  /// Feed one JPEG frame (base64) for vision. Returns true if it was accepted.
  bool sendVideoFrame(String base64Jpeg);

  /// Send a text turn (keyboard input, or the REST/text path).
  void sendText(String text);

  /// Return a tool/function result to the brain so the turn can continue.
  void sendToolResponse(
    String functionCallId,
    String functionName,
    dynamic result,
  );

  /// Hint that Brutus just produced an audio chunk. Used by the cloud backend
  /// for echo bookkeeping; the on-device backend can treat it as a no-op.
  void notifyAiAudioActive();
}
