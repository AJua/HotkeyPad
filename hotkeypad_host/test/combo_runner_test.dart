import 'package:hotkeypad_host/src/host_page.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runComboSteps', () {
    test('runs every step in order, succeeding overall', () async {
      final ran = <DeckItem>[];
      final waited = <Duration>[];
      const steps = [
        ComboStep(action: ActionItem(DeckAction.mute), delayMs: 0),
        ComboStep(action: AppItem('Safari'), delayMs: 500),
        ComboStep(action: AppItem('Chrome'), delayMs: 250),
      ];

      final result = await runComboSteps(
        steps,
        run: (item) async {
          ran.add(item);
          return (ok: true, message: 'did ${item.label}');
        },
        delay: (duration) async => waited.add(duration),
      );

      expect(ran, [
        const ActionItem(DeckAction.mute),
        const AppItem('Safari'),
        const AppItem('Chrome'),
      ]);
      // No delay call for the first step, whose delay is 0 — see
      // runComboSteps' `if (step.delayMs > 0)` guard.
      expect(waited, [
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 250),
      ]);
      expect(result.ok, isTrue);
      expect(result.message, 'Ran 3 steps');
    });

    test('waits before a step even when it is the first', () async {
      final waited = <Duration>[];

      await runComboSteps(
        [const ComboStep(action: AppItem('Safari'), delayMs: 1000)],
        run: (item) async => (ok: true, message: ''),
        delay: (duration) async => waited.add(duration),
      );

      expect(waited, [const Duration(milliseconds: 1000)]);
    });

    test('stops at the first failure without running later steps', () async {
      final ran = <DeckItem>[];

      final result = await runComboSteps(
        const [
          ComboStep(action: AppItem('Safari'), delayMs: 0),
          ComboStep(action: AppItem('Broken'), delayMs: 0),
          ComboStep(action: AppItem('Never'), delayMs: 0),
        ],
        run: (item) async {
          ran.add(item);
          return (ok: item.label != 'Broken', message: '${item.label} result');
        },
        delay: (duration) async {},
      );

      expect(ran.map((i) => i.label), ['Safari', 'Broken']);
      expect(result.ok, isFalse);
      expect(result.message, 'Step 2: Broken result');
    });
  });
}
