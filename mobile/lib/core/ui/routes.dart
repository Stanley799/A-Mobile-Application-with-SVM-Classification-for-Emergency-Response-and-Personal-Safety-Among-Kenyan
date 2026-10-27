// One page transition for the app: the iOS-style slide with the swipe-back edge gesture. Part of Flutter itself (no extra package).
import 'package:flutter/cupertino.dart';

Route<T> appRoute<T>(WidgetBuilder builder, {bool fullscreenDialog = false}) => CupertinoPageRoute<T>(builder: builder, fullscreenDialog: fullscreenDialog);
