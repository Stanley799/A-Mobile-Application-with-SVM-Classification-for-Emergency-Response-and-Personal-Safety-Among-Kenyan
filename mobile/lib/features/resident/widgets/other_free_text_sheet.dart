import 'package:flutter/material.dart';

import '../../../core/models/emergency_enums.dart';
import '../../../core/services/priority_classifier.dart';
import '../../../core/theme/app_theme.dart';

/// Structured fallback for emergency reports that do not fit the fixed category
/// list. The prompt is required so the system always has a meaningful text
/// signal to classify, even when it cannot rely on a structured branch.
class OtherFreeTextSheet extends StatefulWidget {
  const OtherFreeTextSheet({super.key, required this.classifier});

  final PriorityClassifier classifier;

  @override
  State<OtherFreeTextSheet> createState() => _OtherFreeTextSheetState();
}

class _OtherFreeTextSheetState extends State<OtherFreeTextSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isProcessing = false;
  String? _error;
  PrioritySuggestion? _suggestion;
  EmergencyCategory? _suggestedCategory;
  List<String> _keywords = const <String>[];

  static const List<String> _keywordMap = [
    'bleeding',
    'fire',
    'smoke',
    'knife',
    'gun',
    'choking',
    'unconscious',
    'trapped',
    'accident',
    'stolen',
    'abducted',
    'kidnapped',
    'breathing',
    'difficulty',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitText() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isProcessing) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final keywords = _extractKeywords(text);
      final category = _suggestCategory(text, keywords);
      final suggestion = await widget.classifier.suggestPriority(
        category: category,
        conscious: ConsciousnessStatus.unknown,
        breathing: BreathingStatus.unknown,
        mobile: MobilityStatus.unknown,
        weaponInvolved: keywords.contains('knife') || keywords.contains('gun'),
        peopleCount: 1,
        freeTextDescription: text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isProcessing = false;
        _suggestedCategory = category;
        _keywords = keywords;
        _suggestion = suggestion;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = 'Unable to process your description. Please try again.';
      });
    }
  }

  List<String> _extractKeywords(String rawText) {
    final normalized = rawText.toLowerCase();
    final matches = <String>[];

    for (final keyword in _keywordMap) {
      if (normalized.contains(keyword)) {
        matches.add(keyword);
      }
    }

    return matches;
  }

  EmergencyCategory _suggestCategory(String rawText, List<String> keywords) {
    final normalized = rawText.toLowerCase();
    if (keywords.contains('knife') ||
        keywords.contains('gun') ||
        keywords.contains('stolen') ||
        keywords.contains('abducted') ||
        keywords.contains('kidnapped')) {
      return EmergencyCategory.security;
    }
    if (keywords.contains('fire') || keywords.contains('smoke')) {
      return EmergencyCategory.fire;
    }
    if (keywords.contains('trapped') || keywords.contains('accident')) {
      return EmergencyCategory.roadAccident;
    }
    if (keywords.contains('choking') ||
        keywords.contains('breathing') ||
        keywords.contains('unconscious') ||
        keywords.contains('bleeding')) {
      return EmergencyCategory.medical;
    }
    if (normalized.contains('abduct') || normalized.contains('kidnap')) {
      return EmergencyCategory.abduction;
    }
    return EmergencyCategory.other;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_suggestion != null && _suggestedCategory != null) {
      final confidence = (_suggestion!.confidence * 100).round();
      final suggestedCategoryLabel = _suggestedCategory!.label;
      final priorityLabel = _suggestion!.priority.label;

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Suggested response',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Based on your description, this looks like a $suggestedCategoryLabel',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Priority: $priorityLabel ($confidence% confident)',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _suggestion!.reason,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your description',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(_controller.text.trim()),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop({
                      'category': _suggestedCategory,
                      'suggestion': _suggestion,
                      'text': _controller.text.trim(),
                      'keywords': _keywords,
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Confirm & Send'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _suggestion = null;
                      _suggestedCategory = null;
                    });
                  },
                  child: const Text('Edit Description'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Describe what is happening',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              onChanged: (_) => setState(() {}),
              enabled: !_isProcessing,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Example: 'baby choking on something, can't breathe'",
                filled: true,
                fillColor: AppColors.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.warning)),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _controller.text.trim().isNotEmpty && !_isProcessing
                    ? _submitText
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Get Help'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
