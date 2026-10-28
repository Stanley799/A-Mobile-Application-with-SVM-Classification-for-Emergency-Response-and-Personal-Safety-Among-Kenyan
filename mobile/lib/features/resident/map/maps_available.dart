import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'maps_runtime_stub.dart'
    if (dart.library.js_interop) 'maps_runtime_web.dart' as maps_runtime;

bool hasGoogleMapsRuntime() {
  if (!kIsWeb) return true;
  return maps_runtime.isAvailable;
}

class MapsUnavailableView extends StatelessWidget {
  const MapsUnavailableView({
    super.key,
    this.title = 'Map unavailable',
    this.message = 'Google Maps is not available in this browser because the Maps JavaScript API key has not been configured.',
    this.primaryAction,
  });

  final String title;
  final String message;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E1DA)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Color(0xFF5F5F5F),
                    ),
                  ),
                  if (primaryAction != null) ...[
                    const SizedBox(height: 18),
                    primaryAction!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
