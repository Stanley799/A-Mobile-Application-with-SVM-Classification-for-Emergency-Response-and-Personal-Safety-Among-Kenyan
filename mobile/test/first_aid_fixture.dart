// Test-only helpers. The real pack is read from disk; the "approved" copy changes status
// in memory so player/search tests can run without editing the reviewed asset.
import 'dart:convert';
import 'dart:io';

import 'package:mobile/features/resident/first_aid/first_aid_models.dart';

Map<String, dynamic> realFirstAidJson() =>
    jsonDecode(File('assets/first_aid/guides.json').readAsStringSync()) as Map<String, dynamic>;

FirstAidCatalog realFirstAidCatalog() => FirstAidCatalog.fromJson(realFirstAidJson());

FirstAidCatalog approvedFirstAidCatalog() {
  final json = realFirstAidJson();
  for (final item in json['guides'] as List) {
    final guide = item as Map<String, dynamic>;
    if (guide['status'] == FirstAidGuide.statusDraft) {
      guide['status'] = FirstAidGuide.statusApproved;
    }
  }
  return FirstAidCatalog.fromJson(json);
}
