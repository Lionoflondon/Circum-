import 'dart:ui';

import 'package:flutter/material.dart';

/// Lives below the page, rather than covering its navigation or payment actions.
class CookieConsentPanel extends StatelessWidget {
  final VoidCallback onReject;
  final VoidCallback onCustomise;
  final VoidCallback onAccept;

  const CookieConsentPanel({
    super.key,
    required this.onReject,
    required this.onCustomise,
    required this.onAccept,
  });

  static const message =
      'We use essential cookies to keep CIRCUM running securely. With your permission, we also use optional cookies to improve your experience and understand how our website is used.';
  static const choices =
      'You can accept, reject or customise optional cookies at any time.';

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 1120,
              maxHeight: MediaQuery.sizeOf(context).height *
                  (MediaQuery.sizeOf(context).height < 600 ? .65 : .48),
            ),
            child: Semantics(
              container: true,
              label: 'Cookie consent',
              child: FocusTraversalGroup(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xff101827).withValues(alpha: .96),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color:
                                const Color(0xff789cff).withValues(alpha: .55)),
                        gradient: const LinearGradient(
                          colors: [Color(0xf5101827), Color(0xf5192038)],
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: LayoutBuilder(builder: (context, constraints) {
                          final copy = Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                  header: true,
                                  child: const Text('Your privacy matters.',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          height: 1.2,
                                          fontWeight: FontWeight.w700))),
                              const SizedBox(height: 8),
                              const Text(message,
                                  style: TextStyle(
                                      color: Color(0xffe0e7f4),
                                      fontSize: 14,
                                      height: 1.4)),
                              const SizedBox(height: 6),
                              const Text(choices,
                                  style: TextStyle(
                                      color: Color(0xffe0e7f4),
                                      fontSize: 14,
                                      height: 1.4)),
                            ],
                          );
                          final buttonStyle = OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0xff253656),
                            side: const BorderSide(color: Color(0xff99b6ff)),
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            textStyle: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          );
                          Widget button(String label, VoidCallback action) =>
                              OutlinedButton(
                                  style: buttonStyle,
                                  onPressed: action,
                                  child: Text(label));
                          final actions =
                              Wrap(spacing: 8, runSpacing: 8, children: [
                            SizedBox(
                                width: 148,
                                child: button('Reject optional', onReject)),
                            SizedBox(
                                width: 148,
                                child: button('Customise', onCustomise)),
                            SizedBox(
                                width: 148,
                                child: button('Accept all', onAccept)),
                          ]);
                          if (constraints.maxWidth >= 1000 &&
                              MediaQuery.textScalerOf(context).scale(14) <=
                                  18) {
                            return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(child: copy),
                                  const SizedBox(width: 24),
                                  SizedBox(width: 460, child: actions),
                                ]);
                          }
                          return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                copy,
                                const SizedBox(height: 16),
                                if (constraints.maxWidth < 480)
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        button('Reject optional', onReject),
                                        const SizedBox(height: 8),
                                        button('Customise', onCustomise),
                                        const SizedBox(height: 8),
                                        button('Accept all', onAccept),
                                      ])
                                else
                                  actions,
                              ]);
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
