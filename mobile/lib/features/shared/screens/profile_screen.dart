import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/phone_number_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _phoneNumberService = PhoneNumberService();
  String _countryCode = 'KE';
  String _preferredLanguage = 'en';
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Unable to load your profile.'));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!.data()!;
        if (!_initialized) {
          _firstNameController.text = data['firstName'] as String? ?? '';
          _lastNameController.text = data['lastName'] as String? ?? '';
          _phoneController.text = data['phoneNumber'] as String? ?? '';
          _preferredLanguage = data['preferredLanguage'] as String? ?? 'en';
          _initialized = true;
        }

        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            children: [
              Text('Profile', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xl),
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.brandLight,
                child: Text(
                  _firstNameController.text.isEmpty
                      ? '?'
                      : _firstNameController.text.characters.first
                            .toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.brand,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Text(
                  '${_firstNameController.text} ${_lastNameController.text}'
                      .trim(),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontSize: 20),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Text(
                  data['email'] as String? ?? user.email ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadows.card,
                ),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _firstNameController,
                      decoration: _fieldDecoration('First Name'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'First name is required'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _lastNameController,
                      decoration: _fieldDecoration('Last Name'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Last name is required'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    InternationalPhoneNumberInput(
                      textFieldController: _phoneController,
                      initialValue: PhoneNumber(
                        phoneNumber: data['phoneNumber'] as String? ?? '',
                        isoCode: 'KE',
                      ),
                      maxLength: 25,
                      selectorConfig: const SelectorConfig(
                        selectorType: PhoneInputSelectorType.BOTTOM_SHEET,
                        useEmoji: true,
                      ),
                      autoValidateMode: AutovalidateMode.onUserInteraction,
                      inputDecoration: _fieldDecoration('Phone Number'),
                      onInputChanged: (number) =>
                          _countryCode = number.isoCode ?? 'KE',
                      validator: (value) =>
                          _phoneNumberService.validate(value, _countryCode),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: _preferredLanguage,
                      decoration: _fieldDecoration('Preferred Language'),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'sw', child: Text('Kiswahili')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _preferredLanguage = value);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _readOnlyValue(
                      context,
                      'Email',
                      data['email'] as String? ?? user.email ?? '',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _readOnlyValue(
                      context,
                      'Role',
                      data['role'] as String? ?? 'Resident',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _readOnlyValue(
                      context,
                      'Account Status',
                      data['accountStatus'] as String? ?? 'Active',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _saving ? null : () => _save(user.uid),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.brand,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.surface,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: FirebaseAuth.instance.signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _readOnlyValue(BuildContext context, String label, String value) {
    final isRole = label == 'Role';
    final isAccountStatus = label == 'Account Status';
    final chipColor = isAccountStatus
        ? AppColors.successLight
        : AppColors.neutralLight;
    final textColor = isAccountStatus
        ? AppColors.success
        : AppColors.textSecondary;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: label == 'Email' ? 'Contact support to change' : null,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        suffixIcon: label == 'Email'
            ? const Icon(Icons.lock_outline, size: 18)
            : null,
      ),
      child: isRole || isAccountStatus
          ? Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: chipColor,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          : Text(value),
    );
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
    filled: true,
    fillColor: AppColors.background,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: AppColors.info),
    ),
  );

  Future<void> _save(String userId) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    try {
      final phoneNumber = _phoneNumberService.formatToE164(
        _phoneController.text,
        _countryCode,
      );
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'phoneNumber': phoneNumber,
        'preferredLanguage': _preferredLanguage,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update profile. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
