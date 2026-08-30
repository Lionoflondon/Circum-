import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'sender_account_closure.dart';

class SenderAccountClosureDialog {
  static Future<bool> show(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close your account?'),
        content: const Text(
          'This closes your CIRCUM account. Active deliveries, pending '
          'payments and open disputes must be resolved first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep account'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;

    final closure = SenderAccountClosure();
    try {
      final provider = await _selectProvider(context, closure);
      if (provider == null || !context.mounted) return false;
      await _closeWithProvider(context, closure, provider);
      return true;
    } on SenderAccountClosureException catch (error) {
      if (context.mounted) _showError(context, error.message);
    } catch (_) {
      if (context.mounted) {
        _showError(
            context, 'Your account could not be closed. Please try again.');
      }
    }
    return false;
  }

  static Future<SenderReauthenticationProvider?> _selectProvider(
    BuildContext context,
    SenderAccountClosure closure,
  ) async {
    final providers = closure.availableProviders;
    if (providers.isEmpty) {
      throw const SenderAccountClosureException(
        'Sign in again before closing your account.',
      );
    }
    if (providers.length == 1) return providers.single;
    return showModalBottomSheet<SenderReauthenticationProvider>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: providers
              .map((provider) => ListTile(
                    title: Text(_providerLabel(provider)),
                    onTap: () => Navigator.pop(context, provider),
                  ))
              .toList(),
        ),
      ),
    );
  }

  static Future<void> _closeWithProvider(
    BuildContext context,
    SenderAccountClosure closure,
    SenderReauthenticationProvider provider,
  ) async {
    switch (provider) {
      case SenderReauthenticationProvider.emailPassword:
        final password = await _requestText(
          context,
          title: 'Confirm your password',
          label: 'Password',
          obscure: true,
        );
        if (password == null) {
          throw const SenderAccountClosureException(
              'Account closure was cancelled.');
        }
        await closure.closeWithEmailPassword(password);
      case SenderReauthenticationProvider.google:
        await closure.closeWithGoogle();
      case SenderReauthenticationProvider.apple:
        await closure.closeWithApple();
      case SenderReauthenticationProvider.phone:
        await closure.closeWithPhoneCredential(await _phoneCredential(context));
    }
  }

  static Future<PhoneAuthCredential> _phoneCredential(
      BuildContext context) async {
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    if (phone == null || phone.isEmpty) {
      throw const SenderAccountClosureException(
        'Sign in again before closing your account.',
      );
    }
    final result = Completer<PhoneAuthCredential>();
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (credential) {
        if (!result.isCompleted) result.complete(credential);
      },
      verificationFailed: (_) {
        if (!result.isCompleted) {
          result.completeError(const SenderAccountClosureException(
            'Phone confirmation could not be completed. Please try again.',
          ));
        }
      },
      codeSent: (verificationId, _) async {
        final code = await _requestText(
          context,
          title: 'Confirm your phone',
          label: 'Verification code',
          keyboardType: TextInputType.number,
        );
        if (!context.mounted) {
          if (!result.isCompleted) {
            result.completeError(const SenderAccountClosureException(
              'Phone confirmation was cancelled.',
            ));
          }
          return;
        }
        if (code == null || code.trim().isEmpty) {
          if (!result.isCompleted) {
            result.completeError(const SenderAccountClosureException(
              'Account closure was cancelled.',
            ));
          }
          return;
        }
        if (!result.isCompleted) {
          result.complete(PhoneAuthProvider.credential(
            verificationId: verificationId,
            smsCode: code.trim(),
          ));
        }
      },
      codeAutoRetrievalTimeout: (_) {
        if (!result.isCompleted) {
          result.completeError(const SenderAccountClosureException(
            'Phone confirmation timed out. Please try again.',
          ));
        }
      },
    );
    return result.future.timeout(SenderAccountClosure.operationTimeout);
  }

  static Future<String?> _requestText(
    BuildContext context, {
    required String title,
    required String label,
    bool obscure = false,
    TextInputType? keyboardType,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  static String _providerLabel(SenderReauthenticationProvider provider) {
    switch (provider) {
      case SenderReauthenticationProvider.emailPassword:
        return 'Confirm with password';
      case SenderReauthenticationProvider.google:
        return 'Continue with Google';
      case SenderReauthenticationProvider.apple:
        return 'Continue with Apple';
      case SenderReauthenticationProvider.phone:
        return 'Confirm with phone';
    }
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
