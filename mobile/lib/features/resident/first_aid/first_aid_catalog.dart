// Loads the guide pack once and keeps it in memory. A parse failure is surfaced to the
// screen (ErrorState + emergency numbers); it never crashes the app.
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'first_aid_constants.dart';
import 'first_aid_models.dart';

class FirstAidCatalogLoader {
  FirstAidCatalogLoader._();

  static FirstAidCatalog? _cache;
  static Future<FirstAidCatalog>? _pending;

  static Future<FirstAidCatalog> load({bool force = false, AssetBundle? bundle}) {
    final cached = _cache;
    if (!force && cached != null) return Future.value(cached);
    final pending = _pending;
    if (!force && pending != null) return pending;
    final next = _read(bundle).then((catalog) {
      _cache = catalog;
      _pending = null;
      return catalog;
    }, onError: (Object error, StackTrace stack) {
      _pending = null;
      Error.throwWithStackTrace(error, stack);
    });
    _pending = next;
    return next;
  }

  static Future<FirstAidCatalog> _read(AssetBundle? bundle) async {
    final source = await (bundle ?? rootBundle).loadString(kFirstAidAssetPath);
    return FirstAidCatalog.fromJsonString(source);
  }

  /// Tests only: forget the cached pack.
  static void resetForTest() {
    _cache = null;
    _pending = null;
  }
}
