import 'package:flutter_test/flutter_test.dart';
import 'package:taskly_mobile/core/ai/quick_task_detector.dart';

void main() {
  group('QuickTaskDetector', () {
    test('detects a self-assigned task immediately', () {
      final result = QuickTaskDetector.detect(
        body: 'Remind me to buy bread',
        isGroup: false,
        isSelfChat: true,
        currentProfileId: 10,
        otherProfileId: null,
        mentionedProfileIds: const [],
      );

      expect(result, isNotNull);
      expect(result!.assigneeProfileId, 10);
      expect(result.title, 'Buy bread');
    });

    test('assigns a direct-chat request to the other person', () {
      final result = QuickTaskDetector.detect(
        body: 'Please send the report',
        isGroup: false,
        isSelfChat: false,
        currentProfileId: 10,
        otherProfileId: 22,
        mentionedProfileIds: const [],
      );

      expect(result, isNotNull);
      expect(result!.assigneeProfileId, 22);
      expect(result.title, 'Send the report');
    });

    test('requires a mentioned assignee in groups', () {
      final withoutMention = QuickTaskDetector.detect(
        body: 'Please send the report',
        isGroup: true,
        isSelfChat: false,
        currentProfileId: 10,
        otherProfileId: null,
        mentionedProfileIds: const [],
      );
      final withMention = QuickTaskDetector.detect(
        body: '@Raja please send the report',
        isGroup: true,
        isSelfChat: false,
        currentProfileId: 10,
        otherProfileId: null,
        mentionedProfileIds: const [22],
      );

      expect(withoutMention, isNull);
      expect(withMention, isNotNull);
      expect(withMention!.assigneeProfileId, 22);
      expect(withMention.title, 'Send the report');
    });

    test('detects a short concrete task', () {
      final result = QuickTaskDetector.detect(
        body: 'Eat',
        isGroup: false,
        isSelfChat: true,
        currentProfileId: 10,
        otherProfileId: null,
        mentionedProfileIds: const [],
      );

      expect(result, isNotNull);
      expect(result!.title, 'Eat');
    });

    test('does not flag greetings as tasks', () {
      final result = QuickTaskDetector.detect(
        body: 'Hey',
        isGroup: false,
        isSelfChat: false,
        currentProfileId: 10,
        otherProfileId: 22,
        mentionedProfileIds: const [],
      );

      expect(result, isNull);
    });
  });
}
