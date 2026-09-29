import 'package:flutter/material.dart';

import '../../sender_mobile/sender_wallet.dart';

/// Compatibility entry point for the older Account navigation tree.
///
/// Wallet authority and presentation live in the Sender Wallet surface. The
/// legacy route delegates there so it cannot expose a stale, non-interactive
/// secondary or competing balance/payment implementation.
class WalletView extends StatelessWidget {
  const WalletView({super.key});

  @override
  Widget build(BuildContext context) => const SenderWalletView();
}
