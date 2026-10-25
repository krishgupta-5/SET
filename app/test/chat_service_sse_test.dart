import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:startup_expense_tracker/services/chat_service.dart';

String _delta(String text) =>
    'data: ${jsonEncode({
      'choices': [
        {'delta': {'content': text}},
      ],
    })}';

void main() {
  group('ChatService.parseSseLine', () {
    test('extracts token text', () {
      expect(ChatService.parseSseLine(_delta('Hello')), 'Hello');
    });

    test('recognises [DONE] and ignores keep-alives', () {
      expect(ChatService.parseSseLine('data: [DONE]'), ChatService.sseDone);
      expect(ChatService.parseSseLine(''), isNull);
      expect(ChatService.parseSseLine(': ping'), isNull);
      expect(ChatService.parseSseLine('data: {"choices":[{"delta":{}}]}'), isNull);
    });

    test('server error becomes a user-safe ChatException', () {
      expect(
        () => ChatService.parseSseLine('data: {"error": "AI busy"}'),
        throwsA(isA<ChatException>().having((e) => e.message, 'message', 'AI busy')),
      );
    });

    test('malformed JSON is skipped, not fatal', () {
      expect(ChatService.parseSseLine('data: {"choices": [tru'), isNull);
    });

    test('lines split across network chunks are reassembled', () async {
      // Two SSE events whose bytes arrive split mid-JSON — the old parser
      // split each chunk on "\n" and silently dropped both halves.
      final full = '${_delta('Runway is ')}\n\n${_delta('8 months')}\n\n';
      final mid = full.length ~/ 2;
      final chunks = Stream.fromIterable([full.substring(0, mid), full.substring(mid)]);

      final tokens = await chunks
          .transform(const LineSplitter())
          .map(ChatService.parseSseLine)
          .where((t) => t != null && t != ChatService.sseDone)
          .cast<String>()
          .toList();

      expect(tokens.join(), 'Runway is 8 months');
    });
  });
}
