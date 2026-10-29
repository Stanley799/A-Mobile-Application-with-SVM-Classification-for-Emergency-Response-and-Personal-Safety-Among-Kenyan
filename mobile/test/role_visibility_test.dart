import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/ops/ops_logic.dart';

void main() {
  test('a dispatcher sees the control room, incidents, units and pass-on notes only', () {
    final visible = sectionsFor(isAdmin: false);
    expect(visible, [OpsSection.controlRoom, OpsSection.incidents, OpsSection.units, OpsSection.passOnNotes]);
    expect(visible.contains(OpsSection.directory), isFalse);
    expect(visible.contains(OpsSection.analytics), isFalse);
    expect(visible.contains(OpsSection.approvals), isFalse);
    expect(visible.contains(OpsSection.audit), isFalse);
  });

  test('an administrator sees every section', () {
    expect(sectionsFor(isAdmin: true), OpsSection.values);
  });

  test('each section is gated by role, not just hidden', () {
    expect(canUseSection(OpsSection.analytics, isAdmin: false), isFalse);
    expect(canUseSection(OpsSection.directory, isAdmin: false), isFalse);
    expect(canUseSection(OpsSection.approvals, isAdmin: false), isFalse);
    expect(canUseSection(OpsSection.audit, isAdmin: false), isFalse);
    expect(canUseSection(OpsSection.units, isAdmin: false), isTrue);
    expect(canUseSection(OpsSection.audit, isAdmin: true), isTrue);
  });
}
