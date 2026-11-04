// The responder's live map. Navigation now lives in ResponderNavScreen; this keeps the old name so the job screens do not change.
import 'package:flutter/material.dart';

import '../../core/models/dispatch_models.dart' show Offer;
import 'responder_nav_screen.dart';

class JobMapScreen extends StatelessWidget {
  const JobMapScreen({super.key, required this.offer});
  final Offer offer;

  @override
  Widget build(BuildContext context) => ResponderNavScreen(offer: offer);
}
