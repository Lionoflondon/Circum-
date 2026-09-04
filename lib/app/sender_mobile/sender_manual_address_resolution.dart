import 'dart:async';

import '../send_package/models/suggestions.m.dart';

enum SenderManualAddressResolutionStatus {
  resolved,
  ambiguous,
  noMatch,
  stale,
  timeout,
  failed,
}

class SenderManualAddressResolution {
  const SenderManualAddressResolution(this.status, {this.suggestion});

  final SenderManualAddressResolutionStatus status;
  final Suggestion? suggestion;
}

class SenderManualAddressResolver {
  int _generation = 0;

  void invalidate() => _generation++;

  Future<SenderManualAddressResolution> resolve({
    required String input,
    required Future<List<Suggestion>> Function(String input) search,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final generation = ++_generation;
    try {
      final matches = await search(input.trim()).timeout(timeout);
      if (generation != _generation) {
        return const SenderManualAddressResolution(
          SenderManualAddressResolutionStatus.stale,
        );
      }
      if (matches.isEmpty) {
        return const SenderManualAddressResolution(
          SenderManualAddressResolutionStatus.noMatch,
        );
      }
      if (matches.length != 1) {
        return const SenderManualAddressResolution(
          SenderManualAddressResolutionStatus.ambiguous,
        );
      }
      return SenderManualAddressResolution(
        SenderManualAddressResolutionStatus.resolved,
        suggestion: matches.single,
      );
    } on TimeoutException {
      return const SenderManualAddressResolution(
        SenderManualAddressResolutionStatus.timeout,
      );
    } catch (_) {
      return const SenderManualAddressResolution(
        SenderManualAddressResolutionStatus.failed,
      );
    }
  }
}
