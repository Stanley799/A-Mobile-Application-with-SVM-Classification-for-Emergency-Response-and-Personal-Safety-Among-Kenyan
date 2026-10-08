import 'package:flutter/material.dart';

import '../../../core/models/emergency_enums.dart';
import '../../../core/services/priority_classifier.dart';
import '../../../core/theme/app_theme.dart';

class _QuestionOption<T> {
  const _QuestionOption({required this.label, required this.value});

  final String label;
  final T value;
}

class _QuestionConfig {
  const _QuestionConfig({
    required this.id,
    required this.title,
    required this.options,
  });

  final String id;
  final String title;
  final List<_QuestionOption<dynamic>> options;
}

/// Branching triage sheet that asks the universal and category-specific
/// questions then returns the suggested priority along with the captured answers.
class TriageQuestionSheet extends StatefulWidget {
  const TriageQuestionSheet({
    super.key,
    required this.category,
    required this.classifier,
  });

  final EmergencyCategory category;
  final PriorityClassifier classifier;

  @override
  State<TriageQuestionSheet> createState() => _TriageQuestionSheetState();
}

class _TriageQuestionSheetState extends State<TriageQuestionSheet> {
  late final List<_QuestionConfig> _questions;
  final Map<String, dynamic> _answers = {};
  int _currentIndex = 0;
  bool _isProcessing = false;
  bool _isReviewing = false;
  String? _error;
  PrioritySuggestion? _suggestion;

  @override
  void initState() {
    super.initState();
    _questions = _buildQuestions(widget.category);
  }

  List<_QuestionConfig> _buildQuestions(EmergencyCategory category) {
    final questions = <_QuestionConfig>[
      _QuestionConfig(
        id: 'conscious',
        title: 'Is the person conscious?',
        options: const [
          _QuestionOption(label: 'Yes', value: ConsciousnessStatus.yes),
          _QuestionOption(label: 'No', value: ConsciousnessStatus.no),
          _QuestionOption(
            label: 'Not sure',
            value: ConsciousnessStatus.unknown,
          ),
        ],
      ),
      _QuestionConfig(
        id: 'breathing',
        title: 'Are they breathing normally?',
        options: const [
          _QuestionOption(label: 'Yes', value: BreathingStatus.yes),
          _QuestionOption(label: 'No', value: BreathingStatus.no),
          _QuestionOption(label: 'Not sure', value: BreathingStatus.unknown),
        ],
      ),
    ];

    switch (category) {
      case EmergencyCategory.medical:
        questions.addAll([
          const _QuestionConfig(
            id: 'severeBleeding',
            title: 'Is there severe bleeding?',
            options: [
              _QuestionOption(label: 'Yes', value: true),
              _QuestionOption(label: 'No', value: false),
              _QuestionOption(label: 'Not sure', value: null),
            ],
          ),
          const _QuestionConfig(
            id: 'chestPain',
            title: 'Is there chest pain?',
            options: [
              _QuestionOption(label: 'Yes', value: true),
              _QuestionOption(label: 'No', value: false),
              _QuestionOption(label: 'Not sure', value: null),
            ],
          ),
        ]);
        break;
      case EmergencyCategory.roadAccident:
        questions.addAll([
          const _QuestionConfig(
            id: 'trapped',
            title: 'Is anyone trapped?',
            options: [
              _QuestionOption(label: 'Yes', value: MobilityStatus.trapped),
              _QuestionOption(label: 'No', value: MobilityStatus.mobile),
              _QuestionOption(label: 'Not sure', value: MobilityStatus.unknown),
            ],
          ),
          const _QuestionConfig(
            id: 'vehicleCount',
            title: 'How many vehicles are involved?',
            options: [
              _QuestionOption(label: '1', value: 1),
              _QuestionOption(label: '2', value: 2),
              _QuestionOption(label: '3+', value: 3),
            ],
          ),
        ]);
        break;
      case EmergencyCategory.fire:
        questions.addAll([
          const _QuestionConfig(
            id: 'trapped',
            title: 'Is anyone trapped inside?',
            options: [
              _QuestionOption(label: 'Yes', value: MobilityStatus.trapped),
              _QuestionOption(label: 'No', value: MobilityStatus.mobile),
              _QuestionOption(label: 'Not sure', value: MobilityStatus.unknown),
            ],
          ),
          const _QuestionConfig(
            id: 'smokeInhalation',
            title: 'Is there smoke inhalation?',
            options: [
              _QuestionOption(label: 'Yes', value: true),
              _QuestionOption(label: 'No', value: false),
              _QuestionOption(label: 'Not sure', value: null),
            ],
          ),
        ]);
        break;
      case EmergencyCategory.security:
        questions.addAll([
          const _QuestionConfig(
            id: 'weaponInvolved',
            title: 'Is a weapon involved?',
            options: [
              _QuestionOption(label: 'Yes', value: true),
              _QuestionOption(label: 'No', value: false),
              _QuestionOption(label: 'Not sure', value: null),
            ],
          ),
          const _QuestionConfig(
            id: 'sceneSafe',
            title: 'Is the scene safe?',
            options: [
              _QuestionOption(label: 'Yes', value: true),
              _QuestionOption(label: 'No', value: false),
              _QuestionOption(label: 'Not sure', value: null),
            ],
          ),
        ]);
        break;
      case EmergencyCategory.abduction:
        questions.addAll([
          const _QuestionConfig(
            id: 'withAbductor',
            title: 'Is the victim still with the abductor?',
            options: [
              _QuestionOption(label: 'Yes', value: true),
              _QuestionOption(label: 'No', value: false),
              _QuestionOption(label: 'Not sure', value: null),
            ],
          ),
        ]);
        break;
      case EmergencyCategory.other:
      case EmergencyCategory.unknown:
        break;
    }

    questions.add(
      const _QuestionConfig(
        id: 'peopleCount',
        title: 'How many people are affected?',
        options: [
          _QuestionOption(label: '1', value: 1),
          _QuestionOption(label: '2', value: 2),
          _QuestionOption(label: '3+', value: 3),
        ],
      ),
    );

    return questions;
  }

  _QuestionConfig get _currentQuestion => _questions[_currentIndex];
  bool get _isQuestionAnswered => _answers.containsKey(_currentQuestion.id);
  bool get _isLastQuestion => _currentIndex == _questions.length - 1;

  Future<void> _handleAnswerSelection(_QuestionOption<dynamic> option) async {
    if (_isProcessing) return;
    setState(() {
      _answers[_currentQuestion.id] = option.value;
      _error = null;
    });
    if (option.label == 'Not sure') await _continue();
  }

  Future<void> _continue() async {
    if (!_isQuestionAnswered || _isProcessing) {
      return;
    }

    if (_isReviewing) {
      await _generateSuggestion();
      return;
    }

    if (_isLastQuestion) {
      await _generateSuggestion();
      return;
    }

    setState(() {
      _currentIndex += 1;
    });
  }

  Future<void> _generateSuggestion() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    final current =
        _answers['conscious'] as ConsciousnessStatus? ??
        ConsciousnessStatus.unknown;
    final breathing =
        _answers['breathing'] as BreathingStatus? ?? BreathingStatus.unknown;
    final mobileStatus =
        _answers['trapped'] as MobilityStatus? ?? MobilityStatus.unknown;
    final weaponInvolved = (_answers['weaponInvolved'] as bool?) ?? false;
    final peopleCount = (_answers['peopleCount'] as int?) ?? 1;

    try {
      final suggestion = await widget.classifier.suggestPriority(
        category: widget.category,
        conscious: current,
        breathing: breathing,
        mobile: mobileStatus,
        weaponInvolved: weaponInvolved,
        peopleCount: peopleCount,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _suggestion = suggestion;
        _isProcessing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = 'Unable to suggest a priority. Please try again.';
      });
    }
  }

  void _reviewAnswers() {
    setState(() {
      _isReviewing = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_suggestion != null) {
      final priorityLabel = _suggestion!.priority.label;
      final confidence = (_suggestion!.confidence * 100).round();

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
                _isReviewing ? 'Review answers' : 'Suggested priority',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontSize: 22),
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
                      '$priorityLabel priority',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Estimated confidence: $confidence%',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _suggestion!.reason,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isReviewing) ...[
                const SizedBox(height: 12),
                ..._questions.asMap().entries.map((entry) {
                  final question = entry.value;
                  final answerLabel = question.options
                      .firstWhere(
                        (option) => option.value == _answers[question.id],
                      )
                      .label;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(question.title),
                    subtitle: Text(answerLabel),
                    trailing: IconButton(
                      tooltip: 'Edit answer',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => setState(() {
                        _currentIndex = entry.key;
                        _suggestion = null;
                      }),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop({
                      'suggestion': _suggestion,
                      'triageAnswers': Map<String, dynamic>.from(_answers),
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
                  onPressed: _isReviewing
                      ? () => setState(() => _isReviewing = false)
                      : _reviewAnswers,
                  child: Text(
                    _isReviewing ? 'Back to Priority' : 'Review Answers',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final currentQuestion = _currentQuestion;
    final currentAnswer = _answers[currentQuestion.id];

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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.category.label,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Question ${_currentIndex + 1} of ${_questions.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                currentQuestion.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...currentQuestion.options.map((option) {
              final isSelected =
                  _isQuestionAnswered && currentAnswer == option.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Semantics(
                  selected: isSelected,
                  button: true,
                  child: InkWell(
                    onTap: _isProcessing
                        ? null
                        : () => _handleAnswerSelection(option),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.brand
                              : AppColors.divider,
                        ),
                        color: isSelected
                            ? AppColors.brandLight
                            : AppColors.surface,
                      ),
                      child: Text(
                        option.label,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.brand
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 18),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.warning)),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isQuestionAnswered && !_isProcessing
                    ? _continue
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _isReviewing
                            ? 'Save Answer'
                            : _isLastQuestion
                            ? 'Get Priority Suggestion'
                            : 'Next',
                      ),
              ),
            ),
            if (_currentIndex > 0 && !_isReviewing)
              TextButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => setState(() => _currentIndex -= 1),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
          ],
        ),
      ),
    );
  }
}
