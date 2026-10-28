import 'dart:js_interop';

@JS('google.maps')
external JSAny? get _googleMapsRuntime;

@JS('google')
external JSAny? get _googleGlobal;

bool get isAvailable {
	try {
		return _googleGlobal != null && _googleMapsRuntime != null;
	} catch (_) {
		return false;
	}
}