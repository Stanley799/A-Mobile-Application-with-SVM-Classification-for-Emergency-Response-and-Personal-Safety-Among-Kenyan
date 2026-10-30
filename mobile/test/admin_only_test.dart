import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/role_gate.dart';
import 'package:mobile/features/ops/ops_logic.dart';

void main() {
  test('only the server-set SystemAdmin claim opens the monitor', () {
    expect(opensMonitor('SystemAdmin'), isTrue);
    expect(opensMonitor('Dispatcher'), isFalse);
    expect(opensMonitor('Responder'), isFalse);
    expect(opensMonitor('Resident'), isFalse);
    expect(opensMonitor(null), isFalse);
  });

  test('the monitor owns every section, and none is opened by a profile field', () {
    expect(sectionsFor(), OpsSection.values);
    expect(sectionsFor(), containsAll([
      OpsSection.controlRoom,
      OpsSection.incidents,
      OpsSection.units,
      OpsSection.approvals,
      OpsSection.directory,
      OpsSection.analytics,
      OpsSection.audit,
    ]));
  });
}
