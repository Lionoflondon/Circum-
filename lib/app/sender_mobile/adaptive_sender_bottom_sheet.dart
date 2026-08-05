import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_system/sender_design_system.dart';

/// Shared mobile sheet mechanics for Sender booking and tracking surfaces.
/// The child owns its content and presentation; this widget owns only sizing,
/// snapping, and per-flow preference persistence.
class AdaptiveSenderBottomSheet extends StatefulWidget {
  final String persistenceId;
  final Widget child;
  final bool desktopPanel;
  final bool wrapInGlass;
  final Alignment desktopAlignment;
  final double desktopWidthFraction;
  final double desktopMaxWidth;
  final double desktopHeightFraction;

  const AdaptiveSenderBottomSheet({
    super.key,
    required this.persistenceId,
    required this.child,
    this.desktopPanel = false,
    this.wrapInGlass = false,
    this.desktopAlignment = Alignment.bottomCenter,
    this.desktopWidthFraction = .38,
    this.desktopMaxWidth = 460,
    this.desktopHeightFraction = .78,
  });

  @override
  State<AdaptiveSenderBottomSheet> createState() =>
      _AdaptiveSenderBottomSheetState();
}

class _AdaptiveSenderBottomSheetState extends State<AdaptiveSenderBottomSheet> {
  static const defaultExtent = .45;
  static const minExtent = .18;
  static const maxExtent = .9;
  static const _extentKeyPrefix = 'sender_adaptive_panel_extent_';

  double _initialExtent = defaultExtent;
  String _loadedPersistenceId = '';
  Timer? _persistTimer;

  @override
  void initState() {
    super.initState();
    _loadExtent(widget.persistenceId);
  }

  @override
  void didUpdateWidget(covariant AdaptiveSenderBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.persistenceId != widget.persistenceId) {
      _loadExtent(widget.persistenceId);
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadExtent(String persistenceId) async {
    _persistTimer?.cancel();
    _loadedPersistenceId = persistenceId;
    var extent = defaultExtent;
    if (persistenceId.isNotEmpty) {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getDouble('$_extentKeyPrefix$persistenceId');
      if (saved != null && saved >= minExtent && saved <= maxExtent) {
        extent = saved;
      }
    }
    if (!mounted || _loadedPersistenceId != persistenceId) return;
    setState(() => _initialExtent = extent);
  }

  void _rememberExtent(double extent) {
    if (widget.persistenceId.isEmpty) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setDouble(
        '$_extentKeyPrefix${widget.persistenceId}',
        extent.clamp(minExtent, maxExtent).toDouble(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width >= 900) {
      if (!widget.desktopPanel) {
        return Align(
          alignment: widget.desktopAlignment,
          child: widget.child,
        );
      }
      return Align(
        alignment: widget.desktopAlignment,
        child: SizedBox(
          width: mathMin(
              widget.desktopMaxWidth, size.width * widget.desktopWidthFraction),
          height: size.height * widget.desktopHeightFraction,
          child: _panel(null),
        ),
      );
    }
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        _rememberExtent(notification.extent);
        return false;
      },
      child: DraggableScrollableSheet(
        key: ValueKey('${widget.persistenceId}:$_initialExtent'),
        initialChildSize: _initialExtent,
        minChildSize: minExtent,
        maxChildSize: maxExtent,
        snap: true,
        snapSizes: const [minExtent, defaultExtent, maxExtent],
        builder: (context, controller) => _panel(controller),
      ),
    );
  }

  Widget _panel(ScrollController? controller) {
    if (!widget.wrapInGlass) {
      if (controller == null) return widget.child;
      return PrimaryScrollController(
        controller: controller,
        child: widget.child,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: AppGlassContainer(
        radius: 26,
        padding: EdgeInsets.zero,
        accent: AppTokens.primary,
        surfaceColor: Colors.white.withValues(alpha: .048),
        borderColor: const Color(0xFF3B82F6).withValues(alpha: .28),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

double mathMin(double a, double b) => a < b ? a : b;
