import 'package:hotkeypad_client/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

/// The background image must never make the deck's own buttons wait
/// behind it — see [nextIconFetch]'s doc comment.
void main() {
  group('nextIconFetch', () {
    test('returns null when nothing is queued', () {
      expect(
        nextIconFetch(queue: [], pendingBackground: null),
        isNull,
      );
    });

    test('fetches the background when it is the only thing pending', () {
      expect(
        nextIconFetch(queue: [], pendingBackground: 'bg_1'),
        (name: 'bg_1', lowPriority: true),
      );
    });

    test('always prefers an ordinary icon over a pending background', () {
      expect(
        nextIconFetch(queue: ['Slack'], pendingBackground: 'bg_1'),
        (name: 'Slack', lowPriority: false),
      );
    });

    test('takes ordinary icons in queue order', () {
      expect(
        nextIconFetch(queue: ['Slack', 'Chrome'], pendingBackground: 'bg_1'),
        (name: 'Slack', lowPriority: false),
      );
    });
  });
}
