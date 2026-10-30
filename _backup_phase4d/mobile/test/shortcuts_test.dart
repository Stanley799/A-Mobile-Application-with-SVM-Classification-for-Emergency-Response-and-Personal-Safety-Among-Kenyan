import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/ops/ops_logic.dart';

void main() {
  test('shortcuts are ignored while a text field has focus', () {
    for (final key in ['j', 'k', 'Enter', 'a', 'm', '/', 'Escape', '?']) {
      expect(shortcutFor(key, typing: true), isNull);
    }
  });

  test('each shortcut maps to its action', () {
    expect(shortcutFor('j', typing: false), OpsShortcut.nextIncident);
    expect(shortcutFor('K', typing: false), OpsShortcut.previousIncident);
    expect(shortcutFor('Enter', typing: false), OpsShortcut.openIncident);
    expect(shortcutFor('a', typing: false), OpsShortcut.candidates);
    expect(shortcutFor('M', typing: false), OpsShortcut.message);
    expect(shortcutFor('/', typing: false), OpsShortcut.search);
    expect(shortcutFor('Escape', typing: false), OpsShortcut.closePanel);
    expect(shortcutFor('?', typing: false), OpsShortcut.help);
  });

  test('other keys do nothing and every action has help text', () {
    expect(shortcutFor('q', typing: false), isNull);
    expect(shortcutFor(' ', typing: false), isNull);
    expect(kShortcutHelp.length, OpsShortcut.values.length);
  });
}
