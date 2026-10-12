import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_repository.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({
    super.key,
    this.initialEmail = '',
    this.lockEmail = false,
    this.sendResetEmail,
  });

  final String initialEmail;
  final bool lockEmail;
  final Future<void> Function(String email)? sendResetEmail;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  bool _sending = false;
  bool _sent = false;
  String? _error;
  int _remainingSeconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    _remainingSeconds = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remainingSeconds -= 1);
      if (_remainingSeconds == 0) timer.cancel();
    });
  }

  Future<void> _send() async {
    if (_sending || _remainingSeconds > 0 || !_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final send =
          widget.sendResetEmail ??
          context.read<AuthRepository>().requestPasswordReset;
      await send(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _sent = true;
        _startCooldown();
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'too-many-requests' =>
            'Too many requests. Please wait before trying again.',
          'invalid-email' => 'Please enter a valid email address.',
          'network-request-failed' => 'Check your connection and try again.',
          _ => 'Unable to send a reset link. Please try again.',
        };
        if (error.code == 'too-many-requests') _startCooldown();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to send a reset link. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                _sent ? Icons.mark_email_read_outlined : Icons.lock_reset,
                size: 48,
              ),
              const SizedBox(height: 24),
              Text(
                _sent ? 'Check your email' : 'Reset your password',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                _sent
                    ? 'If an account exists for this email, a password reset link will be sent. Check your inbox and spam folder.'
                    : 'A secure reset link will be sent to your account email address.',
              ),
              const SizedBox(height: 24),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _emailController,
                  readOnly: widget.lockEmail || _sent,
                  enabled: !_sending,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(email)) {
                      return 'Please enter a valid email address.';
                    }
                    return null;
                  },
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _sending || _remainingSeconds > 0 ? null : _send,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(
                  _sending
                      ? 'Sending...'
                      : _remainingSeconds > 0
                      ? 'Resend in ${_remainingSeconds}s'
                      : _sent
                      ? 'Resend reset link'
                      : 'Send reset link',
                ),
              ),
              if (_sent && !widget.lockEmail)
                TextButton(
                  onPressed: _sending
                      ? null
                      : () => setState(() => _sent = false),
                  child: const Text('Use a different email'),
                ),
              TextButton(
                onPressed: _sending ? null : () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
