// Entry points to the guided first-aid tool. The content itself lives in first_aid_screen.dart (Part 6).
import 'package:flutter/material.dart';

import 'first_aid_screen.dart';

/// Opens the guide for the incident's classified category and subtype when known.
Future<void> openFirstAid(BuildContext context, {String? category, String? subtype}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FirstAidScreen(category: category, subtype: subtype)));
