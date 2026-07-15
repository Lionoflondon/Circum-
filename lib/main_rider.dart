import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'web_sender_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _RiderStartup());
}

class _RiderStartup extends StatefulWidget {
  const _RiderStartup();

  @override
  State<_RiderStartup> createState() => _RiderStartupState();
}

class _RiderStartupState extends State<_RiderStartup> {
  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _error = null;
      _ready = false;
    });
    try {
      try {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.web)
            .timeout(const Duration(seconds: 20));
      } on FirebaseException catch (error) {
        if (error.code != 'duplicate-app') rethrow;
      }
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const CircumRiderApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF030712),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'CIRCUM RIDER',
                      style: TextStyle(
                        color: Color(0xFF3B82F6),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (_error == null) ...[
                      const CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF3B82F6),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Starting Rider',
                        style: TextStyle(
                          color: Color(0xFFF5F7FB),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else ...[
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFF87171),
                        size: 34,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Something went wrong.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFF5F7FB),
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'We could not start Rider. Check your connection and try again.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Color(0xFF9CA8B8), height: 1.45),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _initialize,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
