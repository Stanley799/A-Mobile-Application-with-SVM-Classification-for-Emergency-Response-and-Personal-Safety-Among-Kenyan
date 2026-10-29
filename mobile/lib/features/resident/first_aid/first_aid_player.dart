// The reader. One step per screen, a pinned banner and a pinned call button, and no
// auto-advance: the person always chooses Back or Next.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart' show AppShadows;
import '../../../../core/ui/app_button.dart';
import '../../../../core/ui/tokens.dart';
import 'first_aid_constants.dart';
import 'first_aid_models.dart';
import 'first_aid_widgets.dart';

class FirstAidPlayer extends StatefulWidget {
  const FirstAidPlayer({
    super.key,
    required this.guide,
    required this.catalog,
    required this.language,
    required this.onChooseDifferent,
    required this.onDone,
    this.quiet = false,
    this.showDraftBanner = false,
    this.onCall,
  });

  final FirstAidGuide guide;
  final FirstAidCatalog catalog;
  final FirstAidLanguage language;
  final VoidCallback onChooseDifferent;
  final VoidCallback onDone;
  final bool quiet;
  final bool showDraftBanner;
  final void Function(String number)? onCall;

  @override
  State<FirstAidPlayer> createState() => _FirstAidPlayerState();
}

class _FirstAidPlayerState extends State<FirstAidPlayer> {
  int _step = 0;
  bool _hapticsOn = false;
  Timer? _haptics;

  @override
  void didUpdateWidget(covariant FirstAidPlayer old) {
    super.didUpdateWidget(old);
    if (old.guide.id != widget.guide.id) {
      _step = 0;
      _hapticsOn = false;
      _syncHaptics();
    } else if (old.quiet != widget.quiet && widget.quiet) {
      _hapticsOn = false;
      _syncHaptics();
    }
  }

  @override
  void dispose() {
    _haptics?.cancel();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.guide.steps.length) return;
    setState(() => _step = index);
    _syncHaptics();
  }

  void _syncHaptics() {
    _haptics?.cancel();
    _haptics = null;
    if (widget.quiet || !_hapticsOn) return;
    final pulse = widget.guide.steps[_step].pulse;
    if (pulse == null) return;
    final period = Duration(milliseconds: (60000 / pulse.bpm).round());
    _haptics = Timer.periodic(period, (_) => HapticFeedback.lightImpact());
  }

  Future<void> _call999() async {
    final cb = widget.onCall;
    if (cb != null) {
      cb('999');
      return;
    }
    await firstAidDial(context, '999', language: widget.language);
  }

  @override
  Widget build(BuildContext context) {
    final guide = widget.guide;
    final language = widget.language;
    final step = guide.steps[_step];
    final last = _step == guide.steps.length - 1;
    final banner = guide.banner;
    final warning = guide.warning;
    final donts = [for (final d in guide.donts) d.of(language)];

    return Column(
      children: [
        if (widget.showDraftBanner) _draftBanner(),
        if (banner != null) _guideBanner(banner.of(language)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guide.titleFor(language),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tk.faint),
                ),
                const SizedBox(height: 8),
                Text(
                  FirstAidCopy.fill(
                    FirstAidCopy.of(language, 'stepOf'),
                    {'n': _step + 1, 'total': guide.steps.length},
                  ),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tk.brandDeep),
                ),
                const SizedBox(height: 10),
                Text(
                  step.title.of(language),
                  key: const ValueKey('first_aid_step_title'),
                  style: const TextStyle(fontSize: 24, height: 1.22, fontWeight: FontWeight.w800, color: Tk.ink),
                ),
                const SizedBox(height: 12),
                Text(
                  step.body.of(language),
                  key: const ValueKey('first_aid_step_body'),
                  style: const TextStyle(fontSize: 20, height: 1.48, color: Tk.ink),
                ),
                if (step.pulse != null) ...[
                  const SizedBox(height: 18),
                  _pulseCard(step.pulse!),
                ],
                if (warning != null) ...[
                  const SizedBox(height: 18),
                  FirstAidNoticeCard(
                    key: const ValueKey('first_aid_warning_card'),
                    title: FirstAidCopy.of(language, 'warning'),
                    lines: [warning.of(language)],
                    tone: FirstAidNoticeTone.warning,
                  ),
                ],
                if (donts.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  FirstAidNoticeCard(
                    key: const ValueKey('first_aid_donts_card'),
                    title: FirstAidCopy.of(language, 'donts'),
                    lines: donts,
                    tone: FirstAidNoticeTone.danger,
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  key: const ValueKey('first_aid_choose_different'),
                  onPressed: widget.onChooseDifferent,
                  child: Text(
                    FirstAidCopy.of(language, 'chooseDifferent'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Tk.brandDeep),
                  ),
                ),
              ],
            ),
          ),
        ),
        _bottomBar(language, last),
      ],
    );
  }

  Widget _draftBanner() => Container(
    key: const ValueKey('first_aid_draft_banner'),
    width: double.infinity,
    color: Tk.dangerTint,
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: Tk.danger, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.catalog.draftNoticeFor(widget.language),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Tk.danger),
          ),
        ),
      ],
    ),
  );

  Widget _guideBanner(String text) => Container(
    key: const ValueKey('first_aid_guide_banner'),
    width: double.infinity,
    color: Tk.warnTint,
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
    child: Row(
      children: [
        const Icon(Icons.campaign_outlined, color: Tk.warnInk, size: 21),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w700, color: Tk.warnInk),
          ),
        ),
      ],
    ),
  );

  Widget _pulseCard(FirstAidPulse pulse) {
    final language = widget.language;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      key: const ValueKey('first_aid_pulse_card'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
      decoration: BoxDecoration(
        color: Tk.card,
        borderRadius: BorderRadius.circular(Tk.rCard),
        border: Border.all(color: Tk.line),
      ),
      child: Column(
        children: [
          if (reduceMotion)
            _PulseFace(pulse: pulse, language: language, reduced: true)
          else
            _PulsingCircle(pulse: pulse, language: language),
          const SizedBox(height: 6),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                FirstAidCopy.of(language, 'gentleVibration'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Tk.ink),
              ),
              subtitle: widget.quiet
                  ? Text(
                      FirstAidCopy.of(language, 'vibrationOffQuiet'),
                      style: const TextStyle(fontSize: 13, color: Tk.mute),
                    )
                  : null,
              value: _hapticsOn && !widget.quiet,
              onChanged: widget.quiet
                  ? null
                  : (value) {
                      setState(() => _hapticsOn = value);
                      _syncHaptics();
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(FirstAidLanguage language, bool last) => Container(
    decoration: const BoxDecoration(
      color: Tk.card,
      boxShadow: AppShadows.navigation,
    ),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: AppButton(
              key: const ValueKey('first_aid_call_999'),
              label: FirstAidCopy.of(language, 'call999'),
              icon: Icons.call,
              kind: AppButtonKind.danger,
              height: 56,
              onPressed: _call999,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: FirstAidCopy.of(language, 'back'),
                  kind: AppButtonKind.secondary,
                  height: 56,
                  onPressed: _step == 0 ? null : () => _goTo(_step - 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: FirstAidCopy.of(language, last ? 'done' : 'next'),
                  height: 56,
                  onPressed: last ? widget.onDone : () => _goTo(_step + 1),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PulsingCircle extends StatefulWidget {
  const _PulsingCircle({required this.pulse, required this.language});

  final FirstAidPulse pulse;
  final FirstAidLanguage language;

  @override
  State<_PulsingCircle> createState() => _PulsingCircleState();
}

class _PulsingCircleState extends State<_PulsingCircle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (60000 / widget.pulse.bpm).round()),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final scale = 0.88 + 0.14 * Curves.easeInOut.transform(_controller.value);
      return Transform.scale(scale: scale, child: child);
    },
    child: _PulseFace(pulse: widget.pulse, language: widget.language, reduced: false),
  );
}

/// The number is the same whether or not the circle animates.
class _PulseFace extends StatelessWidget {
  const _PulseFace({required this.pulse, required this.language, required this.reduced});

  final FirstAidPulse pulse;
  final FirstAidLanguage language;
  final bool reduced;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(reduced ? 'first_aid_pulse_static' : 'first_aid_pulse'),
    width: 160,
    height: 160,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Tk.dangerTint,
      border: Border.all(color: const Color(0xFFE7B4B4), width: 3),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.favorite, color: Tk.danger, size: 30),
        const SizedBox(height: 4),
        Text(
          '${pulse.bpm}',
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Tk.danger, height: 1.1),
        ),
        Text(
          FirstAidCopy.fill(FirstAidCopy.of(language, 'perMinute'), {'bpm': pulse.bpm}),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Tk.danger),
        ),
      ],
    ),
  );
}
