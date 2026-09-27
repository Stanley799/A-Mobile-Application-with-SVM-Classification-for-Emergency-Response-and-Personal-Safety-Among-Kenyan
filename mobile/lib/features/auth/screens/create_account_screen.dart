import 'package:dlibphonenumber/dlibphonenumber.dart' as libphone;
import 'package:dropdown_search/dropdown_search.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart'
    as intl_phone;
import 'package:provider/provider.dart';

import '../../../app/auth_state_controller.dart';
import '../../../core/constants/kenya_counties.dart';
import '../models/auth_models.dart';
import '../services/auth_repository.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _phoneNumberUtil = libphone.PhoneNumberUtil.instance;

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _organizationNameController = TextEditingController();
  final _registrationNumberController = TextEditingController();

  UserRole _role = UserRole.resident;
  OrganizationType _organizationType = OrganizationType.ambulance;
  PreferredLanguage _preferredLanguage = PreferredLanguage.en;
  String _selectedCountryCode = 'KE';
  String? _selectedCounty;
  String? _gender;
  bool _consent = false;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _organizationNameController.dispose();
    _registrationNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (selected == null) {
      return;
    }
    _dobController.text =
        '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
  }

  String? _validateRegistrationNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Organization registration number is required';
    }
    final trimmed = value.trim();
    if (trimmed.length < 5) {
      return 'Registration number must be at least 5 characters';
    }
    if (trimmed.length > 30) {
      return 'Registration number is too long';
    }
    final validPattern = RegExp(r'^[A-Za-z0-9/.\-]+$');
    if (!validPattern.hasMatch(trimmed)) {
      return 'Only letters, numbers, slashes, dots, and hyphens are allowed';
    }
    return null;
  }

  String? _validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }

    try {
      final phoneNumber = _phoneNumberUtil.parse(
        value.trim(),
        _selectedCountryCode,
      );
      if (!_phoneNumberUtil.isValidNumber(phoneNumber)) {
        return 'Please enter a valid phone number for the selected country';
      }
      return null;
    } catch (_) {
      return 'Invalid phone number format';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final parsedPhoneNumber = _phoneNumberUtil.parse(
      _phoneController.text.trim(),
      _selectedCountryCode,
    );
    final formattedPhoneNumber = _phoneNumberUtil.format(
      parsedPhoneNumber,
      libphone.PhoneNumberFormat.e164,
    );

    if (!_consent) {
      setState(() {
        _submitError =
            'You must provide KDPA cross-border consent to continue.';
      });
      return;
    }

    if (_gender == null) {
      setState(() {
        _submitError = 'Please select Male or Female for gender.';
      });
      return;
    }

    setState(() {
      _submitError = null;
      _isSubmitting = true;
    });

    final authRepository = context.read<AuthRepository>();
    final authStateController = context.read<AuthStateController>();

    try {
      final dateOfBirth = DateTime.parse(_dobController.text.trim());
      final input = RegistrationInput(
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        dateOfBirth: dateOfBirth,
        gender: _gender!,
        phoneNumber: formattedPhoneNumber,
        email: _emailController.text,
        password: _passwordController.text,
        role: _role,
        preferredLanguage: _preferredLanguage,
        consentCrossBorderTransfer: _consent,
        organizationName: _role == UserRole.responder
            ? _organizationNameController.text
            : null,
        organizationType: _role == UserRole.responder
            ? _organizationType
            : null,
        registrationNumber: _role == UserRole.responder
            ? _registrationNumberController.text
            : null,
        serviceArea: _role == UserRole.responder ? _selectedCounty : null,
      );

      await authRepository.register(input);
      await authStateController.refresh();

      if (!mounted) {
        return;
      }

      context.go('/loading');
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _submitError =
              e.message ?? 'Unable to create account. Please try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitError = 'Unable to create account. Please verify your details and try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isResponder = _role == UserRole.responder;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Public Registration',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              _textField(
                controller: _firstNameController,
                label: '1. First Name',
              ),
              const SizedBox(height: 12),
              _textField(
                controller: _lastNameController,
                label: '2. Last Name',
              ),
              const SizedBox(height: 12),
              intl_phone.InternationalPhoneNumberInput(
                textFieldController: _phoneController,
                initialValue: intl_phone.PhoneNumber(isoCode: 'KE'),
                maxLength: 25,
                selectorConfig: const intl_phone.SelectorConfig(
                  selectorType: intl_phone.PhoneInputSelectorType.BOTTOM_SHEET,
                  useEmoji: true,
                ),
                autoValidateMode: AutovalidateMode.onUserInteraction,
                ignoreBlank: false,
                inputDecoration: const InputDecoration(
                  labelText: '3. Phone Number',
                  border: OutlineInputBorder(),
                ),
                onInputChanged: (number) {
                  final countryCode = number.isoCode ?? 'KE';
                  if (_selectedCountryCode != countryCode) {
                    setState(() => _selectedCountryCode = countryCode);
                  }
                },
                validator: _validatePhoneNumber,
              ),
              const SizedBox(height: 12),
              _textField(
                controller: _emailController,
                label: '4. Email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '5. Password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required.';
                  }
                  if (value.length < 8) {
                    return 'Password must be at least 8 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '6. Confirm Password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your password.';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text('7. Role', style: Theme.of(context).textTheme.titleMedium),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<UserRole>(
                  segments: const [
                    ButtonSegment(
                      value: UserRole.resident,
                      label: Text('Resident'),
                    ),
                    ButtonSegment(
                      value: UserRole.responder,
                      label: Text('Responder'),
                    ),
                  ],
                  selected: {_role},
                  onSelectionChanged: (selection) {
                    setState(() => _role = selection.first);
                  },
                ),
              ),
              if (isResponder) ...[
                const SizedBox(height: 12),
                _textField(
                  controller: _organizationNameController,
                  label: '8. Organization Name',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _registrationNumberController,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    labelText: 'Organization Registration Number',
                    helperText: 'Enter the official registration number from your Certificate of Incorporation or NGO registration certificate.',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateRegistrationNumber,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<OrganizationType>(
                  initialValue: _organizationType,
                  decoration: const InputDecoration(
                    labelText: '8. Organization Type',
                    border: OutlineInputBorder(),
                  ),
                  items: OrganizationType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.firestoreValue),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _organizationType = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownSearch<String>(
                  items: (filter, loadProps) => kenyaCounties,
                  selectedItem: _selectedCounty,
                  autoValidateMode: AutovalidateMode.onUserInteraction,
                  decoratorProps: const DropDownDecoratorProps(
                    decoration: InputDecoration(
                      labelText: 'Service Area (County)',
                      hintText: 'Search for your county',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  popupProps: PopupProps.bottomSheet(
                    showSearchBox: true,
                    searchDelay: Duration.zero,
                    searchFieldProps: const TextFieldProps(
                      decoration: InputDecoration(
                        hintText: 'Type to search...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    bottomSheetProps: const BottomSheetProps(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                    ),
                    itemBuilder: (context, item, isDisabled, isSelected) =>
                        ListTile(
                          title: Text(item),
                          trailing: isSelected
                              ? const Icon(Icons.check, color: Colors.green)
                              : null,
                        ),
                  ),
                  suffixProps: const DropdownSuffixProps(
                    clearButtonProps: ClearButtonProps(isVisible: true),
                  ),
                  onChanged: (value) {
                    setState(() => _selectedCounty = value);
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please select your service area';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<PreferredLanguage>(
                initialValue: _preferredLanguage,
                decoration: const InputDecoration(
                  labelText: '9. Preferred Language',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: PreferredLanguage.en,
                    child: Text('English'),
                  ),
                  DropdownMenuItem(
                    value: PreferredLanguage.sw,
                    child: Text('Kiswahili'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _preferredLanguage = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dobController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Date of Birth',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: _pickDate,
                  ),
                ),
                onTap: _pickDate,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Date of birth is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text('Gender', style: Theme.of(context).textTheme.titleMedium),
              FormField<String>(
                validator: (_) =>
                    _gender == null ? 'Gender is required.' : null,
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioGroup<String>(
                      groupValue: _gender,
                      onChanged: (value) {
                        setState(() => _gender = value);
                        field.didChange(value);
                      },
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Male'),
                            value: 'Male',
                          ),
                          RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Female'),
                            value: 'Female',
                          ),
                        ],
                      ),
                    ),
                    if (field.hasError)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          field.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: (value) {
                  setState(() => _consent = value ?? false);
                },
                title: const Text('10. KDPA Consent (Required)'),
                subtitle: const Text(
                  'I consent to my data being transferred to and processed on servers located outside Kenya for the purpose of emergency response, as per the Kenya Data Protection Act, 2019.',
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _submitError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Account'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () {
                          context.go('/sign-in');
                        },
                  child: const Text('Already have an account? Sign in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '$label is required.';
        }
        return null;
      },
    );
  }
}
