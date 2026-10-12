import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';

import '../../../core/services/phone_number_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/screens/password_reset_screen.dart';
import '../services/profile_repository.dart';
import 'profile_photo_crop_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.repository});
  final ProfileRepository? repository;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _phoneNumberService = PhoneNumberService();
  late final _repository = widget.repository ?? ProfileRepository();
  late final _profileStream = _repository.watchProfile();
  Map<String, dynamic> _original = {};
  String _countryCode = 'KE';
  String _preferredLanguage = 'en';
  bool _editing = false;
  bool _saving = false;
  bool _writing = false;
  bool _photoBusy = false;
  String? _loadedPhotoPath;
  Future<Uint8List?>? _photoFuture;
  bool get _busy => _saving || _photoBusy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverPhoto());
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _notify(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _startEditing(Map<String, dynamic> data) {
    setState(() {
      _original = Map<String, dynamic>.from(data);
      _firstNameController.text = data['firstName'] as String? ?? '';
      _lastNameController.text = data['lastName'] as String? ?? '';
      _phoneController.text = data['phoneNumber'] as String? ?? '';
      _preferredLanguage = data['preferredLanguage'] as String? ?? 'en';
      _countryCode = 'KE';
      _editing = true;
    });
  }

  Future<bool> _confirm(String title, Widget content, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: content),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(action),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _discard() async {
    if (_busy) return;
    final confirmed = await _confirm(
      'Discard changes?',
      const Text('Your unsaved profile changes will be lost.'),
      'Discard Changes',
    );
    if (confirmed && mounted) setState(() => _editing = false);
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final values = <String, dynamic>{
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'phoneNumber': _phoneNumberService.formatToE164(
          _phoneController.text,
          _countryCode,
        ),
        'preferredLanguage': _preferredLanguage,
      };
      final changes = Map<String, dynamic>.fromEntries(
        values.entries.where((entry) => entry.value != _original[entry.key]),
      );
      if (changes.isEmpty) {
        setState(() => _editing = false);
        _notify('No profile changes to save.');
        return;
      }
      const labels = {
        'firstName': 'First name',
        'lastName': 'Last name',
        'phoneNumber': 'Phone number',
        'preferredLanguage': 'Preferred language',
      };
      String display(dynamic value) => value == 'en'
          ? 'English'
          : value == 'sw'
          ? 'Kiswahili'
          : value.toString();
      final confirmed = await _confirm(
        'Save profile changes?',
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: changes.entries
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labels[entry.key]!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('Current: ${display(_original[entry.key])}'),
                      Text('New: ${display(entry.value)}'),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        'Save Changes',
      );
      if (!confirmed || !mounted) return;
      setState(() => _writing = true);
      await _repository.saveDetails(changes, _original);
      if (mounted) setState(() => _editing = false);
      _notify('Profile updated.');
    } on StateError catch (_) {
      _notify(
        'Your profile changed elsewhere. Cancel editing and reload before saving.',
      );
    } catch (_) {
      _notify(
        'Unable to update profile. Your edits have been kept. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _writing = false;
        });
      }
    }
  }

  Future<void> _recoverPhoto() async {
    try {
      final recovered = await _repository.recoverLostPhoto();
      if (recovered != null && mounted && !_busy) {
        setState(() => _photoBusy = true);
        await _cropAndSave(recovered);
      }
    } catch (_) {
      _notify('Unable to recover the selected photo. Please select it again.');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _cropAndSave(Uint8List bytes) async {
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => ProfilePhotoCropScreen(bytes: bytes)),
    );
    if (cropped == null || !mounted) return;
    await _repository.savePhoto(cropped);
    _notify('Profile photo updated.');
  }

  Future<void> _photoActions(String? currentPath) async {
    if (_busy || _editing) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose photo'),
            onTap: () => Navigator.of(sheetContext).pop('gallery'),
          ),
          if (_repository.supportsCamera)
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
          if (currentPath != null) ...[
            ListTile(
              leading: const Icon(Icons.crop),
              title: const Text('Adjust current photo'),
              onTap: () => Navigator.of(sheetContext).pop('crop'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove photo'),
              onTap: () => Navigator.of(sheetContext).pop('remove'),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Cancel'),
            onTap: () => Navigator.of(sheetContext).pop(),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      if (action == 'remove') {
        final confirmed = await _confirm(
          'Remove profile photo?',
          const Text('Your profile will show your initials instead.'),
          'Remove Photo',
        );
        if (confirmed && mounted) {
          await _repository.removePhoto();
          _notify('Profile photo removed.');
        }
      } else {
        final bytes = action == 'crop'
            ? await _repository.loadPhoto(currentPath!)
            : await _repository.pickPhoto(
                action == 'camera' ? ImageSource.camera : ImageSource.gallery,
              );
        if (bytes != null && mounted) await _cropAndSave(bytes);
      }
    } on FormatException catch (error) {
      _notify(error.message);
    } catch (_) {
      _notify(
        'Unable to update your photo. Check photo permissions and your connection, then try again.',
      );
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    final confirmed = await _confirm(
      'Sign out?',
      Text(
        _editing
            ? 'Your unsaved profile changes will be discarded.'
            : 'You will need to sign in again to access your account.',
      ),
      'Sign Out',
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await _repository.signOut();
    } catch (_) {
      _notify('Unable to sign out. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _profileStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Unable to load your profile. Please try again.'),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(
            child: Text('Your profile is unavailable. Please sign in again.'),
          );
        }
        final path = data['profilePhotoPath'] as String?;
        if (path != _loadedPhotoPath) {
          _loadedPhotoPath = path;
          _photoFuture = path == null ? null : _repository.loadPhoto(path);
        }
        final firstName = data['firstName'] as String? ?? '';
        final email = _repository.email ?? data['email'] as String? ?? '';
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Profile',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    if (!_editing)
                      IconButton(
                        tooltip: 'Edit profile',
                        onPressed: _busy ? null : () => _startEditing(data),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: FutureBuilder<Uint8List?>(
                    key: ValueKey(path),
                    future: _photoFuture,
                    builder: (context, photo) => Column(
                      children: [
                        Semantics(
                          label: 'Profile photo',
                          image: true,
                          child: CircleAvatar(
                            radius: 48,
                            backgroundColor: AppColors.brandLight,
                            backgroundImage: photo.hasData
                                ? MemoryImage(photo.data!)
                                : null,
                            child: photo.hasData
                                ? null
                                : Text(
                                    firstName.isEmpty
                                        ? '?'
                                        : firstName.characters.first
                                              .toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 32,
                                      color: AppColors.brand,
                                    ),
                                  ),
                          ),
                        ),
                        if (photo.connectionState == ConnectionState.waiting &&
                            path != null)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(),
                          ),
                        if (photo.hasError)
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => setState(
                                    () => _photoFuture = _repository.loadPhoto(
                                      path!,
                                    ),
                                  ),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reload photo'),
                          ),
                      ],
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy || _editing
                      ? null
                      : () => _photoActions(path),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                    _photoBusy
                        ? 'Updating photo...'
                        : path == null
                        ? 'Add photo'
                        : 'Edit photo',
                  ),
                ),
                Center(
                  child: Text(
                    '$firstName ${data['lastName'] ?? ''}'.trim(),
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Center(child: Text(email, textAlign: TextAlign.center)),
                const SizedBox(height: 24),
                if (_editing)
                  AbsorbPointer(
                    absorbing: _busy,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _firstNameController,
                            decoration: const InputDecoration(
                              labelText: 'First name',
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (value) =>
                                _validateName(value, 'First name'),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _lastNameController,
                            decoration: const InputDecoration(
                              labelText: 'Last name',
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (value) =>
                                _validateName(value, 'Last name'),
                          ),
                          const SizedBox(height: 16),
                          InternationalPhoneNumberInput(
                            textFieldController: _phoneController,
                            initialValue: PhoneNumber(
                              phoneNumber:
                                  _original['phoneNumber'] as String? ?? '',
                              isoCode: 'KE',
                            ),
                            maxLength: 25,
                            selectorConfig: const SelectorConfig(
                              selectorType: PhoneInputSelectorType.BOTTOM_SHEET,
                              useEmoji: true,
                            ),
                            inputDecoration: const InputDecoration(
                              labelText: 'Phone number',
                            ),
                            onInputChanged: (number) =>
                                _countryCode = number.isoCode ?? 'KE',
                            validator: (value) => _phoneNumberService.validate(
                              value,
                              _countryCode,
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _preferredLanguage,
                            decoration: const InputDecoration(
                              labelText: 'Preferred language',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'en',
                                child: Text('English'),
                              ),
                              DropdownMenuItem(
                                value: 'sw',
                                child: Text('Kiswahili'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _preferredLanguage = value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  _detail('First name', firstName),
                  _detail('Last name', data['lastName'] as String? ?? ''),
                  _detail('Phone number', data['phoneNumber'] as String? ?? ''),
                  _detail(
                    'Preferred language',
                    data['preferredLanguage'] == 'sw' ? 'Kiswahili' : 'English',
                  ),
                ],
                _detail('Email', email, locked: true),
                _detail(
                  'Role',
                  data['role'] as String? ?? 'Resident',
                  locked: true,
                ),
                _detail(
                  'Account status',
                  data['accountStatus'] as String? ?? 'Active',
                  locked: true,
                ),
                if (_editing) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _writing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_writing ? 'Saving...' : 'Review Changes'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _discard,
                    icon: const Icon(Icons.close),
                    label: const Text('Discard Changes'),
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_reset),
                  title: const Text('Reset password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy || _editing || _repository.email == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PasswordResetScreen(
                              initialEmail: _repository.email!,
                              lockEmail: true,
                            ),
                          ),
                        ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  onTap: _busy ? null : _signOut,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _validateName(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    if (value.trim().length > 100) {
      return '$label must be 100 characters or fewer';
    }
    return null;
  }

  Widget _detail(String label, String value, {bool locked = false}) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(value),
    trailing: locked ? const Icon(Icons.lock_outline, size: 18) : null,
  );
}
