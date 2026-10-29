// Shared pieces of the first-aid screens: the emergency call panel, dial/copy behaviour,
// the EN | SW toggle, and the warning/donts cards.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/ui/app_button.dart';
import '../../../../core/ui/feedback.dart';
import '../../../../core/ui/tokens.dart';
import 'first_aid_constants.dart';

/// 999 and 112, always reachable. Shown before suggestions for immediate-threat words.
class FirstAidCallPanel extends StatelessWidget {
  const FirstAidCallPanel({
    super.key,
    required this.language,
    this.message,
    this.numbers = kFirstAidFallbackNumbers,
  });

  final FirstAidLanguage language;
  final String? message;
  final List<String> numbers;

  @override
  Widget build(BuildContext context) {
    final shown = numbers.isEmpty ? kFirstAidFallbackNumbers : numbers;
    return Container(
      key: const ValueKey('first_aid_emergency_call_panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Tk.dangerTint,
        borderRadius: BorderRadius.circular(Tk.rCard),
        border: Border.all(color: const Color(0xFFF0C9C9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emergency_outlined, color: Tk.danger, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  FirstAidCopy.of(language, 'emergencyTitle'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Tk.danger),
                ),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              style: const TextStyle(fontSize: 15, height: 1.35, color: Tk.ink),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < shown.length && i < 2; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    label: FirstAidCopy.fill(
                      FirstAidCopy.of(language, 'callNumber'),
                      {'number': shown[i]},
                    ),
                    kind: i == 0 ? AppButtonKind.danger : AppButtonKind.secondary,
                    height: 56,
                    icon: Icons.call,
                    onPressed: () => firstAidDial(context, shown[i], language: language),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// On the web a tel: link cannot dial, so copy the number and say so. On a phone, open the dialer.
Future<void> firstAidDial(
  BuildContext context,
  String number, {
  required FirstAidLanguage language,
  bool? webOverride,
  Future<void> Function(String)? copy,
}) async {
  if (webOverride ?? kIsWeb) {
    try {
      if (copy != null) {
        await copy(number);
      } else {
        await Clipboard.setData(ClipboardData(text: number));
      }
    } catch (_) {
      // The number is still written on the button.
    }
    if (context.mounted) {
      AppToast.show(
        context,
        FirstAidCopy.fill(FirstAidCopy.of(language, 'webCopied'), {'number': number}),
      );
    }
    return;
  }
  var opened = false;
  try {
    opened = await launchUrl(Uri(scheme: 'tel', path: number));
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    AppToast.show(
      context,
      FirstAidCopy.fill(FirstAidCopy.of(language, 'dialFailed'), {'number': number}),
      kind: ToastKind.error,
    );
  }
}

class FirstAidLanguageToggle extends StatelessWidget {
  const FirstAidLanguageToggle({
    super.key,
    required this.language,
    required this.onChanged,
  });

  /// Null on the very first screen: nothing is selected until the person chooses.
  final FirstAidLanguage? language;
  final ValueChanged<FirstAidLanguage> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _LangButton(language: FirstAidLanguage.en, selected: language == FirstAidLanguage.en, onTap: onChanged),
      const Text('|', style: TextStyle(color: Tk.faint, fontSize: 16)),
      _LangButton(language: FirstAidLanguage.sw, selected: language == FirstAidLanguage.sw, onTap: onChanged),
    ],
  );
}

class _LangButton extends StatelessWidget {
  const _LangButton({required this.language, required this.selected, required this.onTap});

  final FirstAidLanguage language;
  final bool selected;
  final ValueChanged<FirstAidLanguage> onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: language.label,
    child: InkWell(
      key: ValueKey('first_aid_lang_${language.toggleLabel}'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => onTap(language),
      child: Container(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          language.toggleLabel,
          style: TextStyle(
            fontSize: 16,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? Tk.brandDeep : Tk.faint,
            decoration: selected ? TextDecoration.underline : TextDecoration.none,
            decorationColor: Tk.brandDeep,
            decorationThickness: 2,
          ),
        ),
      ),
    ),
  );
}

enum FirstAidNoticeTone { warning, danger }

/// Warning and donts are separate cards on purpose; they are not folded into the step body.
class FirstAidNoticeCard extends StatelessWidget {
  const FirstAidNoticeCard({
    super.key,
    required this.title,
    required this.lines,
    required this.tone,
  });

  final String title;
  final List<String> lines;
  final FirstAidNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final danger = tone == FirstAidNoticeTone.danger;
    final ink = danger ? Tk.danger : Tk.warnInk;
    final tint = danger ? Tk.dangerTint : Tk.warnTint;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(Tk.rCard),
        border: Border.all(color: danger ? const Color(0xFFF0C9C9) : const Color(0xFFF3D6B3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(danger ? Icons.block : Icons.warning_amber_rounded, color: ink, size: 22),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: TextStyle(fontSize: 18, height: 1.35, color: ink, fontWeight: FontWeight.w800)),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(fontSize: 18, height: 1.4, color: Tk.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class FirstAidGuideTile extends StatelessWidget {
  const FirstAidGuideTile({
    super.key,
    required this.title,
    required this.stepsLabel,
    required this.onTap,
  });

  final String title;
  final String stepsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: title,
    child: Material(
      color: Tk.card,
      borderRadius: BorderRadius.circular(Tk.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(Tk.rCard),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: Tk.brandTint, shape: BoxShape.circle),
                child: const Icon(Icons.medical_services_outlined, color: Tk.brandDeep, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Tk.ink)),
                    const SizedBox(height: 3),
                    Text(stepsLabel, style: const TextStyle(fontSize: 13, color: Tk.mute)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Tk.faint),
            ],
          ),
        ),
      ),
    ),
  );
}
