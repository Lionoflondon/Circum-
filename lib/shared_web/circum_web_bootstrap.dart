import 'package:flutter/material.dart';

import 'circum_web_shell.dart';

class CircumWebBootstrap extends StatefulWidget {
  const CircumWebBootstrap({
    super.key,
    required this.section,
    required this.initializer,
    required this.appBuilder,
    this.showSectionNavigation = true,
    this.timeout = const Duration(seconds: 20),
  });

  final CircumWebSection section;
  final Future<void> Function() initializer;
  final WidgetBuilder appBuilder;
  final bool showSectionNavigation;
  final Duration timeout;

  @override
  State<CircumWebBootstrap> createState() => _CircumWebBootstrapState();
}

class _CircumWebBootstrapState extends State<CircumWebBootstrap> {
  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _error = null);
    try {
      await widget.initializer().timeout(widget.timeout);
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
        body: CircumWebShell(
          section: widget.section,
          darkMode: true,
          onToggleTheme: () {},
          showSectionNavigation: widget.showSectionNavigation,
          child: _error == null
              ? const _WebPageSkeleton()
              : _WebStartupError(onRetry: _initialize),
        ),
      ),
    );
  }
}

class _WebPageSkeleton extends StatelessWidget {
  const _WebPageSkeleton();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SkeletonBlock(height: 44, widthFactor: .46),
                const SizedBox(height: 22),
                const _SkeletonBlock(height: 188),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 720;
                    final cards = List.generate(
                      3,
                      (_) => const Expanded(
                        child: _SkeletonBlock(height: 122),
                      ),
                    );
                    if (stacked) {
                      return Column(
                        children: [
                          for (var index = 0; index < 3; index++) ...[
                            const _SkeletonBlock(height: 96),
                            if (index < 2) const SizedBox(height: 12),
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        cards[0],
                        const SizedBox(width: 14),
                        cards[1],
                        const SizedBox(width: 14),
                        cards[2],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height, this.widthFactor = 1});

  final double height;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x1FFFFFFF)),
        ),
      ),
    );
  }
}

class _WebStartupError extends StatelessWidget {
  const _WebStartupError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xF20D111C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x1FFFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFF87171), size: 32),
            const SizedBox(height: 14),
            const Text('Something went wrong.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
