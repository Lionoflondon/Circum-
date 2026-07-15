import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import 'public_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    _PublicStartup(
      initializer: _initializePublicFirebase,
      appBuilder: (_) => const CircumPublicWebsiteApp(),
    ),
  );
}

Future<void> _initializePublicFirebase() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app') rethrow;
  }
}

class _PublicStartup extends StatefulWidget {
  const _PublicStartup({
    required this.initializer,
    required this.appBuilder,
  });

  final Future<void> Function() initializer;
  final WidgetBuilder appBuilder;

  @override
  State<_PublicStartup> createState() => _PublicStartupState();
}

class _PublicStartupState extends State<_PublicStartup> {
  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _ready = false;
    });
    try {
      await widget.initializer().timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.appBuilder(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF07090F),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CIRCUM',
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
                  const Text('Starting Circum'),
                ] else ...[
                  const Icon(Icons.error_outline, color: Color(0xFFF87171)),
                  const SizedBox(height: 16),
                  const Text('Something went wrong.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
