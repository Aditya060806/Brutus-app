import 'dart:developer' as dev;

import 'package:brutus_app/data/services/api_keys.dart';
import 'package:brutus_app/data/services/network_guard.dart';
import 'package:brutus_app/data/tools/stock_api.dart';
import 'package:brutus_app/data/tools/tavily_client.dart';
import 'package:brutus_app/data/tools/weather_api.dart';
import 'package:brutus_app/providers/robot_provider.dart';

/// Brutus Mobile — Tool Dispatcher
/// Routes Gemini Live function calls to local implementations.
/// Tool names + argument keys mirror the desktop `Brutus-voice-ai.ts` reference.
class ToolDispatcher {
  static final ToolDispatcher instance = ToolDispatcher._();
  ToolDispatcher._();

  // Lazy-instantiated clients shared across tool calls. Created on first use
  // because creating a Dio instance is light but we still skip it for users
  // who never invoke web/research tools.
  TavilyClient? _tavily;
  TavilyClient _tavilyClient() => _tavily ??= TavilyClient();

  Future<Map<String, dynamic>> Function(String title, String content)? _noteCreator;
  Future<List<Map<String, dynamic>>> Function()? _noteReader;

  /// Deep-research runner. Registered by [ChatNotifier] once the service is
  /// constructed; left null when the dispatcher is instantiated in tests.
  Future<Map<String, dynamic>> Function(String query)? _deepResearchRunner;

  /// Oracle runner. Registered by [ChatNotifier] in the same way.
  Future<Map<String, dynamic>> Function(String question)? _oracleRunner;

  /// Gmail runners.
  Future<Map<String, dynamic>> Function({int max})? _readEmailsRunner;
  Future<Map<String, dynamic>> Function({
    required String to,
    required String subject,
    required String body,
  })? _sendEmailRunner;

  /// Gallery runner.
  Future<Map<String, dynamic>> Function(String prompt)? _generateImageRunner;

  /// Maps runner.
  Future<Map<String, dynamic>> Function(String query)? _findPlaceRunner;

  // ── Phase 4: Phone Automation runners ──────────────────────────────────
  Future<Map<String, dynamic>> Function(String name)? _openAppRunner;
  Future<Map<String, dynamic>> Function(bool on)? _toggleFlashlightRunner;
  Future<Map<String, dynamic>> Function(String panel)? _openSettingsPanelRunner;
  Future<Map<String, dynamic>> Function(String mode)? _setRingerModeRunner;
  Future<Map<String, dynamic>> Function({
    required String phone,
    required String message,
  })? _sendWhatsAppRunner;
  Future<Map<String, dynamic>> Function(String query)? _playSpotifyRunner;
  Future<Map<String, dynamic>> Function()? _readNotificationsRunner;

  // ── Phase 4 enhancement: ghost-typing + OCR ──────────────────────────
  Future<Map<String, dynamic>> Function(String text)? _ghostTypeRunner;
  Future<Map<String, dynamic>> Function(String query)? _clickByTextRunner;
  Future<Map<String, dynamic>> Function()? _readScreenTextRunner;
  Future<Map<String, dynamic>> Function()? _ocrRunner;
  Future<Map<String, dynamic>> Function(String action)? _globalActionRunner;

  // ── Phase 4 enhancement: contacts + SMS + dialer ─────────────────────
  Future<Map<String, dynamic>> Function({
    required String to,
    required String body,
  })? _sendSmsRunner;
  Future<Map<String, dynamic>> Function(String to)? _callRunner;
  Future<Map<String, dynamic>> Function(String name)? _findContactRunner;

  // ── System timer runner ──────────────────────────────────────────
  Future<Map<String, dynamic>> Function(int minutes)? _setTimerRunner;

  // ── Phase 5: Robot animation/trick runners ───────────────────────
  Future<Map<String, dynamic>> Function(int index)? _playAnimationRunner;
  Future<Map<String, dynamic>> Function(int index)? _playMovementTrickRunner;

  void registerSetTimerRunner(
    Future<Map<String, dynamic>> Function(int minutes) fn,
  ) {
    _setTimerRunner = fn;
  }

  void registerNoteCreator(
    Future<Map<String, dynamic>> Function(String title, String content) fn,
  ) {
    _noteCreator = fn;
  }

  void registerNoteReader(Future<List<Map<String, dynamic>>> Function() fn) {
    _noteReader = fn;
  }

  void registerDeepResearchRunner(
    Future<Map<String, dynamic>> Function(String query) fn,
  ) {
    _deepResearchRunner = fn;
  }

  void registerOracleRunner(
    Future<Map<String, dynamic>> Function(String question) fn,
  ) {
    _oracleRunner = fn;
  }

  void registerReadEmailsRunner(
    Future<Map<String, dynamic>> Function({int max}) fn,
  ) {
    _readEmailsRunner = fn;
  }

  void registerSendEmailRunner(
    Future<Map<String, dynamic>> Function({
      required String to,
      required String subject,
      required String body,
    }) fn,
  ) {
    _sendEmailRunner = fn;
  }

  void registerGenerateImageRunner(
    Future<Map<String, dynamic>> Function(String prompt) fn,
  ) {
    _generateImageRunner = fn;
  }

  void registerFindPlaceRunner(
    Future<Map<String, dynamic>> Function(String query) fn,
  ) {
    _findPlaceRunner = fn;
  }

  void registerOpenAppRunner(
    Future<Map<String, dynamic>> Function(String name) fn,
  ) {
    _openAppRunner = fn;
  }

  void registerToggleFlashlightRunner(
    Future<Map<String, dynamic>> Function(bool on) fn,
  ) {
    _toggleFlashlightRunner = fn;
  }

  void registerOpenSettingsPanelRunner(
    Future<Map<String, dynamic>> Function(String panel) fn,
  ) {
    _openSettingsPanelRunner = fn;
  }

  void registerSetRingerModeRunner(
    Future<Map<String, dynamic>> Function(String mode) fn,
  ) {
    _setRingerModeRunner = fn;
  }

  void registerSendWhatsAppRunner(
    Future<Map<String, dynamic>> Function({
      required String phone,
      required String message,
    }) fn,
  ) {
    _sendWhatsAppRunner = fn;
  }

  void registerPlaySpotifyRunner(
    Future<Map<String, dynamic>> Function(String query) fn,
  ) {
    _playSpotifyRunner = fn;
  }

  void registerReadNotificationsRunner(
    Future<Map<String, dynamic>> Function() fn,
  ) {
    _readNotificationsRunner = fn;
  }

  void registerGhostTypeRunner(
    Future<Map<String, dynamic>> Function(String text) fn,
  ) {
    _ghostTypeRunner = fn;
  }

  void registerClickByTextRunner(
    Future<Map<String, dynamic>> Function(String query) fn,
  ) {
    _clickByTextRunner = fn;
  }

  void registerReadScreenTextRunner(
    Future<Map<String, dynamic>> Function() fn,
  ) {
    _readScreenTextRunner = fn;
  }

  void registerOcrRunner(Future<Map<String, dynamic>> Function() fn) {
    _ocrRunner = fn;
  }

  void registerGlobalActionRunner(
    Future<Map<String, dynamic>> Function(String action) fn,
  ) {
    _globalActionRunner = fn;
  }

  void registerSendSmsRunner(
    Future<Map<String, dynamic>> Function({
      required String to,
      required String body,
    }) fn,
  ) {
    _sendSmsRunner = fn;
  }

  void registerCallRunner(
    Future<Map<String, dynamic>> Function(String to) fn,
  ) {
    _callRunner = fn;
  }

  void registerFindContactRunner(
    Future<Map<String, dynamic>> Function(String name) fn,
  ) {
    _findContactRunner = fn;
  }

  void registerPlayAnimationRunner(
    Future<Map<String, dynamic>> Function(int index) fn,
  ) {
    _playAnimationRunner = fn;
  }

  void registerPlayMovementTrickRunner(
    Future<Map<String, dynamic>> Function(int index) fn,
  ) {
    _playMovementTrickRunner = fn;
  }

  void _log(String msg) => dev.log('[Tools] $msg', name: 'BrutusAI');

  /// Dispatch a tool call from Gemini and return a result map.
  Future<Map<String, dynamic>> dispatch(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (toolName) {
        case 'get_weather':
          // Desktop arg: `location`. Old mobile arg: `city`. Accept both.
          final loc = (args['location'] ?? args['city']) as String? ?? 'Delhi';
          return await WeatherApi.fetchWeather(loc);

        case 'get_stock_price':
          final ticker = args['ticker'] as String? ?? 'AAPL';
          final result = await StockApi.fetchStock(ticker);
          if (result.containsKey('error')) return result;
          return {
            'symbol': result['symbol'],
            'price': '\$${(result['currentPrice'] as double).toStringAsFixed(2)}',
            'change':
                '${(result['isPositive'] as bool) ? '+' : ''}${(result['percentChange'] as double).toStringAsFixed(2)}%',
            'currency': result['currency'],
          };

        case 'compare_stocks':
          final t1 = args['ticker1'] as String? ?? 'AAPL';
          final t2 = args['ticker2'] as String? ?? 'MSFT';
          return await StockApi.compareStocks(t1, t2);

        case 'get_time':
          final now = DateTime.now();
          return {
            'time':
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
            'date': '${now.day}/${now.month}/${now.year}',
            'iso': now.toIso8601String(),
          };

        case 'save_note':
        case 'create_note':
          final title = args['title'] as String? ?? 'Note';
          final content = args['content'] as String? ?? '';
          if (_noteCreator != null) {
            return await _noteCreator!(title, content);
          }
          return {'success': true, 'title': title, 'message': 'Note saved'};

        case 'read_notes':
          if (_noteReader != null) {
            final notes = await _noteReader!();
            return {'count': notes.length, 'notes': notes};
          }
          return {'count': 0, 'notes': <Map<String, dynamic>>[]};

        case 'read_emails':
          final max = (args['max_results'] as num?)?.toInt() ?? 5;
          if (_readEmailsRunner == null) {
            return {
              'count': 0,
              'note':
                  'Email runner not initialised. Open Tools → Email and sign in.',
            };
          }
          return await _readEmailsRunner!(max: max);

        case 'send_email':
          final to = (args['to'] as String? ?? '').trim();
          final subject = (args['subject'] as String? ?? '').trim();
          final body = (args['body'] as String? ?? '').trim();
          if (to.isEmpty || subject.isEmpty || body.isEmpty) {
            return {
              'success': false,
              'error':
                  'send_email needs `to`, `subject`, and `body` — all non-empty.',
            };
          }
          if (_sendEmailRunner == null) {
            return {
              'success': false,
              'error':
                  'Email runner not initialised. Open Tools → Email and sign in first.',
            };
          }
          return await _sendEmailRunner!(to: to, subject: subject, body: body);

        case 'generate_image':
          final prompt = (args['prompt'] as String? ?? '').trim();
          if (prompt.isEmpty) {
            return {'error': 'generate_image needs a non-empty `prompt`.'};
          }
          if (_generateImageRunner == null) {
            return {'error': 'Gallery runner not initialised.'};
          }
          return await _generateImageRunner!(prompt);

        case 'find_place':
          final query = (args['query'] as String? ?? '').trim();
          if (query.isEmpty) {
            return {'error': 'find_place needs a non-empty `query`.'};
          }
          if (_findPlaceRunner == null) {
            return {'error': 'Maps runner not initialised.'};
          }
          return await _findPlaceRunner!(query);

        case 'open_app':
          final appName = (args['app_name'] as String? ??
                  args['appName'] as String? ??
                  args['name'] as String? ??
                  '')
              .trim();
          if (appName.isEmpty) {
            return {'error': 'open_app needs a non-empty `app_name`.'};
          }
          if (_openAppRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _openAppRunner!(appName);

        case 'toggle_flashlight':
          // Accept multiple arg names — Gemini sometimes sends `state` instead.
          final raw = args['on'] ?? args['state'] ?? args['value'];
          final on = switch (raw) {
            bool b => b,
            String s => s.toLowerCase() == 'on' || s.toLowerCase() == 'true',
            _ => true,
          };
          if (_toggleFlashlightRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _toggleFlashlightRunner!(on);

        case 'open_settings_panel':
          final panel = (args['panel'] as String? ?? '').trim();
          if (panel.isEmpty) {
            return {
              'error':
                  'open_settings_panel needs `panel` (wifi, bluetooth, internet, location, airplane, volume, nfc, data).',
            };
          }
          if (_openSettingsPanelRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _openSettingsPanelRunner!(panel);

        case 'set_ringer_mode':
          final mode = (args['mode'] as String? ?? '').trim();
          if (mode.isEmpty) {
            return {
              'error': 'set_ringer_mode needs `mode` (silent, vibrate, normal).',
            };
          }
          if (_setRingerModeRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _setRingerModeRunner!(mode);

        case 'send_whatsapp':
          // Accept either `phone` (digits) or `to`/`name`/`contact` (a saved
          // contact name we'll look up in the address book).
          final recipient = (args['phone'] as String? ??
                  args['number'] as String? ??
                  args['to'] as String? ??
                  args['name'] as String? ??
                  args['contact'] as String? ??
                  '')
              .trim();
          final message = (args['message'] as String? ??
                  args['text'] as String? ??
                  args['body'] as String? ??
                  '')
              .trim();
          if (recipient.isEmpty || message.isEmpty) {
            return {
              'error':
                  'send_whatsapp needs `to` (contact name or phone with country code) and `message`.',
            };
          }
          if (_sendWhatsAppRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _sendWhatsAppRunner!(phone: recipient, message: message);

        case 'play_spotify':
          final query = ((args['query'] ?? args['song'] ?? args['artist']) as String? ?? '').trim();
          if (query.isEmpty) {
            return {'error': 'play_spotify needs `query`.'};
          }
          if (_playSpotifyRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _playSpotifyRunner!(query);

        case 'read_notifications':
          if (_readNotificationsRunner == null) {
            return {
              'count': 0,
              'notifications': const <Map<String, dynamic>>[],
              'note': 'Automation runner not initialised.',
            };
          }
          return await _readNotificationsRunner!();

        case 'ghost_type':
        case 'type_text':
          final text = (args['text'] as String? ?? '').trim();
          if (text.isEmpty) {
            return {'error': 'ghost_type needs `text`.'};
          }
          if (_ghostTypeRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _ghostTypeRunner!(text);

        case 'tap_text':
        case 'click_button':
          final query = (args['query'] as String? ??
                  args['text'] as String? ??
                  args['label'] as String? ??
                  '')
              .trim();
          if (query.isEmpty) {
            return {'error': 'tap_text needs `query` or `label`.'};
          }
          if (_clickByTextRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _clickByTextRunner!(query);

        case 'read_screen':
          if (_readScreenTextRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _readScreenTextRunner!();

        case 'ocr':
        case 'read_with_camera':
          if (_ocrRunner == null) {
            return {
              'success': false,
              'message': 'OCR runner not initialised.',
            };
          }
          return await _ocrRunner!();

        case 'global_action':
        case 'press_back':
        case 'press_home':
          // Allow shorthand: tool name itself encodes the action.
          var action = (args['action'] as String? ?? '').trim();
          if (action.isEmpty) {
            action = switch (toolName) {
              'press_back' => 'back',
              'press_home' => 'home',
              _ => '',
            };
          }
          if (action.isEmpty) {
            return {'error': 'global_action needs `action`.'};
          }
          if (_globalActionRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _globalActionRunner!(action);

        case 'send_sms':
        case 'text_message':
          final to = (args['to'] as String? ??
                  args['phone'] as String? ??
                  args['name'] as String? ??
                  args['contact'] as String? ??
                  '')
              .trim();
          final body = (args['body'] as String? ??
                  args['message'] as String? ??
                  args['text'] as String? ??
                  '')
              .trim();
          if (to.isEmpty || body.isEmpty) {
            return {
              'error': 'send_sms needs `to` and `body` / `message`.',
            };
          }
          if (_sendSmsRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _sendSmsRunner!(to: to, body: body);

        case 'call':
        case 'make_call':
          final to = (args['to'] as String? ??
                  args['phone'] as String? ??
                  args['name'] as String? ??
                  args['contact'] as String? ??
                  '')
              .trim();
          if (to.isEmpty) {
            return {'error': 'call needs `to` (contact name or number).'};
          }
          if (_callRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _callRunner!(to);

        case 'find_contact':
        case 'lookup_contact':
          final name = (args['name'] as String? ??
                  args['query'] as String? ??
                  '')
              .trim();
          if (name.isEmpty) {
            return {'error': 'find_contact needs `name`.'};
          }
          if (_findContactRunner == null) {
            return {
              'success': false,
              'message': 'Automation runner not initialised.',
            };
          }
          return await _findContactRunner!(name);

        case 'web_search':
        case 'google_search':
          final query = (args['query'] as String? ?? '').trim();
          if (query.isEmpty) {
            return {'error': 'web_search needs a non-empty `query` argument.'};
          }
          try {
            final result = await _tavilyClient().search(
              query,
              includeAnswer: true,
              maxResults: 5,
            );
            return {
              'query': result.query,
              if (result.answer != null) 'answer': result.answer,
              'results': result.results
                  .map((s) => {
                        'title': s.title,
                        'url': s.url,
                        'snippet': s.content,
                        'score': s.score,
                      })
                  .toList(),
              'note':
                  'Cite sources by domain when reading aloud (e.g., "according to nytimes.com").',
            };
          } on MissingApiKeyException catch (e) {
            return {'error': e.toString()};
          } on OfflineException catch (e) {
            return {'error': e.toString()};
          } on TavilyException catch (e) {
            _log('web_search Tavily failure: $e');
            return {'error': e.toString()};
          } catch (e) {
            return {'error': 'Web search failed: $e'};
          }

        case 'deep_research':
          final query = ((args['query'] ?? args['topic']) as String? ?? '').trim();
          if (query.isEmpty) {
            return {'error': 'deep_research needs a non-empty `query` argument.'};
          }
          if (_deepResearchRunner == null) {
            return {
              'error':
                  'Deep research is not initialised. Open the app once to register the runner.',
            };
          }
          try {
            return await _deepResearchRunner!(query);
          } catch (e) {
            return {'error': 'Deep research failed: $e'};
          }

        case 'ask_oracle':
          final question =
              ((args['question'] ?? args['query']) as String? ?? '').trim();
          if (question.isEmpty) {
            return {'error': 'ask_oracle needs a non-empty `question` argument.'};
          }
          if (_oracleRunner == null) {
            return {
              'error':
                  'Oracle is not initialised. Open the app once to register the runner.',
            };
          }
          try {
            return await _oracleRunner!(question);
          } catch (e) {
            return {'error': 'Oracle failed: $e'};
          }

        case 'set_timer':
          final raw = args['minutes'] ?? args['duration'];
          final minutes = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
          if (minutes <= 0) {
            return {'error': 'set_timer needs `minutes` (a positive number).'};
          }
          if (_setTimerRunner == null) {
            return {
              'success': false,
              'message': 'Timer runner not initialised.',
            };
          }
          return await _setTimerRunner!(minutes);

        case 'play_animation':
        case 'robot_animation':
          final seqName = (args['sequence'] as String? ??
                  args['animation'] as String? ??
                  args['name'] as String? ??
                  '')
              .trim();
          if (seqName.isEmpty) {
            return {'error': 'play_animation needs a `sequence` name.'};
          }
          final index = RobotAnimation.fromName(seqName);
          if (index == null) {
            return {
              'error':
                  'Unknown animation "$seqName". Valid names: nod, shake, '
                  'look_around, wink, yawn, laugh, eye_roll, mouth_cycle, '
                  'eye_cycle, wiggle.',
            };
          }
          if (_playAnimationRunner == null) {
            return {
              'success': false,
              'message': 'Robot animation runner not initialised.',
            };
          }
          return await _playAnimationRunner!(index);

        case 'play_movement_trick':
        case 'robot_trick':
          final trickName = (args['trick'] as String? ??
                  args['name'] as String? ??
                  '')
              .trim();
          if (trickName.isEmpty) {
            return {'error': 'play_movement_trick needs a `trick` name.'};
          }
          final index = RobotMovementTrick.fromName(trickName);
          if (index == null) {
            return {
              'error':
                  'Unknown trick "$trickName". Valid names: crazy_eyes, '
                  'chatter, slow_scan, peekaboo, double_blink, jaw_drop, '
                  'drowsy, side_eye, happy_bounce, confused.',
            };
          }
          if (_playMovementTrickRunner == null) {
            return {
              'success': false,
              'message': 'Robot trick runner not initialised.',
            };
          }
          return await _playMovementTrickRunner!(index);

        default:
          return {'error': 'Unknown tool: $toolName'};
      }
    } catch (e) {
      return {'error': 'Tool execution failed: $e'};
    }
  }
}
