import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';

import '../../../core/models/trusted_contact.dart';
import '../../../core/services/phone_number_service.dart';

class TrustedContactsScreen extends StatelessWidget {
  const TrustedContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final contacts = FirebaseFirestore.instance
        .collection('trustedContacts')
        .where('userId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: contacts,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Unable to load trusted contacts.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final contacts = snapshot.data!.docs
            .map(TrustedContact.fromDocument)
            .toList();
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Trusted Contacts',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _editContact(context, userId: userId),
                      icon: const Icon(Icons.add),
                      label: const Text('Add contact'),
                    ),
                  ],
                ),
              ),
            ),
            if (contacts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Add someone you trust to your list.')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                sliver: SliverList.separated(
                  itemCount: contacts.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    return Dismissible(
                      key: ValueKey(contact.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                      confirmDismiss: (_) => showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Remove trusted contact?'),
                          content: Text('${contact.name} will be removed from your active list.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      ),
                      onDismissed: (_) => FirebaseFirestore.instance
                          .collection('trustedContacts')
                          .doc(contact.id)
                          .update({
                            'isActive': false,
                            'updatedAt': FieldValue.serverTimestamp(),
                          }),
                      child: ListTile(
                        minVerticalPadding: 12,
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                          child: Text(_initials(contact.name)),
                        ),
                        title: Text(contact.name),
                        subtitle: Text('${contact.relationship}  ·  ${contact.phoneNumber}'),
                        trailing: IconButton(
                          tooltip: 'Edit contact',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editContact(
                            context,
                            userId: userId,
                            contact: contact,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _editContact(
    BuildContext context, {
    required String userId,
    TrustedContact? contact,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _TrustedContactForm(
        contact: contact,
        onSave: (name, phoneNumber, relationship) async {
          final reference = contact == null
              ? FirebaseFirestore.instance.collection('trustedContacts').doc()
              : FirebaseFirestore.instance.collection('trustedContacts').doc(contact.id);
          final now = FieldValue.serverTimestamp();
          if (contact == null) {
            await reference.set({
              'userId': userId,
              'name': name,
              'phoneNumber': phoneNumber,
              'relationship': relationship,
              'isActive': true,
              'createdAt': now,
              'updatedAt': now,
            });
          } else {
            await reference.update({
              'name': name,
              'phoneNumber': phoneNumber,
              'relationship': relationship,
              'updatedAt': now,
            });
          }
        },
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }
}

class _TrustedContactForm extends StatefulWidget {
  const _TrustedContactForm({required this.onSave, this.contact});

  final TrustedContact? contact;
  final Future<void> Function(String name, String phoneNumber, String relationship)
  onSave;

  @override
  State<_TrustedContactForm> createState() => _TrustedContactFormState();
}

class _TrustedContactFormState extends State<_TrustedContactForm> {
  static const _relationships = [
    'Sister',
    'Brother',
    'Friend',
    'Parent',
    'Spouse',
    'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _phoneNumberService = PhoneNumberService();
  String _countryCode = 'KE';
  String _relationship = 'Other';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    if (contact != null) {
      _nameController.text = contact.name;
      _phoneController.text = contact.phoneNumber;
      _relationship = contact.relationship;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    try {
      final phoneNumber = _phoneNumberService.formatToE164(
        _phoneController.text,
        _countryCode,
      );
      await widget.onSave(
        _nameController.text.trim(),
        phoneNumber,
        _relationship,
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save contact. Please try again.')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.contact == null ? 'Add trusted contact' : 'Edit trusted contact',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Name is required'
                  : null,
            ),
            const SizedBox(height: 12),
            InternationalPhoneNumberInput(
              textFieldController: _phoneController,
              initialValue: PhoneNumber(
                phoneNumber: widget.contact?.phoneNumber,
                isoCode: 'KE',
              ),
              maxLength: 25,
              selectorConfig: const SelectorConfig(
                selectorType: PhoneInputSelectorType.BOTTOM_SHEET,
                useEmoji: true,
              ),
              autoValidateMode: AutovalidateMode.onUserInteraction,
              inputDecoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
              ),
              onInputChanged: (number) {
                _countryCode = number.isoCode ?? 'KE';
              },
              validator: (value) => _phoneNumberService.validate(value, _countryCode),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _relationship,
              decoration: const InputDecoration(
                labelText: 'Relationship',
                border: OutlineInputBorder(),
              ),
              items: _relationships
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _relationship = value);
                }
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving...' : 'Save contact'),
            ),
          ],
        ),
      ),
    );
  }
}