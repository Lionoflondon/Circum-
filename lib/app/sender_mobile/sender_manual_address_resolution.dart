import 'dart:async';

import '../platform/address_engine.dart';
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
      final bestMatch = senderBestAddressSuggestionForInput(input, matches);
      if (bestMatch != null) {
        return SenderManualAddressResolution(
          SenderManualAddressResolutionStatus.resolved,
          suggestion: bestMatch,
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

Suggestion? senderBestAddressSuggestionForInput(
  String input,
  Iterable<Suggestion> suggestions,
) {
  final matches = senderMatchingAddressSuggestions(input, suggestions);
  return matches.length == 1
      ? AddressEngine.cleanSuggestion(matches.single)
      : null;
}

List<Suggestion> senderMatchingAddressSuggestions(
  String input,
  Iterable<Suggestion> suggestions,
) {
  final inputTokens = _addressMatchTokens(input);
  if (inputTokens.isEmpty) return const [];
  final matches = <Suggestion>[];
  for (final suggestion in suggestions) {
    final suggestionTokens = _addressMatchTokens(
      [
        suggestion.description,
        suggestion.mainText,
        suggestion.subText,
        suggestion.components['locality'],
        suggestion.components['postalTown'],
        suggestion.components['postTown'],
        suggestion.components['city'],
        suggestion.components['postcode'],
        suggestion.components['postalCode'],
      ].whereType<String>().join(' '),
    );
    if (inputTokens.every(suggestionTokens.contains)) {
      matches.add(suggestion);
    }
  }
  return matches;
}

Set<String> _addressMatchTokens(String value) {
  final postcode =
      AddressEngine.extractUkPostcode(value)?.toLowerCase().replaceAll(' ', '');
  final normalized = AddressEngine.normalizeUkPostcodes(value)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  final tokens = normalized
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .map(_canonicalAddressToken)
      .where((token) => !_addressStopWords.contains(token))
      .where((token) => token.length > 2 || RegExp(r'\d').hasMatch(token))
      .toSet();
  if (postcode != null && postcode.isNotEmpty) tokens.add(postcode);
  return tokens;
}

String _canonicalAddressToken(String token) {
  return switch (token) {
    'rd' => 'road',
    'ave' => 'avenue',
    'av' => 'avenue',
    'ln' => 'lane',
    'dr' => 'drive',
    'ct' => 'court',
    'pl' => 'place',
    'sq' => 'square',
    _ => token,
  };
}

const _addressStopWords = {
  'the',
  'and',
  'uk',
  'gb',
  'great',
  'britain',
  'united',
  'kingdom',
  'england',
  'scotland',
  'wales',
  'northern',
  'ireland',
};
