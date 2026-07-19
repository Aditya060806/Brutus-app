import 'package:flutter_test/flutter_test.dart';

import 'package:brutus_app/data/services/tool_dispatcher.dart';
import 'package:brutus_app/features/home/widgets/recent_activity_list.dart';
import 'package:brutus_app/providers/chat_provider.dart';
import 'package:brutus_app/providers/robot_provider.dart';
import 'package:brutus_app/providers/user_prefs_provider.dart';

void main() {
  group('Robot name → index mappings (Gemini tool dispatch)', () {
    test('animation names resolve across separators and casing', () {
      expect(RobotAnimation.fromName('nod'), RobotAnimation.nod);
      expect(RobotAnimation.fromName('Look Around'), RobotAnimation.lookAround);
      expect(RobotAnimation.fromName('look_around'), RobotAnimation.lookAround);
      expect(RobotAnimation.fromName('eye-roll'), RobotAnimation.eyeRoll);
      expect(RobotAnimation.fromName('WIGGLE'), RobotAnimation.wiggle);
      expect(RobotAnimation.fromName('moonwalk'), isNull);
    });

    test('movement trick names resolve', () {
      expect(RobotMovementTrick.fromName('crazy_eyes'),
          RobotMovementTrick.crazyEyes);
      expect(RobotMovementTrick.fromName('peekaboo'),
          RobotMovementTrick.peekaboo);
      expect(RobotMovementTrick.fromName('Happy Bounce'),
          RobotMovementTrick.happyBounce);
      expect(RobotMovementTrick.fromName('jaw drop'),
          RobotMovementTrick.jawDrop);
      expect(RobotMovementTrick.fromName('backflip'), isNull);
    });

    test('emotion tags map to expressions; unknown tags are ignored', () {
      expect(RobotExpression.fromEmotionTag('happy'), RobotExpression.happy);
      expect(RobotExpression.fromEmotionTag('SURPRISED'),
          RobotExpression.surprised);
      expect(RobotExpression.fromEmotionTag('confused'), isNull);
      expect(RobotExpression.fromEmotionTag(null), isNull);
      expect(RobotExpression.fromEmotionTag(''), isNull);
    });

    test('every expression maps to a valid LED pattern', () {
      for (var expr = 0; expr <= 5; expr++) {
        final led = RobotExpression.toLedPattern(expr);
        expect(led, inInclusiveRange(0, 3));
      }
      expect(RobotExpression.toLedPattern(RobotExpression.sleepy),
          RobotLedPattern.off);
      expect(RobotExpression.toLedPattern(RobotExpression.angry),
          RobotLedPattern.fastBlink);
    });

    test('labels and emojis stay in sync with the 10 firmware slots', () {
      expect(RobotAnimation.labels.length, 10);
      expect(RobotAnimation.emojis.length, 10);
      expect(RobotMovementTrick.labels.length, 10);
      expect(RobotMovementTrick.emojis.length, 10);
    });
  });

  group('ChatMessage persistence', () {
    test('toMap → fromMap roundtrip preserves every field', () {
      final original = ChatMessage(
        id: '123',
        text: 'Hello **Brutus**',
        role: MessageRole.tool,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1720000000000),
        toolName: 'get_weather',
      );
      final restored = ChatMessage.fromMap(original.toMap());
      expect(restored.id, original.id);
      expect(restored.text, original.text);
      expect(restored.role, original.role);
      expect(restored.timestamp, original.timestamp);
      expect(restored.toolName, original.toolName);
    });

    test('fromMap survives missing/corrupt fields with safe defaults', () {
      final restored = ChatMessage.fromMap(const {});
      expect(restored.role, MessageRole.assistant);
      expect(restored.text, '');
      expect(restored.toolName, isNull);

      final badRole = ChatMessage.fromMap(const {'role': 'alien'});
      expect(badRole.role, MessageRole.assistant);
    });
  });

  group('ToolDispatcher argument validation', () {
    final dispatcher = ToolDispatcher.instance;

    test('unknown tool returns a structured error', () async {
      final r = await dispatcher.dispatch('warp_drive', {});
      expect(r['error'], contains('Unknown tool'));
    });

    test('get_time works without any runners', () async {
      final r = await dispatcher.dispatch('get_time', {});
      expect(r['time'], isNotNull);
      expect(r['date'], isNotNull);
      expect(r['iso'], isNotNull);
    });

    test('set_timer rejects zero/absent minutes', () async {
      final r0 = await dispatcher.dispatch('set_timer', {'minutes': 0});
      expect(r0['error'], contains('minutes'));
      final rAbsent = await dispatcher.dispatch('set_timer', {});
      expect(rAbsent['error'], contains('minutes'));
    });

    test('set_timer without a registered runner degrades gracefully',
        () async {
      final r = await dispatcher.dispatch('set_timer', {'minutes': 5});
      expect(r['success'], isFalse);
      expect(r['message'], contains('not initialised'));
    });

    test('send_email requires to/subject/body', () async {
      final r = await dispatcher
          .dispatch('send_email', {'to': 'a@b.com', 'subject': '', 'body': ''});
      expect(r['success'], isFalse);
      expect(r['error'], isNotNull);
    });

    test('play_animation rejects unknown sequence names with guidance',
        () async {
      final r =
          await dispatcher.dispatch('play_animation', {'sequence': 'moonwalk'});
      expect(r['error'], contains('Unknown animation'));
      expect(r['error'], contains('nod'));
    });

    test('play_movement_trick accepts alias arg names', () async {
      // Valid name but no runner registered in tests → graceful message.
      final r =
          await dispatcher.dispatch('play_movement_trick', {'name': 'jaw_drop'});
      expect(r['success'], isFalse);
      expect(r['message'], contains('not initialised'));
    });
  });

  group('UserPrefs helpers', () {
    test('initials from one and two words', () {
      expect(const UserPrefs(userName: 'Aditya Pandey').initials, 'AP');
      expect(const UserPrefs(userName: 'Aditya').initials, 'A');
      expect(const UserPrefs(userName: '  ').initials, 'B');
    });

    test('firstName falls back gracefully', () {
      expect(const UserPrefs(userName: 'Aditya Pandey').firstName, 'Aditya');
      expect(const UserPrefs(userName: '').firstName, 'there');
    });

    test('voice profile storage values match what the voice services read',
        () {
      expect(VoicePref.male.storageValue, 'MALE');
      expect(VoicePref.female.storageValue, 'FEMALE');
    });
  });

  group('relativeTime formatting', () {
    test('buckets are correct', () {
      final now = DateTime.now();
      expect(relativeTime(now), 'just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 5))),
          '5 min ago');
      expect(relativeTime(now.subtract(const Duration(hours: 3))), '3 hr ago');
      expect(relativeTime(now.subtract(const Duration(days: 1))), 'Yesterday');
      expect(relativeTime(now.subtract(const Duration(days: 3))), '3 days ago');
    });
  });
}
