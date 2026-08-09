import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../business/business_journey_context.dart';
import '../../helper/bitmap_descriptor_helper.dart';
import '../../helper/platform_view_visibility.dart';
import '../send_package/bloc/send_package_bloc.dart';
import '../send_package/models/place_coordinates.m.dart';
import '../send_package/repo/place_api.dart';
import 'sender_accessibility.dart';
import 'sender_booking_state.dart';
import 'sender_finance.dart';
import 'sender_saved_addresses.dart';
import 'sender_tracking_screen.dart';

String _scheduledJourneyIso(String date, String time) {
  final value = '${date.trim()}T${time.trim()}:00';
  final parsed = DateTime.tryParse(value);
  return parsed?.toUtc().toIso8601String() ?? '';
}

String _londonTimeFromIso(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return '';
  final local = parsed.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class SenderBookingCanvas extends StatefulWidget {
  const SenderBookingCanvas({super.key});

  @override
  State<SenderBookingCanvas> createState() => _SenderBookingCanvasState();
}

class _SenderBookingCanvasState extends State<SenderBookingCanvas> {
  static const Duration _localDraftRetention = Duration(minutes: 10);
  static const Duration _backendDraftRestoreTimeout = Duration(seconds: 12);
  static const Duration _localDraftRestoreTimeout = Duration(seconds: 4);

  SenderBookingDraft _draft = const SenderBookingDraft();
  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();
  final _receiverName = TextEditingController();
  final _receiverPhone = TextEditingController();
  final _notes = TextEditingController();
  final _scheduledDate = TextEditingController();
  final _scheduledJourneyTime = TextEditingController();
  final _customWindowStart = TextEditingController();
  final _customWindowEnd = TextEditingController();
  final _item = TextEditingController();
  final _description = TextEditingController();
  final _weight = TextEditingController();
  var _searchingPickup = true;
  String? _initializationError;
  String? _addressResolutionMessage;
  bool _addressResolving = false;
  bool _draftLoading = true;
  bool _restoringDraft = false;
  Timer? _draftSaveDebounce;
  String? _draftId;
  int _draftRevision = 0;
  int _saveGeneration = 0;
  Future<void> _saveChain = Future.value();
  String _syncStatus = 'Loading draft';
  bool _suppressDraftSave = false;
  String? _lastBackendQuoteKey;
  XFile? _parcelPhoto;
  bool _parcelPhotoBusy = false;
  String? _parcelPhotoMessage;
  String? _irisPhotoAnalysisId;
  double? _photoEstimatedWeightKg;
  bool _resettingBooking = false;

  @override
  void initState() {
    super.initState();
    _initializeSendRoute();
  }

  void _initializeSendRoute() {
    try {
      final bloc = context.read<SendPackageBloc>();
      bloc.add(CheckForPushToken());
      bloc.add(CheckForActiveRequest());
      if (!_handleStripeCheckoutReturn(bloc)) {
        _loadBackendDraft();
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Sender booking route could not initialise: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      _draftLoading = false;
      _initializationError =
          'Send could not start because its booking engine was unavailable.';
    }
  }

  bool _handleStripeCheckoutReturn(SendPackageBloc bloc) {
    if (!kIsWeb) return false;
    final params = Uri.base.queryParameters;
    final result = (params['sender_payment'] ?? '').trim().toLowerCase();
    if (result == 'cancelled') {
      _draft = _draft.copyWith(
        step: SenderBookingStep.payment,
        paymentStatus: SenderPaymentStatus.failed,
        cardConfirmationStarted: false,
      );
      _syncStatus = 'Payment cancelled';
      return false;
    }
    if (result != 'success') return false;
    final checkoutSessionId = (params['checkoutSessionId'] ?? '').trim();
    final paymentSessionId = (params['paymentSessionId'] ?? '').trim();
    if (checkoutSessionId.isEmpty || paymentSessionId.isEmpty) {
      _draft = _draft.copyWith(
        step: SenderBookingStep.payment,
        paymentStatus: SenderPaymentStatus.failed,
        cardConfirmationStarted: false,
      );
      _draftLoading = false;
      _initializationError =
          'Stripe payment could not be confirmed. Please contact support.';
      return true;
    }
    _draft = _draft.copyWith(
      step: SenderBookingStep.findingRider,
      paymentStatus: SenderPaymentStatus.processing,
      cardConfirmationStarted: true,
    );
    _draftLoading = false;
    _syncStatus = 'Confirming payment';
    bloc.add(
      FinalizeSenderWebCheckout(
        checkoutSessionId: checkoutSessionId,
        paymentSessionId: paymentSessionId,
      ),
    );
    return true;
  }

  @override
  void dispose() {
    _draftSaveDebounce?.cancel();
    if (!_suppressDraftSave && !_draftLoading && !_restoringDraft) {
      _queueDraftSave(_draft);
    }
    _pickup.dispose();
    _dropoff.dispose();
    _receiverName.dispose();
    _receiverPhone.dispose();
    _notes.dispose();
    _scheduledDate.dispose();
    _scheduledJourneyTime.dispose();
    _customWindowStart.dispose();
    _customWindowEnd.dispose();
    _item.dispose();
    _description.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _setDraft(SenderBookingDraft next) {
    setState(() => _draft = next);
    if (!_restoringDraft) _scheduleDraftSave(next);
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  String? get _localDraftKey {
    final uid = _uid;
    return uid == null ? null : 'senderBookingDraftQueue:$uid';
  }

  Future<Map<String, dynamic>> _callDraftFunction(
    String name, [
    Map<String, dynamic> payload = const {},
    Duration? timeout,
  ]) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(name)
        .call(payload)
        .timeout(timeout ?? const Duration(seconds: 15));
    return result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : <String, dynamic>{};
  }

  bool _isExpectedRestoreFailure(Object error) {
    if (error is TimeoutException) return true;
    if (error is FirebaseFunctionsException) {
      return switch (error.code) {
        'unauthenticated' ||
        'not-found' ||
        'deadline-exceeded' ||
        'unavailable' ||
        'permission-denied' =>
          true,
        _ => false,
      };
    }
    return false;
  }

  bool _canStartFreshAfterDraftFailure(FirebaseFunctionsException error) {
    return switch (error.code) {
      'internal' ||
      'not-found' ||
      'deadline-exceeded' ||
      'unavailable' ||
      'aborted' ||
      'failed-precondition' =>
        true,
      _ => false,
    };
  }

  Future<void> _startFreshAfterDraftFailure(String syncStatus) async {
    await _clearQueuedLocalDraft();
    if (!mounted) return;
    _hydrateDraft(const SenderBookingDraft());
    setState(() {
      _draftLoading = false;
      _initializationError = null;
      _syncStatus = syncStatus;
    });
  }

  void _reportUnexpectedRestoreFailure(
    Object error,
    StackTrace stackTrace,
    String context,
  ) {
    if (_isExpectedRestoreFailure(error)) return;
    if (kDebugMode) {
      debugPrint('Sender draft recovery issue while $context: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _loadBackendDraft() async {
    setState(() => _draftLoading = true);
    if (_uid == null) {
      await _clearQueuedLocalDraft();
      if (!mounted) return;
      setState(() {
        _draftLoading = false;
        _syncStatus = 'Saved';
      });
      return;
    }
    try {
      try {
        final data = await _callDraftFunction(
          'loadSenderDraft',
          const {},
          _backendDraftRestoreTimeout,
        );
        if (data['exists'] == true && data['draft'] is Map) {
          _draftRevision = _intFrom(data['revision']);
          _draftId = '${data['draftId'] ?? ''}'.trim().isEmpty
              ? null
              : '${data['draftId']}';
          final restored = SenderBookingDraft.fromBackendDraft(
            Map<String, dynamic>.from(data['draft'] as Map),
          );
          _hydrateRestoredDraft(restored);
        }
      } on TimeoutException catch (error, stackTrace) {
        _reportUnexpectedRestoreFailure(
          error,
          stackTrace,
          'timed out loading Sender booking draft',
        );
        if (mounted) setState(() => _syncStatus = 'Saved offline');
      }
      await _restoreQueuedLocalDraft().timeout(_localDraftRestoreTimeout);
      if (mounted) setState(() => _draftLoading = false);
    } on FirebaseFunctionsException catch (error, stackTrace) {
      _reportUnexpectedRestoreFailure(
        error,
        stackTrace,
        'loading Sender booking draft',
      );
      if (_canStartFreshAfterDraftFailure(error)) {
        await _startFreshAfterDraftFailure('Started fresh');
        return;
      }
      if (!mounted) return;
      setState(() {
        _draftLoading = false;
        _initializationError = error.code == 'unauthenticated'
            ? 'Sign in again to send a parcel.'
            : 'Your saved delivery could not be restored. Please try again.';
      });
    } on TimeoutException catch (error, stackTrace) {
      _reportUnexpectedRestoreFailure(
        error,
        stackTrace,
        'restoring queued Sender booking draft',
      );
      await _clearQueuedLocalDraft();
      if (!mounted) return;
      setState(() {
        _draftLoading = false;
        _initializationError =
            "Your previous draft couldn't be restored. Please start again.";
      });
    } catch (error, stackTrace) {
      _reportUnexpectedRestoreFailure(
        error,
        stackTrace,
        'loading Sender booking draft',
      );
      if (!mounted) return;
      setState(() {
        _draftLoading = false;
        _initializationError = 'Your saved delivery draft could not be loaded.';
      });
    }
  }

  void _hydrateRestoredDraft(SenderBookingDraft restored) {
    if (!mounted) return;
    _restoringDraft = true;
    try {
      _hydrateDraft(_safeRestoredDraft(restored));
    } finally {
      _restoringDraft = false;
    }
  }

  SenderBookingDraft _safeRestoredDraft(SenderBookingDraft restored) {
    final routeReady = restored.pickupLat != null &&
        restored.pickupLng != null &&
        restored.dropoffLat != null &&
        restored.dropoffLng != null;
    final routeDependentStep =
        SenderBookingStep.values.indexOf(restored.step) >=
            SenderBookingStep.values.indexOf(SenderBookingStep.parcel);
    if (routeDependentStep && !routeReady) {
      final hasPickupCoordinate =
          restored.pickupLat != null && restored.pickupLng != null;
      return restored.copyWith(
        step: hasPickupCoordinate
            ? SenderBookingStep.dropoff
            : SenderBookingStep.pickup,
      );
    }
    return restored;
  }

  void _hydrateDraft(SenderBookingDraft restored) {
    if (!mounted) return;
    _pickup.text = restored.pickupAddress;
    _dropoff.text = restored.dropoffAddress;
    _receiverName.text = restored.receiverName;
    _receiverPhone.text = restored.receiverPhone;
    _notes.text = restored.deliveryNotes;
    _scheduledDate.text = restored.scheduledDate;
    _scheduledJourneyTime.text =
        _londonTimeFromIso(restored.scheduledJourneyAt);
    _customWindowStart.text = restored.customWindowStart;
    _customWindowEnd.text = restored.customWindowEnd;
    _item.text = restored.itemName;
    _description.text = restored.itemDescription;
    _weight.text = restored.weightLabel;
    setState(() => _draft = restored);
    if (restored.pickupLat != null &&
        restored.pickupLng != null &&
        restored.dropoffLat != null &&
        restored.dropoffLng != null) {
      context.read<SendPackageBloc>().add(
            RestoreSenderRoute(
              pickupAddress: restored.pickupAddress,
              pickupLat: restored.pickupLat!,
              pickupLng: restored.pickupLng!,
              dropoffAddress: restored.dropoffAddress,
              dropoffLat: restored.dropoffLat!,
              dropoffLng: restored.dropoffLng!,
            ),
          );
    }
  }

  void _scheduleDraftSave(SenderBookingDraft next) {
    if (_suppressDraftSave) return;
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 450), () {
      _queueDraftSave(next);
    });
  }

  void _queueDraftSave(SenderBookingDraft next) {
    if (_suppressDraftSave) return;
    final generation = ++_saveGeneration;
    _saveChain = _saveChain.then((_) => _saveDraft(next, generation));
  }

  Future<void> _saveDraft(
    SenderBookingDraft next,
    int generation, {
    bool retryConflict = true,
  }) async {
    if (_uid == null) return;
    if (next.step == SenderBookingStep.findingRider ||
        next.step == SenderBookingStep.liveTracking ||
        next.bookingConfirmed) {
      return;
    }
    try {
      if (mounted) setState(() => _syncStatus = 'Saving...');
      final engine = context.read<SendPackageBloc>().state;
      final nextWithRoute = next.copyWith(
        pickupLat: engine.pickupCoordinate?.lat ?? next.pickupLat,
        pickupLng: engine.pickupCoordinate?.lng ?? next.pickupLng,
        dropoffLat: engine.desinationCoordinate?.lat ?? next.dropoffLat,
        dropoffLng: engine.desinationCoordinate?.lng ?? next.dropoffLng,
      );
      final payload = {
        'schemaVersion': 1,
        'baseRevision': _draftRevision,
        'draft': {
          ...nextWithRoute.toBackendDraftPayload(),
          if (_draftId != null) 'draftId': _draftId,
        },
      };
      await _storeQueuedLocalDraft(payload);
      final data = await _callDraftFunction('saveSenderDraft', payload);
      if (generation == _saveGeneration) {
        _draftRevision = _intFrom(data['revision']);
        _draftId = '${data['draftId'] ?? ''}'.trim().isEmpty
            ? _draftId
            : '${data['draftId']}';
        await _clearQueuedLocalDraft();
        if (mounted) setState(() => _syncStatus = 'Saved');
      }
    } on FirebaseFunctionsException catch (error, stackTrace) {
      if (retryConflict &&
          (error.code == 'aborted' || error.code == 'failed-precondition')) {
        await _handleDraftConflict(next, generation);
        return;
      }
      _reportUnexpectedRestoreFailure(
        error,
        stackTrace,
        'saving Sender booking draft',
      );
      if (mounted) setState(() => _syncStatus = 'Saved offline');
    } catch (error, stackTrace) {
      _reportUnexpectedRestoreFailure(
        error,
        stackTrace,
        'saving Sender booking draft',
      );
      if (mounted) setState(() => _syncStatus = 'Saved offline');
    }
  }

  Future<void> _handleDraftConflict(
    SenderBookingDraft localDraft,
    int generation,
  ) async {
    final data = await _callDraftFunction('loadSenderDraft');
    if (data['exists'] == true && data['draft'] is Map) {
      _draftRevision = _intFrom(data['revision']);
      _draftId = '${data['draftId'] ?? ''}'.trim().isEmpty
          ? _draftId
          : '${data['draftId']}';
      if (mounted) {
        setState(() {
          _syncStatus = 'Updated from another device';
        });
      }
    }
    if (generation == _saveGeneration) {
      await _saveDraft(localDraft, generation + 1, retryConflict: false);
    }
  }

  Future<void> _storeQueuedLocalDraft(Map<String, dynamic> payload) async {
    final key = _localDraftKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        ...payload,
        'queuedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<void> _clearQueuedLocalDraft() async {
    final key = _localDraftKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<void> _restoreQueuedLocalDraft() async {
    final key = _localDraftKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      if (mounted) setState(() => _syncStatus = 'Saved');
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      await _clearQueuedLocalDraft();
      if (mounted) {
        setState(() {
          _syncStatus = 'Saved';
          _initializationError =
              "Your previous draft couldn't be restored. Please start again.";
        });
      }
      return;
    }
    if (decoded is! Map || decoded['draft'] is! Map) {
      await _clearQueuedLocalDraft();
      if (mounted) setState(() => _syncStatus = 'Saved');
      return;
    }
    if (_queuedLocalDraftExpired(decoded)) {
      await _clearQueuedLocalDraft();
      if (mounted) setState(() => _syncStatus = 'Saved');
      return;
    }
    final SenderBookingDraft restored;
    try {
      restored = SenderBookingDraft.fromBackendDraft(
        Map<String, dynamic>.from(decoded['draft'] as Map),
      );
    } catch (_) {
      await _clearQueuedLocalDraft();
      if (mounted) {
        setState(() {
          _syncStatus = 'Saved';
          _initializationError =
              "Your previous draft couldn't be restored. Please start again.";
        });
      }
      return;
    }
    _hydrateRestoredDraft(restored);
    if (mounted) setState(() => _syncStatus = 'Sync needed');
    _queueDraftSave(restored);
  }

  Future<void> _deleteBackendDraft() async {
    _draftSaveDebounce?.cancel();
    if (_uid == null) {
      await _clearQueuedLocalDraft();
      _draftRevision = 0;
      _draftId = null;
      return;
    }
    try {
      await _callDraftFunction('deleteSenderDraft');
      _draftRevision = 0;
      _draftId = null;
    } catch (error, stackTrace) {
      _reportUnexpectedRestoreFailure(
        error,
        stackTrace,
        'deleting completed Sender booking draft',
      );
    } finally {
      await _clearQueuedLocalDraft();
      _draftRevision = 0;
      _draftId = null;
    }
  }

  bool _queuedLocalDraftExpired(Map<dynamic, dynamic> decoded) {
    final rawQueuedAt = '${decoded['queuedAt'] ?? ''}'.trim();
    final queuedAt = DateTime.tryParse(rawQueuedAt);
    if (queuedAt == null) return false;
    return DateTime.now().toUtc().difference(queuedAt.toUtc()) >
        _localDraftRetention;
  }

  Future<void> _discardDraftAndExit() async {
    _suppressDraftSave = true;
    _draftSaveDebounce?.cancel();
    if (!mounted) return;
    _hydrateDraft(const SenderBookingDraft());
    unawaited(_deleteBackendDraft());
    final popped = await Navigator.of(context).maybePop();
    if (!popped && mounted) {
      _suppressDraftSave = false;
      _scheduleDraftSave(const SenderBookingDraft());
    }
  }

  Future<void> _confirmCancelBooking() async {
    if (_resettingBooking) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .62),
      isScrollControlled: true,
      builder: (sheetContext) => _CancelBookingSheet(
        onContinue: () => Navigator.of(sheetContext).pop(false),
        onCancel: () => Navigator.of(sheetContext).pop(true),
      ),
    );
    if (confirmed == true) {
      await _resetBookingSession();
    }
  }

  Future<void> _resetBookingSession() async {
    if (_resettingBooking) return;
    _resettingBooking = true;
    _suppressDraftSave = true;
    _draftSaveDebounce?.cancel();
    context.read<SendPackageBloc>().add(const ResetSenderBookingSession());
    await _deleteBackendDraft();
    if (!mounted) {
      _resettingBooking = false;
      return;
    }
    _pickup.clear();
    _dropoff.clear();
    _receiverName.clear();
    _receiverPhone.clear();
    _notes.clear();
    _scheduledDate.clear();
    _scheduledJourneyTime.clear();
    _customWindowStart.clear();
    _customWindowEnd.clear();
    _item.clear();
    _description.clear();
    _weight.clear();
    setState(() {
      _draft = const SenderBookingDraft();
      _draftId = null;
      _draftRevision = 0;
      _saveGeneration++;
      _syncStatus = 'New booking';
      _initializationError = null;
      _addressResolutionMessage = null;
      _addressResolving = false;
      _searchingPickup = true;
      _lastBackendQuoteKey = null;
      _parcelPhoto = null;
      _parcelPhotoBusy = false;
      _parcelPhotoMessage = null;
      _irisPhotoAnalysisId = null;
      _photoEstimatedWeightKg = null;
    });
    _suppressDraftSave = false;
    _resettingBooking = false;
    _scheduleDraftSave(const SenderBookingDraft());
  }

  void _advance() async {
    if (_draft.step == SenderBookingStep.payment) return;
    if (_draft.step == SenderBookingStep.pickup ||
        _draft.step == SenderBookingStep.dropoff) {
      final resolved = await _resolveTypedAddressIfNeeded();
      if (!resolved || !mounted) return;
    }
    _restoreRouteFromDraftIfReady(_draft);
    if (_draft.step == SenderBookingStep.pickup ||
        _draft.step == SenderBookingStep.dropoff) {
      context.read<SendPackageBloc>().add(ClearSuggestions());
    }
    if (_draft.step == SenderBookingStep.parcel) {
      final engine = context.read<SendPackageBloc>().state;
      final irisReady = _irisMatchesParcel(
        engine.canonicalIrisResult,
        _item.text,
        _description.text,
      );
      if (engine.isIrisResolving) return;
      if (!irisReady) {
        context.read<SendPackageBloc>().add(
              RequestCanonicalIrisEstimate(
                itemName: _item.text,
                quantity: senderQuantityFromItemName(_item.text),
                description: _description.text,
                declaredWeightText: _weight.text,
                fragile: false,
                highValue: false,
              ),
            );
        return;
      }
      _setDraft(_draft.copyWith(step: SenderBookingStep.options));
      _requestBackendQuote(_draft.copyWith(step: SenderBookingStep.options));
      return;
    }
    if (_draft.step == SenderBookingStep.iris) {
      context.read<SendPackageBloc>().add(
            RequestCanonicalIrisEstimate(
              itemName: _item.text,
              quantity: senderQuantityFromItemName(_item.text),
              description: _description.text,
              declaredWeightText: _weight.text,
              fragile: false,
              highValue: false,
            ),
          );
    }
    if (_draft.step == SenderBookingStep.iris ||
        _draft.step == SenderBookingStep.options ||
        _draft.step == SenderBookingStep.review) {
      _requestBackendQuote(_draft);
    }
    if (_draft.step == SenderBookingStep.review) {
      context.read<SendPackageBloc>().add(const LoadSenderRothBalance());
    }
    _setDraft(_draft.next());
  }

  Future<bool> _resolveTypedAddressIfNeeded() async {
    final pickup = _draft.step == SenderBookingStep.pickup;
    final address =
        (pickup ? _draft.pickupAddress : _draft.dropoffAddress).trim();
    final hasCoordinates = pickup
        ? _draft.pickupLat != null && _draft.pickupLng != null
        : _draft.dropoffLat != null && _draft.dropoffLng != null;
    if (address.isEmpty || hasCoordinates) return true;

    setState(() {
      _addressResolving = true;
      _addressResolutionMessage = null;
    });
    try {
      final provider = PlaceApiProvider(const Uuid());
      final lang = Localizations.localeOf(context).languageCode;
      final suggestions = await provider.fetchSuggestions(
        address,
        lang,
      );
      if (!mounted) return false;
      final normalized = address.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final match = suggestions.where((suggestion) {
        final description = suggestion.description
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ');
        final main = suggestion.mainText
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ');
        return description == normalized || main == normalized;
      }).firstOrNull;
      if (match == null) {
        throw StateError('No exact address match found');
      }
      final coordinate = await provider.fetchPlaceDetails(
        match.placeId,
        lang,
      );
      if (!mounted) return false;
      if (pickup) {
        context.read<SendPackageBloc>().add(
              SetPickupAddress(
                val: match.description,
                pickupLocationSubAddress: match.subText,
                placeId: match.placeId,
                lang: lang,
              ),
            );
        _setDraft(
          _draft.copyWith(
            pickupAddress: match.description,
            pickupLat: coordinate.lat,
            pickupLng: coordinate.lng,
          ),
        );
      } else {
        context.read<SendPackageBloc>().add(
              SetDeliveryAddress(
                val: match.description,
                destinationLocationSubAddress: match.subText,
                placeId: match.placeId,
                lang: lang,
              ),
            );
        _setDraft(
          _draft.copyWith(
            dropoffAddress: match.description,
            dropoffLat: coordinate.lat,
            dropoffLng: coordinate.lng,
          ),
        );
      }
      return true;
    } catch (error, stackTrace) {
      debugPrint('Typed Sender address resolution failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _addressResolutionMessage =
              'Please choose a matching address suggestion before continuing.';
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _addressResolving = false);
    }
  }

  void _requestBackendQuote(SenderBookingDraft draft) {
    _restoreRouteFromDraftIfReady(draft);
    final engine = context.read<SendPackageBloc>().state;
    final routeReady = _routeReadyForQuote(engine, draft);
    if (!routeReady) {
      return;
    }
    final business = BusinessJourneyScope.maybeOf(context);
    final iris = engine.canonicalIrisResult;
    final requiresVanguard =
        _irisRequiresIncludedVanguard(iris, business: business) ||
            draft.vanguard;
    final selectedVehicle = _selectedVehicleFor(draft, iris);
    final quoteKey = [
      (engine.distance ?? -1).toStringAsFixed(3),
      draft.selectedOption,
      selectedVehicle,
      requiresVanguard,
      draft.itemName,
      draft.itemDescription,
      _manualWeightKg(_weight.text)?.toStringAsFixed(3) ?? '0',
      _irisPhotoAnalysisId ?? '',
      draft.scheduledJourneyAt,
      business?.businessId ?? '',
    ].join('|');
    if (_lastBackendQuoteKey == quoteKey && engine.senderQuoteError.isEmpty) {
      return;
    }
    _lastBackendQuoteKey = quoteKey;
    context.read<SendPackageBloc>().add(
          RequestSenderBookingQuote(
            selectedSpeed: draft.selectedOption,
            vanguardProtocolEnabled: requiresVanguard,
            itemName: draft.itemName,
            description: draft.itemDescription,
            weightKg: _manualWeightKg(_weight.text) ?? 0,
            fragile: _irisHasHandling(iris, 'fragile'),
            highValue: _irisHasHandling(iris, 'high value'),
            selectedVehicle: selectedVehicle,
            scheduledJourneyAt: draft.scheduledJourneyAt,
            scheduledDate: draft.scheduledDate,
            irisPhotoAnalysisId: _irisPhotoAnalysisId ?? '',
            businessContext: business?.toMap(),
          ),
        );
  }

  void _onParcelChanged() {
    if (_irisPhotoAnalysisId != null || _photoEstimatedWeightKg != null) {
      _irisPhotoAnalysisId = null;
      _photoEstimatedWeightKg = null;
      _parcelPhotoMessage = _parcelPhoto == null
          ? null
          : 'Photo kept. Recheck IRIS after changing item details.';
    }
    final engine = context.read<SendPackageBloc>().state;
    if (engine.canonicalIrisResult != null ||
        engine.irisResult != null ||
        engine.parcelWeightKg > 0 ||
        engine.senderQuoteId != null ||
        engine.senderPaymentSessionId != null) {
      _lastBackendQuoteKey = null;
      context.read<SendPackageBloc>().add(const ClearIrisParcelState());
    }
    final parsed = _manualWeightKg(_weight.text);
    _setDraft(
      _draft.copyWith(
        itemName: _item.text,
        itemDescription: _description.text,
        weightLabel: parsed == null ? '' : '${parsed.toStringAsFixed(1)}kg',
      ),
    );
  }

  Future<void> _pickParcelPhoto() async {
    final details = [
      _item.text,
      _description.text,
    ].where((value) => value.trim().isNotEmpty).join(' ').trim();
    if (details.length < 3) {
      setState(() {
        _parcelPhotoMessage = 'Describe the item before adding a photo.';
      });
      return;
    }
    setState(() {
      _parcelPhotoBusy = true;
      _parcelPhotoMessage = null;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 72,
        maxWidth: 1600,
      );
      if (picked == null) {
        if (mounted) {
          setState(() => _parcelPhotoMessage = 'No parcel photo selected.');
        }
        return;
      }
      final bytes = await picked.readAsBytes();
      final result = await FirebaseFunctions.instance
          .httpsCallable('analyseParcelPhotoForIris')
          .call({
        'imageBase64': base64Encode(bytes),
        'contentType': picked.mimeType ?? 'image/jpeg',
        'fileName': picked.name,
        'description': details,
        'declaredWeightText': _weight.text,
      }).timeout(const Duration(seconds: 20));
      final data = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : <String, dynamic>{};
      final estimate = _nullableDouble(data['estimatedWeightKg']);
      if (!mounted) return;
      setState(() {
        _parcelPhoto = picked;
        _irisPhotoAnalysisId = '${data['analysisId'] ?? ''}'.trim();
        _photoEstimatedWeightKg = estimate;
        _parcelPhotoMessage = estimate == null
            ? 'Photo added. IRIS will use your item details.'
            : 'Photo reviewed. Visual estimate ${estimate.toStringAsFixed(2)} kg.';
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _parcelPhotoMessage = error.code == 'invalid-argument'
            ? 'Photo could not be used. Add a clear JPG, PNG or WebP under 10MB.'
            : 'Photo could not be reviewed. You can continue with item details.';
      });
    } catch (error, stackTrace) {
      _reportUnexpectedRestoreFailure(
        error,
        stackTrace,
        'analysing parcel photo',
      );
      if (!mounted) return;
      setState(() {
        _parcelPhotoMessage =
            'Photo could not be reviewed. You can continue with item details.';
      });
    } finally {
      if (mounted) setState(() => _parcelPhotoBusy = false);
    }
  }

  void _removeParcelPhoto() {
    setState(() {
      _parcelPhoto = null;
      _parcelPhotoMessage = 'Parcel photo removed.';
      _irisPhotoAnalysisId = null;
      _photoEstimatedWeightKg = null;
    });
    _lastBackendQuoteKey = null;
    context.read<SendPackageBloc>().add(const ClearIrisParcelState());
  }

  void _restoreRouteFromDraftIfReady(SenderBookingDraft draft) {
    if (draft.pickupLat == null ||
        draft.pickupLng == null ||
        draft.dropoffLat == null ||
        draft.dropoffLng == null) {
      return;
    }
    context.read<SendPackageBloc>().add(
          RestoreSenderRoute(
            pickupAddress: draft.pickupAddress,
            pickupLat: draft.pickupLat!,
            pickupLng: draft.pickupLng!,
            dropoffAddress: draft.dropoffAddress,
            dropoffLat: draft.dropoffLat!,
            dropoffLng: draft.dropoffLng!,
          ),
        );
  }

  void _back() {
    if (_draft.step == SenderBookingStep.pickup) {
      unawaited(_discardDraftAndExit());
      return;
    }
    if (_draft.step == SenderBookingStep.options) {
      _setDraft(_draft.copyWith(step: SenderBookingStep.parcel));
      return;
    }
    _setDraft(_draft.back());
  }

  @override
  Widget build(BuildContext context) {
    if (_initializationError != null) {
      return _SendRouteStateScaffold(
        title: 'Send unavailable',
        body: _initializationError!,
        actionLabel: 'Retry',
        onAction: () {
          setState(() => _initializationError = null);
          _initializeSendRoute();
        },
      );
    }
    if (_draftLoading) {
      return const _SendRouteStateScaffold(
        title: 'Restoring delivery',
        body: 'Loading your saved delivery draft.',
        actionLabel: 'Please wait',
      );
    }
    return BlocBuilder<SendPackageBloc, SendPackageState>(
      builder: (context, engine) {
        final operationalStep = _stepForEngine(engine);
        if (operationalStep != null && operationalStep != _draft.step) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _deleteBackendDraft();
            _setDraft(_draft.copyWith(step: operationalStep));
          });
        }
        if ((_draft.step == SenderBookingStep.options ||
                _draft.step == SenderBookingStep.review ||
                _draft.step == SenderBookingStep.payment) &&
            _routeReadyForQuote(engine, _draft) &&
            !engine.isSenderQuoteLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _requestBackendQuote(_draft);
          });
        }
        if (_draft.step == SenderBookingStep.findingRider ||
            _draft.step == SenderBookingStep.liveTracking) {
          return ColoredBox(
            color: _Tokens.bg,
            child: SenderMobileTrackingScreen(
              engine: engine,
              stateOverride: senderTrackingStateForEngine(engine),
            ),
          );
        }
        if (_draft.step == SenderBookingStep.review) {
          return _SenderReviewDeliveryScreen(
            draft: _draft,
            engine: engine,
            onBack: _back,
            onCancel: _confirmCancelBooking,
            onContinue: _advance,
          );
        }
        return ColoredBox(
          color: _Tokens.bg,
          child: Stack(
            children: [
              _SenderMobileMap(
                active: true,
                engine: engine,
                showDestination: engine.desinationCoordinate != null ||
                    _dropoff.text.trim().isNotEmpty,
                showVanguardShield: _draft.vanguard,
                distanceKm: engine.distance,
              ),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(
                      progress: _draft.progress,
                      syncStatus: _syncStatus,
                      onBack: _back,
                      onCancel: _confirmCancelBooking,
                    ),
                    const Spacer(),
                    _BookingPanel(
                      draft: _draft,
                      engine: engine,
                      draftId: _draftId,
                      senderUid: _uid,
                      pickup: _pickup,
                      dropoff: _dropoff,
                      receiverName: _receiverName,
                      receiverPhone: _receiverPhone,
                      notes: _notes,
                      scheduledDate: _scheduledDate,
                      scheduledJourneyTime: _scheduledJourneyTime,
                      customWindowStart: _customWindowStart,
                      customWindowEnd: _customWindowEnd,
                      item: _item,
                      description: _description,
                      weight: _weight,
                      parcelPhoto: _parcelPhoto,
                      parcelPhotoBusy: _parcelPhotoBusy,
                      parcelPhotoMessage: _parcelPhotoMessage,
                      photoEstimatedWeightKg: _photoEstimatedWeightKg,
                      searchingPickup: _searchingPickup,
                      onSearchingPickupChanged: (value) =>
                          setState(() => _searchingPickup = value),
                      onParcelChanged: _onParcelChanged,
                      onPhotoTap: _pickParcelPhoto,
                      onPhotoRemove: _removeParcelPhoto,
                      onDraft: _setDraft,
                      onContinue: _advance,
                      addressResolutionMessage: _addressResolutionMessage,
                      addressResolving: _addressResolving,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  SenderBookingStep? _stepForEngine(SendPackageState engine) {
    switch (engine.deliveryStatus) {
      case DeliveryStatus.deliveryConfirmed:
      case DeliveryStatus.reconnectingWithRider:
        return SenderBookingStep.findingRider;
      case DeliveryStatus.deliveryOnGoing:
        return SenderBookingStep.liveTracking;
      case DeliveryStatus.deliveryCompleted:
        return null;
      case DeliveryStatus.inital:
      case DeliveryStatus.addressesSelected:
        return null;
    }
  }
}

int _intFrom(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

class _SendRouteStateScaffold extends StatelessWidget {
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onAction;

  const _SendRouteStateScaffold({
    required this.title,
    required this.body,
    required this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _Tokens.bg,
      child: Stack(
        children: [
          const _SenderMobileMap(active: false),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _Glass(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: _Tokens.lightBlue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        body,
                        style: const TextStyle(
                          color: _Tokens.muted,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PrimaryButton(
                        label: actionLabel,
                        enabled: onAction != null,
                        onTap: onAction ?? () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final double progress;
  final String syncStatus;
  final VoidCallback onBack;
  final VoidCallback onCancel;

  const _TopBar({
    required this.progress,
    required this.syncStatus,
    required this.onBack,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          _RoundButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: progress,
                backgroundColor: Colors.white.withValues(alpha: .08),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  _Tokens.lightBlue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            syncStatus,
            style: const TextStyle(
              color: _Tokens.muted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          _BookingCancelPill(onTap: onCancel),
        ],
      ),
    );
  }
}

class _BookingPanel extends StatelessWidget {
  final SenderBookingDraft draft;
  final SendPackageState engine;
  final String? draftId;
  final String? senderUid;
  final TextEditingController pickup;
  final TextEditingController dropoff;
  final TextEditingController receiverName;
  final TextEditingController receiverPhone;
  final TextEditingController notes;
  final TextEditingController scheduledDate;
  final TextEditingController scheduledJourneyTime;
  final TextEditingController customWindowStart;
  final TextEditingController customWindowEnd;
  final TextEditingController item;
  final TextEditingController description;
  final TextEditingController weight;
  final XFile? parcelPhoto;
  final bool parcelPhotoBusy;
  final String? parcelPhotoMessage;
  final double? photoEstimatedWeightKg;
  final bool searchingPickup;
  final ValueChanged<bool> onSearchingPickupChanged;
  final VoidCallback onParcelChanged;
  final VoidCallback onPhotoTap;
  final VoidCallback onPhotoRemove;
  final ValueChanged<SenderBookingDraft> onDraft;
  final VoidCallback onContinue;
  final String? addressResolutionMessage;
  final bool addressResolving;

  const _BookingPanel({
    required this.draft,
    required this.engine,
    required this.draftId,
    required this.senderUid,
    required this.pickup,
    required this.dropoff,
    required this.receiverName,
    required this.receiverPhone,
    required this.notes,
    required this.scheduledDate,
    required this.scheduledJourneyTime,
    required this.customWindowStart,
    required this.customWindowEnd,
    required this.item,
    required this.description,
    required this.weight,
    required this.parcelPhoto,
    required this.parcelPhotoBusy,
    required this.parcelPhotoMessage,
    required this.photoEstimatedWeightKg,
    required this.searchingPickup,
    required this.onSearchingPickupChanged,
    required this.onParcelChanged,
    required this.onPhotoTap,
    required this.onPhotoRemove,
    required this.onDraft,
    required this.onContinue,
    required this.addressResolutionMessage,
    required this.addressResolving,
  });

  @override
  Widget build(BuildContext context) {
    final content = _content(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final maxPanelHeight = math.max(
      320.0,
      MediaQuery.sizeOf(context).height - bottomInset - 150,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset + 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxPanelHeight),
        child: _Glass(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: SingleChildScrollView(
              key: ValueKey(draft.step),
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(bottom: bottomInset + 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      height: 5,
                      width: 48,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Text(
                    senderStepTitle(draft.step),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  content,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    switch (draft.step) {
      case SenderBookingStep.pickup:
        return _AddressPanel(
          savedForPickup: true,
          controller: pickup,
          hint: 'Pickup address, flat or postcode',
          helperText: 'Enter a postcode, business or address.',
          suggestions: engine.suggestions,
          isSearching: engine.isAddressSearching,
          errorText: engine.addressSearchError,
          resolutionMessage: addressResolutionMessage,
          isResolvingTypedAddress: addressResolving,
          onChanged: (value) {
            onSearchingPickupChanged(true);
            _search(context, value);
            onDraft(
              draft.copyWith(pickupAddress: value, clearPickupCoordinate: true),
            );
          },
          onSuggestion: (suggestion) {
            final lat = suggestion.lat is num
                ? (suggestion.lat as num).toDouble()
                : null;
            final lng = suggestion.lng is num
                ? (suggestion.lng as num).toDouble()
                : null;
            context.read<SendPackageBloc>().add(
                  SetPickupAddress(
                    val: suggestion.description,
                    pickupLocationSubAddress: suggestion.subText,
                    placeId: suggestion.placeId,
                    lang: Localizations.localeOf(context).languageCode,
                  ),
                );
            pickup.text = suggestion.description;
            onDraft(
              draft.copyWith(
                pickupAddress: suggestion.description,
                pickupLat: lat,
                pickupLng: lng,
                dropoffAddress: '',
                clearDropoffCoordinate: true,
              ),
            );
          },
          primaryLabel: 'Confirm pickup',
          canContinue: draft.canContinue,
          onContinue: onContinue,
        );
      case SenderBookingStep.dropoff:
        return _AddressPanel(
          savedForPickup: false,
          controller: dropoff,
          hint: 'Drop-off address, flat or postcode',
          helperText: 'Enter a postcode, business or address.',
          suggestions: engine.suggestions,
          isSearching: engine.isAddressSearching,
          errorText: engine.addressSearchError,
          resolutionMessage: addressResolutionMessage,
          isResolvingTypedAddress: addressResolving,
          onChanged: (value) {
            onSearchingPickupChanged(false);
            _search(context, value);
            onDraft(
              draft.copyWith(
                dropoffAddress: value,
                clearDropoffCoordinate: true,
              ),
            );
          },
          onSuggestion: (suggestion) {
            final lat = suggestion.lat is num
                ? (suggestion.lat as num).toDouble()
                : null;
            final lng = suggestion.lng is num
                ? (suggestion.lng as num).toDouble()
                : null;
            context.read<SendPackageBloc>().add(
                  SetDeliveryAddress(
                    val: suggestion.description,
                    destinationLocationSubAddress: suggestion.subText,
                    placeId: suggestion.placeId,
                    lang: Localizations.localeOf(context).languageCode,
                  ),
                );
            dropoff.text = suggestion.description;
            onDraft(
              draft.copyWith(
                dropoffAddress: suggestion.description,
                dropoffLat: lat,
                dropoffLng: lng,
              ),
            );
          },
          primaryLabel: 'Confirm drop-off',
          canContinue: draft.canContinue,
          onContinue: onContinue,
        );
      case SenderBookingStep.recipient:
        return _RecipientPanel(
          name: receiverName,
          phone: receiverPhone,
          notes: notes,
          onChanged: () => onDraft(
            draft.copyWith(
              receiverName: receiverName.text,
              receiverPhone: receiverPhone.text,
              deliveryNotes: notes.text,
            ),
          ),
          canContinue: draft.canContinue,
          onContinue: onContinue,
        );
      case SenderBookingStep.deliveryTime:
        return _DeliveryTimePanel(
          draft: draft,
          scheduledDate: scheduledDate,
          scheduledJourneyTime: scheduledJourneyTime,
          customWindowStart: customWindowStart,
          customWindowEnd: customWindowEnd,
          onDraft: onDraft,
          canContinue: draft.canContinue,
          onContinue: onContinue,
        );
      case SenderBookingStep.parcel:
        return _ParcelPanel(
          item: item,
          description: description,
          weight: weight,
          iris: _irisMatchesParcel(
            engine.canonicalIrisResult,
            item.text,
            description.text,
          )
              ? engine.canonicalIrisResult
              : null,
          isIrisResolving: engine.isIrisResolving,
          irisErrorMessage: engine.irisErrorMessage,
          parcelPhoto: parcelPhoto,
          parcelPhotoBusy: parcelPhotoBusy,
          parcelPhotoMessage: parcelPhotoMessage,
          photoEstimatedWeightKg: photoEstimatedWeightKg,
          onPhotoTap: onPhotoTap,
          onPhotoRemove: onPhotoRemove,
          onChanged: onParcelChanged,
          canContinue: draft.canContinue,
          onContinue: onContinue,
        );
      case SenderBookingStep.iris:
        return _IrisPanel(engine: engine, draft: draft, onContinue: onContinue);
      case SenderBookingStep.options:
        return _OptionsPanel(
          draft: draft,
          engine: engine,
          onDraft: onDraft,
          onContinue: onContinue,
        );
      case SenderBookingStep.review:
        return const SizedBox.shrink();
      case SenderBookingStep.payment:
        return _PaymentPanel(
          engine: engine,
          draft: draft,
          draftId: draftId,
          senderUid: senderUid,
          onDraft: onDraft,
        );
      case SenderBookingStep.findingRider:
      case SenderBookingStep.liveTracking:
        return const SizedBox.shrink();
    }
  }

  void _search(BuildContext context, String value) {
    if (value.trim().length < 3) {
      context.read<SendPackageBloc>().add(ClearSuggestions());
      return;
    }
    context.read<SendPackageBloc>().add(
          SearchAPlaceEvent(
            query: value,
            lang: Localizations.localeOf(context).languageCode,
          ),
        );
  }
}

double? _manualWeightKg(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('kg', '').trim();
  if (normalized.isEmpty) return null;
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

class _AddressPanel extends StatelessWidget {
  final bool savedForPickup;
  final TextEditingController controller;
  final String hint;
  final String helperText;
  final List suggestions;
  final bool isSearching;
  final String errorText;
  final String? resolutionMessage;
  final bool isResolvingTypedAddress;
  final ValueChanged<String> onChanged;
  final ValueChanged<dynamic> onSuggestion;
  final String primaryLabel;
  final bool canContinue;
  final VoidCallback onContinue;

  const _AddressPanel({
    required this.savedForPickup,
    required this.controller,
    required this.hint,
    required this.helperText,
    required this.suggestions,
    required this.isSearching,
    required this.errorText,
    required this.resolutionMessage,
    required this.isResolvingTypedAddress,
    required this.onChanged,
    required this.onSuggestion,
    required this.primaryLabel,
    required this.canContinue,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final typed = controller.text.trim().toLowerCase();
    final typedAddressCanContinue = isSenderTypedAddressSpecific(typed);
    final buttonEnabled =
        !isResolvingTypedAddress && (canContinue || typedAddressCanContinue);
    dynamic exactSuggestion;
    if (!canContinue && typed.isNotEmpty) {
      for (final suggestion in suggestions) {
        final main = '${suggestion.mainText}'.trim().toLowerCase();
        final description = '${suggestion.description}'.trim().toLowerCase();
        if (main == typed || description == typed) {
          exactSuggestion = suggestion;
          break;
        }
      }
    }
    if (exactSuggestion != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onSuggestion(exactSuggestion);
      });
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            helperText,
            style: const TextStyle(color: _Tokens.muted, height: 1.35),
          ),
        ),
        const SizedBox(height: 10),
        SenderSavedAddressSuggestions(
          forPickup: savedForPickup,
          onSelected: (address) => onSuggestion(address.toSuggestion()),
        ),
        _TextInput(controller: controller, hint: hint, onChanged: onChanged),
        const SizedBox(height: 10),
        if (isSearching || isResolvingTypedAddress)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: _Tokens.lightBlue,
              backgroundColor: Colors.transparent,
            ),
          ),
        if (resolutionMessage != null ||
            (errorText.isNotEmpty && !typedAddressCanContinue))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                resolutionMessage ?? errorText,
                style: const TextStyle(color: _Tokens.muted, height: 1.35),
              ),
            ),
          ),
        if (controller.text.trim().isNotEmpty && !canContinue)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                suggestions.isEmpty
                    ? 'Type the full address and postcode, then continue.'
                    : 'Choose a suggestion, or keep your typed address and continue.',
                style: const TextStyle(
                  color: Color(0xFFD6E4FF),
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (controller.text.trim().isNotEmpty && !canContinue)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 164),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: math.min(suggestions.length, 4),
              itemBuilder: (context, index) {
                final suggestion = suggestions[index];
                return _SuggestionTile(
                  title: '${suggestion.mainText}',
                  subtitle: '${suggestion.subText}',
                  onTap: () => onSuggestion(suggestion),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        _PrimaryButton(
          label: isResolvingTypedAddress ? 'Checking address...' : primaryLabel,
          enabled: buttonEnabled,
          onTap: onContinue,
        ),
      ],
    );
  }
}

class _RecipientPanel extends StatelessWidget {
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController notes;
  final VoidCallback onChanged;
  final bool canContinue;
  final VoidCallback onContinue;

  const _RecipientPanel({
    required this.name,
    required this.phone,
    required this.notes,
    required this.onChanged,
    required this.canContinue,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TextInput(
          controller: name,
          hint: 'Recipient name',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        _TextInput(
          controller: phone,
          hint: 'Recipient phone',
          keyboardType: TextInputType.phone,
          helperText:
              'Used only if the Circum Rider needs to contact the recipient.',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        _TextInput(
          controller: notes,
          hint: 'Delivery instructions (optional)',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        _PrimaryButton(
          label: 'Confirm recipient',
          enabled: canContinue,
          onTap: onContinue,
        ),
      ],
    );
  }
}

class _DeliveryTimePanel extends StatelessWidget {
  final SenderBookingDraft draft;
  final TextEditingController scheduledDate;
  final TextEditingController scheduledJourneyTime;
  final TextEditingController customWindowStart;
  final TextEditingController customWindowEnd;
  final ValueChanged<SenderBookingDraft> onDraft;
  final bool canContinue;
  final VoidCallback onContinue;

  const _DeliveryTimePanel({
    required this.draft,
    required this.scheduledDate,
    required this.scheduledJourneyTime,
    required this.customWindowStart,
    required this.customWindowEnd,
    required this.onDraft,
    required this.canContinue,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final scheduled =
        draft.deliveryTimingType == SenderDeliveryTimingType.scheduled;
    final pastDate = scheduled &&
        scheduledDate.text.trim().isNotEmpty &&
        !isSenderScheduledDateValid(scheduledDate.text);
    final custom = scheduled && draft.scheduledWindow == 'Custom';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose when your Circum Rider should collect and deliver your parcel.',
          style: TextStyle(color: _Tokens.muted, height: 1.35),
        ),
        const SizedBox(height: 14),
        _RadioGlassTile(
          selected: !scheduled,
          title: 'Deliver now',
          caption:
              'Start finding a Circum Rider as soon as payment is complete.',
          onTap: () => onDraft(
            draft.copyWith(
              deliveryTimingType: SenderDeliveryTimingType.now,
              scheduledDate: '',
              scheduledWindow: '',
              customWindowStart: '',
              customWindowEnd: '',
            ),
          ),
        ),
        const SizedBox(height: 10),
        _RadioGlassTile(
          selected: scheduled,
          title: 'Schedule for later',
          caption: 'Choose a date and time window.',
          onTap: () => onDraft(
            draft.copyWith(
              deliveryTimingType: SenderDeliveryTimingType.scheduled,
            ),
          ),
        ),
        if (scheduled) ...[
          const SizedBox(height: 14),
          const _SectionLabel('Preferred date'),
          const SizedBox(height: 8),
          _ScheduleDateSelector(
            selectedDate: draft.scheduledDate,
            onSelected: (value) {
              scheduledDate.text = value;
              onDraft(draft.copyWith(
                scheduledDate: value,
                scheduledJourneyAt: _scheduledJourneyIso(
                  value,
                  scheduledJourneyTime.text,
                ),
              ));
            },
          ),
          if (pastDate) ...[
            const SizedBox(height: 6),
            const Text(
              'Choose today or a future date',
              style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          const _SectionLabel('Exact journey time (London)'),
          const SizedBox(height: 8),
          _TextInput(
            controller: scheduledJourneyTime,
            hint: 'HH:MM',
            keyboardType: TextInputType.datetime,
            onChanged: (value) => onDraft(draft.copyWith(
              scheduledJourneyAt: _scheduledJourneyIso(
                draft.scheduledDate,
                value,
              ),
            )),
          ),
          const SizedBox(height: 12),
          const _SectionLabel('Preferred collection window'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Morning', 'Afternoon', 'Evening', 'Custom'].map((
              window,
            ) {
              return _ToggleChip(
                label: window,
                selected: draft.scheduledWindow == window,
                onTap: () => onDraft(draft.copyWith(scheduledWindow: window)),
              );
            }).toList(),
          ),
          if (custom) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TextInput(
                    controller: customWindowStart,
                    hint: 'Start HH:MM',
                    keyboardType: TextInputType.datetime,
                    errorText: customWindowStart.text.trim().isNotEmpty &&
                            !RegExp(
                              r'^\d{2}:\d{2}$',
                            ).hasMatch(customWindowStart.text.trim())
                        ? 'Use HH:MM'
                        : null,
                    onChanged: (value) =>
                        onDraft(draft.copyWith(customWindowStart: value)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TextInput(
                    controller: customWindowEnd,
                    hint: 'End HH:MM',
                    keyboardType: TextInputType.datetime,
                    errorText: customWindowEnd.text.trim().isNotEmpty &&
                            !isSenderCustomWindowValid(
                              customWindowStart.text,
                              customWindowEnd.text,
                            )
                        ? 'After start'
                        : null,
                    onChanged: (value) =>
                        onDraft(draft.copyWith(customWindowEnd: value)),
                  ),
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 14),
        const _InfoNote(
          text:
              "Scheduled deliveries depend on Circum Rider availability. We'll confirm before the delivery begins.",
        ),
        const SizedBox(height: 14),
        _PrimaryButton(
          label: 'Confirm delivery time',
          enabled: canContinue,
          onTap: onContinue,
        ),
      ],
    );
  }
}

class _ScheduleDateSelector extends StatelessWidget {
  final String selectedDate;
  final ValueChanged<String> onSelected;

  const _ScheduleDateSelector({
    required this.selectedDate,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final dates = senderScheduleDateOptions();
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = dates[index];
          final value = senderScheduleDateValue(date);
          final selected = selectedDate == value;
          return _ScheduleDateCard(
            day: senderScheduleDayLabel(date),
            date: senderScheduleMonthDayLabel(date),
            selected: selected,
            onTap: () => onSelected(value),
          );
        },
      ),
    );
  }
}

class _ScheduleDateCard extends StatelessWidget {
  final String day;
  final String date;
  final bool selected;
  final VoidCallback onTap;

  const _ScheduleDateCard({
    required this.day,
    required this.date,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 84,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? _Tokens.blue.withValues(alpha: .18)
              : Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _Tokens.lightBlue : _Tokens.border,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : _Tokens.muted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? _Tokens.lightBlue : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParcelPanel extends StatelessWidget {
  final TextEditingController item;
  final TextEditingController description;
  final TextEditingController weight;
  final dynamic iris;
  final bool isIrisResolving;
  final String irisErrorMessage;
  final XFile? parcelPhoto;
  final bool parcelPhotoBusy;
  final String? parcelPhotoMessage;
  final double? photoEstimatedWeightKg;
  final VoidCallback onPhotoTap;
  final VoidCallback onPhotoRemove;
  final VoidCallback onChanged;
  final bool canContinue;
  final VoidCallback onContinue;

  const _ParcelPanel({
    required this.item,
    required this.description,
    required this.weight,
    required this.iris,
    required this.isIrisResolving,
    required this.irisErrorMessage,
    required this.parcelPhoto,
    required this.parcelPhotoBusy,
    required this.parcelPhotoMessage,
    required this.photoEstimatedWeightKg,
    required this.onPhotoTap,
    required this.onPhotoRemove,
    required this.onChanged,
    required this.canContinue,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _IrisInputCard(
          item: item,
          description: description,
          weight: weight,
          iris: iris,
          isIrisResolving: isIrisResolving,
          irisErrorMessage: irisErrorMessage,
          parcelPhoto: parcelPhoto,
          parcelPhotoBusy: parcelPhotoBusy,
          parcelPhotoMessage: parcelPhotoMessage,
          photoEstimatedWeightKg: photoEstimatedWeightKg,
          onPhotoTap: onPhotoTap,
          onPhotoRemove: onPhotoRemove,
          onChanged: onChanged,
          canContinue: canContinue,
          onContinue: onContinue,
        ),
      ],
    );
  }
}

class _IrisInputCard extends StatelessWidget {
  final TextEditingController item;
  final TextEditingController description;
  final TextEditingController weight;
  final dynamic iris;
  final bool isIrisResolving;
  final String irisErrorMessage;
  final XFile? parcelPhoto;
  final bool parcelPhotoBusy;
  final String? parcelPhotoMessage;
  final double? photoEstimatedWeightKg;
  final VoidCallback onPhotoTap;
  final VoidCallback onPhotoRemove;
  final VoidCallback onChanged;
  final bool canContinue;
  final VoidCallback onContinue;

  const _IrisInputCard({
    required this.item,
    required this.description,
    required this.weight,
    required this.iris,
    required this.isIrisResolving,
    required this.irisErrorMessage,
    required this.parcelPhoto,
    required this.parcelPhotoBusy,
    required this.parcelPhotoMessage,
    required this.photoEstimatedWeightKg,
    required this.onPhotoTap,
    required this.onPhotoRemove,
    required this.onChanged,
    required this.canContinue,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final hasWeight = _irisEstimatedWeightDisplay(iris) != 'Unavailable';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xAA111827),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _Tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IrisInputHeader(isResolving: isIrisResolving, hasResult: hasWeight),
          const SizedBox(height: 14),
          _TextInput(
            controller: item,
            hint: 'Item and quantity, e.g. 2 printers',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 10),
          _TextInput(
            controller: description,
            hint: 'Extra details (optional)',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TextInput(
                  controller: weight,
                  hint: 'Weight if you know it (kg)',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 10),
              _ParcelPhotoAction(
                photo: parcelPhoto,
                busy: parcelPhotoBusy,
                onTap: onPhotoTap,
              ),
            ],
          ),
          _ParcelPhotoStatus(
            photo: parcelPhoto,
            busy: parcelPhotoBusy,
            message: parcelPhotoMessage,
            estimatedWeightKg: photoEstimatedWeightKg,
            onRemove: onPhotoRemove,
          ),
          if (hasWeight) ...[
            const SizedBox(height: 12),
            _IrisInputResultCard(iris: iris),
          ],
          const SizedBox(height: 12),
          _PrimaryButton(
            label: isIrisResolving
                ? 'Checking weight...'
                : !hasWeight
                    ? 'Check weight with IRIS'
                    : 'Choose Delivery Options',
            enabled: canContinue && !isIrisResolving,
            onTap: onContinue,
          ),
          const SizedBox(height: 10),
          const Text(
            'IRIS estimates the parcel before pricing. Your Circum Rider still confirms the item at collection.',
            style: TextStyle(color: _Tokens.muted, height: 1.35, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _IrisInputHeader extends StatelessWidget {
  final bool isResolving;
  final bool hasResult;

  const _IrisInputHeader({required this.isResolving, required this.hasResult});

  @override
  Widget build(BuildContext context) {
    final status = isResolving
        ? 'IRIS is reading your description'
        : hasResult
            ? 'IRIS has an estimate'
            : 'IRIS is ready when you are';
    return Row(
      children: [
        _IrisPresenceOrb(active: isResolving),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Describe your item',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                status,
                style: const TextStyle(
                  color: _Tokens.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.info_outline_rounded, color: _Tokens.muted, size: 18),
      ],
    );
  }
}

class _IrisPresenceOrb extends StatelessWidget {
  final bool active;

  const _IrisPresenceOrb({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_Tokens.iris, _Tokens.lightBlue],
        ),
        boxShadow: [
          BoxShadow(
            color: _Tokens.lightBlue.withValues(alpha: active ? .42 : .22),
            blurRadius: active ? 28 : 16,
            spreadRadius: active ? 3 : 1,
          ),
        ],
      ),
      child: const Icon(
        Icons.auto_awesome_rounded,
        color: Colors.white,
        size: 18,
      ),
    );
  }
}

class _ParcelPhotoAction extends StatelessWidget {
  final XFile? photo;
  final bool busy;
  final VoidCallback onTap;

  const _ParcelPhotoAction({
    required this.photo,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final attached = photo != null;
    final label = attached ? 'Replace parcel photo' : 'Add parcel photo';
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: attached
                  ? const Color(0xFF22C55E).withValues(alpha: .14)
                  : const Color(0xFF1D4ED8).withValues(alpha: .72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: attached
                    ? const Color(0xFF86EFAC).withValues(alpha: .45)
                    : _Tokens.lightBlue.withValues(alpha: .8),
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (attached ? const Color(0xFF22C55E) : _Tokens.lightBlue)
                          .withValues(alpha: .18),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _Tokens.lightBlue,
                      ),
                    )
                  : attached
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF86EFAC),
                          size: 23,
                        )
                      : const _TinyCameraGlyph(),
            ),
          ),
        ),
      ),
    );
  }
}

class _TinyCameraGlyph extends StatelessWidget {
  const _TinyCameraGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 23,
      height: 19,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 4,
            child: Container(
              width: 21,
              height: 15,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white, width: 1.8),
              ),
            ),
          ),
          Positioned(
            top: 1,
            left: 6,
            child: Container(
              width: 8,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParcelPhotoStatus extends StatelessWidget {
  final XFile? photo;
  final bool busy;
  final String? message;
  final double? estimatedWeightKg;
  final VoidCallback onRemove;

  const _ParcelPhotoStatus({
    required this.photo,
    required this.busy,
    required this.message,
    required this.estimatedWeightKg,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final attached = photo != null;
    final parts = <String>[
      if (busy)
        'Checking photo...'
      else if (message != null && message!.trim().isNotEmpty)
        message!.trim()
      else if (attached)
        'Photo added.'
      else
        'Optional photo helps IRIS confirm handling.',
      if (estimatedWeightKg != null)
        'Visual estimate ${estimatedWeightKg!.toStringAsFixed(2)} kg.',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: attached ? const Color(0xFF86EFAC) : _Tokens.muted,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join(' '),
              style: const TextStyle(
                color: _Tokens.muted,
                height: 1.25,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (attached && !busy)
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove parcel photo',
              icon: const Icon(Icons.close_rounded, size: 16),
              color: _Tokens.muted,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

class _IrisInputResultCard extends StatelessWidget {
  final dynamic iris;

  const _IrisInputResultCard({required this.iris});

  @override
  Widget build(BuildContext context) {
    final weight = _irisEstimatedWeightDisplay(iris);
    final band = _irisSizeDisplay(iris);
    final vehicle = _minimumVehicleLabel(iris?.recommendedVehicle);
    return _IrisPremiumSummaryCard(
      title: iris?.itemName.isNotEmpty == true ? iris!.itemName : 'Parcel',
      weight: weight,
      size: band,
      vehicle: vehicle,
      handling: _handlingRequirements(iris),
      confidence: iris?.confidenceLabel ?? 'IRIS estimate',
      compact: true,
    );
  }
}

class _IrisPremiumSummaryCard extends StatelessWidget {
  final String title;
  final String weight;
  final String size;
  final String vehicle;
  final String handling;
  final String confidence;
  final String? vanguard;
  final bool compact;

  const _IrisPremiumSummaryCard({
    required this.title,
    required this.weight,
    required this.size,
    required this.vehicle,
    required this.handling,
    required this.confidence,
    this.vanguard,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final chip = _confidenceChip(confidence);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 14 : 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 20 : 26),
          border: Border.all(color: _Tokens.lightBlue.withValues(alpha: .30)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _Tokens.lightBlue.withValues(alpha: .16),
              _Tokens.midnight.withValues(alpha: .82),
              _Tokens.iris.withValues(alpha: .07),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: _Tokens.blue.withValues(alpha: .18),
              blurRadius: 30,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF86EFAC),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'IRIS Analysis Complete',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _InfoChip(chip),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 21 : 26,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 14),
            _IrisWeightHero(weight: weight, compact: compact),
            const SizedBox(height: 12),
            _IrisSummaryFact(
              icon: Icons.two_wheeler_rounded,
              label: 'Recommended Vehicle',
              value: vehicle,
              helper: 'Fastest suitable vehicle for this parcel.',
            ),
            _IrisSummaryFact(
              icon: Icons.inventory_2_outlined,
              label: 'Weight band',
              value: size,
            ),
            _IrisSummaryFact(
              icon: Icons.shield_outlined,
              label: 'Handling',
              value: handling,
            ),
            const _IrisSummaryFact(
              icon: Icons.verified_user_rounded,
              label: 'Verification',
              value: 'Rider confirms at collection',
            ),
            _IrisSummaryFact(
              icon: Icons.track_changes_rounded,
              label: 'Confidence',
              value: confidence,
            ),
            if (vanguard != null)
              _IrisSummaryFact(
                icon: Icons.security_rounded,
                label: 'Vanguard',
                value: vanguard!,
              ),
          ],
        ),
      ),
    );
  }
}

class _IrisWeightHero extends StatelessWidget {
  final String weight;
  final bool compact;

  const _IrisWeightHero({required this.weight, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 12 : 15,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estimated Weight',
            style: TextStyle(
              color: _Tokens.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            weight,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 30 : 38,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _IrisSummaryFact extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? helper;

  const _IrisSummaryFact({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _Tokens.lightBlue, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _Tokens.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                if (helper != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    helper!,
                    style: const TextStyle(
                      color: _Tokens.muted,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IrisPanel extends StatelessWidget {
  final SendPackageState engine;
  final SenderBookingDraft draft;
  final VoidCallback onContinue;

  const _IrisPanel({
    required this.engine,
    required this.draft,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final iris = engine.canonicalIrisResult;
    final vehicle = _minimumVehicleLabel(iris?.recommendedVehicle);
    return Column(
      children: [
        _IrisOrb(active: engine.isIrisResolving),
        const SizedBox(height: 12),
        if (engine.isIrisResolving) ...[
          const _IrisAnalysisProgress(),
        ] else if (engine.irisErrorMessage.isNotEmpty) ...[
          Text(
            engine.irisErrorMessage,
            style: const TextStyle(color: _Tokens.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          _PrimaryButton(
            label: 'Retry',
            enabled: true,
            onTap: () => context.read<SendPackageBloc>().add(
                  RequestCanonicalIrisEstimate(
                    itemName: draft.itemName,
                    quantity: senderQuantityFromItemName(draft.itemName),
                    description: draft.itemDescription,
                    declaredWeightText: draft.weightLabel,
                    fragile: false,
                    highValue: false,
                  ),
                ),
          ),
        ] else ...[
          if (iris != null) const _IrisSuccessPulse(),
          if (iris?.partial == true)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Some estimate details are unavailable right now.',
                style: TextStyle(color: _Tokens.muted, height: 1.35),
              ),
            ),
          if (engine.irisWeightReviewMessage.isNotEmpty) ...[
            _InfoNote(text: engine.irisWeightReviewMessage),
            const SizedBox(height: 10),
          ],
          _IrisPremiumSummaryCard(
            title: iris?.itemName.isNotEmpty == true
                ? iris!.itemName
                : (draft.itemName.isEmpty ? 'Awaiting IRIS' : draft.itemName),
            weight: _finalWeightDisplay(draft, iris),
            size: _irisSizeDisplay(iris),
            vehicle: vehicle,
            handling: _handlingRequirements(iris),
            confidence: iris?.confidenceLabel ?? 'Awaiting IRIS',
            vanguard: iris?.vanguardRequired == true
                ? _irisVanguardDisplay(iris)
                : null,
          ),
        ],
        ExpansionTile(
          collapsedIconColor: _Tokens.lightBlue,
          iconColor: _Tokens.lightBlue,
          title: const Text(
            'How IRIS reached this estimate',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          children: [..._customerIrisReasons(iris, draft).map(_ReasonLine.new)],
        ),
        _PrimaryButton(
          label: 'Choose Delivery Options',
          enabled: true,
          onTap: onContinue,
        ),
      ],
    );
  }
}

class _IrisAnalysisProgress extends StatefulWidget {
  const _IrisAnalysisProgress();

  @override
  State<_IrisAnalysisProgress> createState() => _IrisAnalysisProgressState();
}

class _IrisAnalysisProgressState extends State<_IrisAnalysisProgress>
    with SingleTickerProviderStateMixin {
  static const _stages = [
    'Identifying your parcel...',
    'Comparing verified parcel data...',
    'Estimating dimensions...',
    'Calculating weight...',
    'Selecting the best vehicle...',
    'Preparing recommendation...',
    'Complete ✓',
  ];

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2450),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final index = (_controller.value * _stages.length).floor().clamp(
              0,
              _stages.length - 1,
            );
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 3,
                value: (_controller.value + .08).clamp(0, 1),
                color: index == _stages.length - 1
                    ? const Color(0xFF22C55E)
                    : _Tokens.iris,
                backgroundColor: Colors.white.withValues(alpha: .06),
              ),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                _stages[index],
                key: ValueKey(_stages[index]),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _Tokens.muted,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _IrisSuccessPulse extends StatelessWidget {
  const _IrisSuccessPulse();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .86, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF22C55E).withValues(alpha: .34),
              ),
            ),
            child: const Text(
              'Complete ✓',
              style: TextStyle(
                color: Color(0xFF86EFAC),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  }
}

const _senderVehicleOrder = ['Motorbike', 'Car', 'Van'];

List<String> _vehicleMatches(String? raw) {
  final normalized = (raw ?? '').trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'any') return const ['Motorbike'];
  final vehicles = <String>[];
  void addIf(RegExp pattern, String label) {
    if (pattern.hasMatch(normalized) && !vehicles.contains(label)) {
      vehicles.add(label);
    }
  }

  addIf(
    RegExp(
      r'\b(bike|bicycle|cycle|e-bike|ebike|electric bike|motorbike|motorcycle|moped|scooter)\b',
    ),
    'Motorbike',
  );
  addIf(RegExp(r'\bcar\b'), 'Car');
  addIf(RegExp(r'\bvan\b'), 'Van');
  return vehicles.isEmpty ? const ['Motorbike'] : vehicles;
}

String _minimumVehicleLabel(String? raw) {
  final matches = _vehicleMatches(raw);
  return matches.first;
}

List<String> _allowedVehicleUpgrades(String? raw) {
  final minimum = _minimumVehicleLabel(raw);
  final start = _senderVehicleOrder.indexOf(minimum);
  if (start < 0) return const ['Motorbike', 'Car', 'Van'];
  return _senderVehicleOrder.sublist(start);
}

String _selectedVehicleFor(SenderBookingDraft draft, dynamic iris) {
  final allowed = _allowedVehicleUpgrades(iris?.recommendedVehicle);
  final selected = draft.selectedVehicle.trim();
  return allowed.contains(selected) ? selected : allowed.first;
}

bool _irisHasHandling(dynamic iris, String needle) {
  final target = needle.trim().toLowerCase();
  final values = <String>[
    ...?iris?.handlingRequirements,
    '${iris?.category ?? ''}',
    '${iris?.vanguardRequiredReason ?? ''}',
    ...?iris?.reasons,
  ].join(' ').toLowerCase();
  return values.contains(target);
}

bool _irisRequiresIncludedVanguard(dynamic iris, {Object? business}) {
  return iris?.vanguardRequired == true || business != null;
}

double? _nullableDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}'.trim());
}

bool _irisMatchesParcel(dynamic iris, String itemName, String description) {
  if (iris == null) return false;
  final expected = [
    itemName,
    description,
  ].where((value) => value.trim().isNotEmpty).join(' ').trim().toLowerCase();
  if (expected.isEmpty) return false;
  final actual = '${iris.itemName ?? ''}'.trim().toLowerCase();
  if (actual.isEmpty) return false;
  final item = itemName.trim().toLowerCase();
  if ((item.isNotEmpty && actual.contains(item)) || expected.contains(actual)) {
    return true;
  }
  final expectedTokens = expected
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.length > 2)
      .map(
        (token) =>
            token.endsWith('s') ? token.substring(0, token.length - 1) : token,
      )
      .toSet();
  final actualTokens = actual
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.length > 2)
      .map(
        (token) =>
            token.endsWith('s') ? token.substring(0, token.length - 1) : token,
      );
  return actualTokens.any(expectedTokens.contains);
}

String _irisEstimatedWeightDisplay(dynamic iris) {
  final suggested = iris?.totalWeightKg;
  if (suggested == null) return 'Unavailable';
  return '${suggested.toStringAsFixed(2)} kg';
}

String _finalWeightDisplay(SenderBookingDraft draft, dynamic iris) {
  final entered = _manualWeightKg(draft.weightLabel);
  final suggested = iris?.totalWeightKg;
  final weights = [
    if (entered != null && entered > 0) entered,
    if (suggested is num && suggested > 0) suggested.toDouble(),
  ];
  if (weights.isEmpty) return 'Unavailable';
  return '${weights.reduce(math.max).toStringAsFixed(2)} kg';
}

String _irisSizeDisplay(dynamic iris) {
  final size = '${iris?.weightBand ?? ''}'.trim();
  return size.isEmpty ? 'Unavailable' : size;
}

String _irisVanguardDisplay(dynamic iris) {
  final reason = '${iris?.vanguardRequiredReason ?? ''}'.trim();
  if (iris?.vanguardRequired == true) {
    return reason.isEmpty ? 'Included' : 'Included • $reason';
  }
  return reason.isEmpty ? 'Available' : 'Available • $reason';
}

String _handlingRequirements(dynamic iris) {
  final requirements = <String>[
    ...?iris?.handlingRequirements,
    if (iris?.vanguardRequired == true) 'Vanguard included',
  ];
  return requirements.isEmpty
      ? 'Standard parcel care'
      : requirements.toSet().join(' · ');
}

String _confidenceChip(String confidence) {
  final value = confidence.trim();
  final number = RegExp(r'\d+').firstMatch(value);
  final score = number == null ? null : int.tryParse(number.group(0)!);
  if (score == null) return value.isEmpty ? 'Confidence pending' : value;
  if (score >= 85) return 'High confidence';
  if (score >= 60) return 'Medium confidence';
  return 'Low confidence';
}

List<String> _customerIrisReasons(dynamic iris, SenderBookingDraft draft) {
  if (iris == null) {
    return const [
      'IRIS will compare your parcel with verified parcel data.',
      'Weight and vehicle guidance appear after analysis completes.',
      'Rider confirms at collection before departure.',
    ];
  }
  final item = '${iris.itemName}'.trim().isEmpty
      ? 'your parcel'
      : '${iris.itemName}'.trim();
  final reasons = <String>[
    if ('${iris.explanation}'.trim().isNotEmpty) '${iris.explanation}'.trim(),
    'Matched to a verified $item profile.',
    if (iris.totalWeightKg != null)
      'Estimated weight based on known dimensions.',
    '${_minimumVehicleLabel(iris.recommendedVehicle)} is the minimum suitable vehicle.',
    'Rider confirms at collection before departure.',
  ];
  return reasons.toSet().toList(growable: false);
}

bool _routeReadyForQuote(
  SendPackageState engine, [
  SenderBookingDraft? draft,
]) {
  return engine.distance != null ||
      engine.pickupCoordinate != null && engine.desinationCoordinate != null ||
      draft?.pickupLat != null &&
          draft?.pickupLng != null &&
          draft?.dropoffLat != null &&
          draft?.dropoffLng != null;
}

class _OptionsPanel extends StatelessWidget {
  final SenderBookingDraft draft;
  final SendPackageState engine;
  final ValueChanged<SenderBookingDraft> onDraft;
  final VoidCallback onContinue;

  const _OptionsPanel({
    required this.draft,
    required this.engine,
    required this.onDraft,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final quoteTotal = engine.senderQuoteTotal;
    final routeReady = _routeReadyForQuote(engine, draft);
    final iris = engine.canonicalIrisResult;
    final business = BusinessJourneyScope.maybeOf(context);
    final includedVanguard = _irisRequiresIncludedVanguard(
      iris,
      business: business,
    );
    final allowedVehicles = _allowedVehicleUpgrades(iris?.recommendedVehicle);
    final minimumVehicle = allowedVehicles.first;
    final selectedVehicle = _selectedVehicleFor(draft, iris);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'IRIS sets the minimum safe vehicle. You can choose that vehicle or upgrade.',
          style: TextStyle(color: _Tokens.muted, height: 1.35),
        ),
        const SizedBox(height: 14),
        const _SectionLabel('Vehicle'),
        const SizedBox(height: 8),
        _VehicleUpgradeSelector(
          values: allowedVehicles,
          selected: selectedVehicle,
          recommended: minimumVehicle,
          onSelected: (value) {
            final next = draft.copyWith(
              selectedVehicle: value,
              irisVehicle: value,
            );
            onDraft(next);
            _requestQuote(context, next);
          },
        ),
        const SizedBox(height: 16),
        const _SectionLabel('Delivery speed'),
        const SizedBox(height: 8),
        _DeliverySpeedSelector(
          values: senderDeliverySpeeds,
          selected: draft.selectedOption,
          loading: engine.isSenderQuoteLoading,
          options: engine.senderQuoteSpeedOptions,
          onSelected: (value) {
            final next = draft.copyWith(selectedOption: value);
            onDraft(next);
            _requestQuote(context, next);
          },
        ),
        const SizedBox(height: 16),
        _SectionLabel(includedVanguard ? 'Vanguard Included' : 'Vanguard'),
        const SizedBox(height: 8),
        _AddOnTile(
          selected: includedVanguard || draft.vanguard,
          title: senderVanguardProtocolLabel,
          price: includedVanguard
              ? 'Included'
              : '+£${senderVanguardAddOnPriceGbp.toStringAsFixed(2)}',
          subtitle: includedVanguard
              ? 'Protected throughout this delivery. Priority dispute support, enhanced custody tracking, and trusted rider prioritisation.'
              : 'Add Vanguard for pickup verification, secure custody, secure transit, and secure handover.',
          icon: Icons.shield_outlined,
          onTap: () {
            if (includedVanguard) return;
            final next = draft.copyWith(vanguard: !draft.vanguard);
            onDraft(next);
            _requestQuote(context, next);
          },
        ),
        if (includedVanguard || draft.vanguard) ...[
          const SizedBox(height: 8),
          Text(
            includedVanguard ? '✓ Vanguard Included' : '✓ Vanguard Added',
            style: TextStyle(
              color: _Tokens.lightBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _PaymentCard(
          child: Column(
            children: [
              if (engine.senderQuoteError.isNotEmpty)
                _QuoteUnavailable(onRetry: () => _requestQuote(context, draft))
              else if (!routeReady)
                const _RouteQuotePending()
              else if (engine.isSenderQuoteLoading || quoteTotal == null)
                const _QuoteSkeleton()
              else
                _BackendPricingBreakdown(engine: engine),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PrimaryButton(
          label: 'Continue to Review',
          enabled:
              routeReady && quoteTotal != null && !engine.isSenderQuoteLoading,
          onTap: onContinue,
        ),
      ],
    );
  }

  void _requestQuote(BuildContext context, SenderBookingDraft draft) {
    final engine = context.read<SendPackageBloc>().state;
    if (!_routeReadyForQuote(engine, draft)) {
      return;
    }
    final iris = engine.canonicalIrisResult;
    final business = BusinessJourneyScope.maybeOf(context);
    final includedVanguard = _irisRequiresIncludedVanguard(
      iris,
      business: business,
    );
    context.read<SendPackageBloc>().add(
          RequestSenderBookingQuote(
            selectedSpeed: draft.selectedOption,
            vanguardProtocolEnabled: includedVanguard || draft.vanguard,
            itemName: draft.itemName,
            description: draft.itemDescription,
            weightKg: _manualWeightKg(draft.weightLabel) ?? 0,
            fragile: _irisHasHandling(iris, 'fragile'),
            highValue: _irisHasHandling(iris, 'high value'),
            selectedVehicle: _selectedVehicleFor(draft, iris),
            scheduledJourneyAt: draft.scheduledJourneyAt,
            scheduledDate: draft.scheduledDate,
          ),
        );
  }
}

class _DeliverySpeedSelector extends StatelessWidget {
  final List<String> values;
  final String selected;
  final bool loading;
  final List<Map<String, dynamic>> options;
  final ValueChanged<String> onSelected;

  const _DeliverySpeedSelector({
    required this.values,
    required this.selected,
    required this.loading,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && options.isEmpty) {
      return const Text(
        'Loading live prices for Standard and Express.',
        style: TextStyle(color: _Tokens.muted, fontSize: 12),
      );
    }
    if (options.isEmpty) {
      return const Text(
        'Live prices appear after route and IRIS checks are complete.',
        style: TextStyle(color: _Tokens.muted, fontSize: 12),
      );
    }
    return Row(
      children: values.map((speed) {
        final option = _speedQuoteOption(options, speed);
        final active = speed == selected;
        final price =
            option == null ? 'Pending' : _speedQuoteStandalonePrice(option);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: speed == values.last ? 0 : 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelected(speed),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                constraints: const BoxConstraints(minHeight: 88),
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? _Tokens.lightBlue.withValues(alpha: .18)
                      : Colors.white.withValues(alpha: .045),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: active ? _Tokens.lightBlue : _Tokens.border,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: _Tokens.blue.withValues(alpha: .30),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ]
                      : const [],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (active) ...[
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: _Tokens.lightBlue,
                                  size: 15,
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  speed,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        active ? Colors.white : _Tokens.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .10),
                            ),
                          ),
                          child: Text(
                            price,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      speed.toLowerCase() == 'express'
                          ? 'Priority rider matching'
                          : 'Regular matching',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: speed.toLowerCase() == 'express'
                            ? _Tokens.lightBlue
                            : _Tokens.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SelectedSpeedNote extends StatelessWidget {
  final String speed;

  const _SelectedSpeedNote({required this.speed});

  @override
  Widget build(BuildContext context) {
    final express = speed.trim().toLowerCase() == 'express';
    return _InfoNote(
      text: express
          ? 'Express makes this booking a priority for rider matching and urgent pickup.'
          : 'Standard uses regular rider matching.',
    );
  }
}

Map<String, dynamic>? _speedQuoteOption(
  List<Map<String, dynamic>> options,
  String speed,
) {
  final target = speed.trim().toLowerCase();
  for (final option in options) {
    final optionSpeed = '${option['speed'] ?? option['selectedSpeed'] ?? ''}'
        .trim()
        .toLowerCase();
    if (optionSpeed == target) {
      return option;
    }
    final optionKey = '${option['key'] ?? option['type'] ?? ''}'
        .trim()
        .toLowerCase()
        .replaceAll('_', ' ');
    if (optionKey == target ||
        optionKey == '$target service' ||
        optionKey == '$target delivery') {
      return option;
    }
    final optionLabel = '${option['label'] ?? ''}'.trim().toLowerCase();
    if (optionLabel == target ||
        optionLabel == '$target service' ||
        optionLabel == '$target delivery') {
      return option;
    }
  }
  return null;
}

String _speedQuoteStandalonePrice(Map<String, dynamic>? option) {
  if (option == null) return 'Pending';
  final value = option['speedAdjustment'] ??
      option['speedSurcharge'] ??
      option['deliverySpeedFee'] ??
      option['serviceFee'];
  if (value is num) {
    final amount = value.toDouble();
    return amount <= 0 ? 'Included' : '+${formatSenderCurrency(amount)}';
  }
  final parsed = double.tryParse('$value');
  if (parsed == null) return 'Pending';
  return parsed <= 0 ? 'Included' : '+${formatSenderCurrency(parsed)}';
}

class _SenderReviewDeliveryScreen extends StatefulWidget {
  final SenderBookingDraft draft;
  final SendPackageState engine;
  final VoidCallback onBack;
  final VoidCallback onCancel;
  final VoidCallback onContinue;

  const _SenderReviewDeliveryScreen({
    required this.draft,
    required this.engine,
    required this.onBack,
    required this.onCancel,
    required this.onContinue,
  });

  @override
  State<_SenderReviewDeliveryScreen> createState() =>
      _SenderReviewDeliveryScreenState();
}

class _SenderReviewDeliveryScreenState
    extends State<_SenderReviewDeliveryScreen> {
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final total = widget.engine.senderQuoteTotal;
    final canContinue = total != null && !widget.engine.isSenderQuoteLoading;
    final pickup = widget.engine.pickupLocation ?? widget.draft.pickupAddress;
    final dropoff =
        widget.engine.destinationLocation ?? widget.draft.dropoffAddress;
    final speed = widget.engine.senderQuoteSpeed?.trim().isNotEmpty == true
        ? widget.engine.senderQuoteSpeed!.trim()
        : widget.draft.selectedOption;

    return ColoredBox(
      color: _Tokens.bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: _SenderMobileMap(
              active: true,
              engine: widget.engine,
              showDestination: widget.engine.desinationCoordinate != null ||
                  widget.draft.dropoffAddress.trim().isNotEmpty,
              showVanguardShield: widget.draft.vanguard,
              distanceKm: widget.engine.distance,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _ReviewTopBar(onBack: widget.onBack, onCancel: widget.onCancel),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    child: ListView(
                      key: ValueKey(widget.engine.senderQuoteId ?? speed),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        18 + media.padding.bottom,
                      ),
                      children: [
                        _ReviewRoutePanel(
                          engine: widget.engine,
                          draft: widget.draft,
                          selectedSpeed: speed,
                          onCancel: widget.onCancel,
                        ),
                        const SizedBox(height: 14),
                        _ReviewSheet(
                          child: Column(
                            children: [
                              const _ReviewGrabber(),
                              _ExpandableReviewAddressRow(
                                icon: Icons.location_on_outlined,
                                label: 'Pickup',
                                summary: _reviewAddressSummary(
                                  pickup,
                                  widget.engine.pickupLocality,
                                ),
                                fullAddress: pickup,
                              ),
                              _ExpandableReviewAddressRow(
                                icon: Icons.flag_outlined,
                                label: 'Drop-off',
                                summary: _reviewAddressSummary(
                                  dropoff,
                                  widget.engine.destinationLocality,
                                ),
                                fullAddress: dropoff,
                              ),
                              _ReviewListRow(
                                icon: Icons.person_outline_rounded,
                                label: 'Recipient',
                                value: widget.draft.receiverName.trim().isEmpty
                                    ? 'Recipient pending'
                                    : widget.draft.receiverName.trim(),
                                secondary: _maskSenderPhoneForReview(
                                  widget.draft.receiverPhone,
                                ),
                              ),
                              _ReviewListRow(
                                icon: Icons.inventory_2_outlined,
                                label: 'Parcel',
                                value: widget.draft.itemName.trim().isEmpty
                                    ? 'Parcel pending'
                                    : widget.draft.itemName.trim(),
                                secondary: _reviewIrisEstimate(
                                  widget.engine,
                                  widget.draft,
                                ),
                                badge: widget.draft.vanguard
                                    ? const _VanguardReviewBadge()
                                    : null,
                              ),
                              if (widget
                                  .engine.irisWeightReviewMessage.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: _InfoNote(
                                    text: widget.engine.irisWeightReviewMessage,
                                  ),
                                ),
                              _ReviewListRow(
                                icon: Icons.schedule_rounded,
                                label: 'Delivery time',
                                value: widget.draft.deliveryTimeSummary,
                              ),
                              _ReviewListRow(
                                icon: Icons.speed_rounded,
                                label: 'Delivery priority',
                                value: speed,
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: _SelectedSpeedNote(speed: speed),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: _BackendPricingBreakdown(
                                  engine: widget.engine,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _ReviewBottomBar(
                  total: total,
                  loading: widget.engine.isSenderQuoteLoading,
                  error: widget.engine.senderQuoteError,
                  canContinue: canContinue,
                  onContinue: widget.onContinue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onCancel;

  const _ReviewTopBar({required this.onBack, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        children: [
          _ReviewIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            label: 'Back',
            onTap: onBack,
          ),
          const Expanded(
            child: Text(
              'Review your delivery',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: .1,
              ),
            ),
          ),
          _BookingCancelPill(onTap: onCancel),
        ],
      ),
    );
  }
}

class _ReviewIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ReviewIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .055),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _Tokens.border),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _ReviewRoutePanel extends StatefulWidget {
  final SendPackageState engine;
  final SenderBookingDraft draft;
  final String selectedSpeed;
  final VoidCallback onCancel;

  const _ReviewRoutePanel({
    required this.engine,
    required this.draft,
    required this.selectedSpeed,
    required this.onCancel,
  });

  @override
  State<_ReviewRoutePanel> createState() => _ReviewRoutePanelState();
}

class _ReviewRoutePanelState extends State<_ReviewRoutePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routeConfirmed = widget.engine.polylineCoordinates.isNotEmpty ||
        widget.engine.polylines.isNotEmpty ||
        widget.engine.distance != null;
    final pickup = _reviewRouteLabel(
      widget.engine.pickupLocation ?? widget.draft.pickupAddress,
    );
    final dropoff = _reviewRouteLabel(
      widget.engine.destinationLocation ?? widget.draft.dropoffAddress,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 238,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _Tokens.blue.withValues(alpha: .16),
                _Tokens.midnight.withValues(alpha: .92),
                const Color(0xFF0D111C),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .36),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: _ReviewMapGrid()),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _ReviewRoutePainter(
                    t: _controller.value,
                    routeConfirmed: routeConfirmed,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: 22,
                bottom: 30,
                child: _ReviewPinLabel(label: pickup, color: _Tokens.blue),
              ),
              Positioned(
                right: 22,
                bottom: 30,
                child: _ReviewPinLabel(
                  label: dropoff,
                  color: Color(0xFF34D399),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: _BookingCancelPill(onTap: widget.onCancel),
              ),
              Positioned(
                left: 14,
                bottom: 14,
                child: _ReviewEtaChip(
                  routeConfirmed: routeConfirmed,
                  distanceKm: widget.engine.distance,
                  speed: widget.selectedSpeed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewMapGrid extends StatelessWidget {
  const _ReviewMapGrid();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ReviewMapGridPainter());
  }
}

class _ReviewMapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .06)
      ..strokeWidth = 1;
    const spacing = 28.0;
    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final shade = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, _Tokens.bg.withValues(alpha: .28)],
        stops: const [.40, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, shade);
  }

  @override
  bool shouldRepaint(covariant _ReviewMapGridPainter oldDelegate) => false;
}

class _ReviewRoutePainter extends CustomPainter {
  final double t;
  final bool routeConfirmed;

  const _ReviewRoutePainter({required this.t, required this.routeConfirmed});

  @override
  void paint(Canvas canvas, Size size) {
    final route = Path()
      ..moveTo(size.width * .10, size.height * .72)
      ..cubicTo(
        size.width * .30,
        size.height * .72,
        size.width * .30,
        size.height * .30,
        size.width * .50,
        size.height * .30,
      )
      ..cubicTo(
        size.width * .70,
        size.height * .30,
        size.width * .70,
        size.height * .72,
        size.width * .90,
        size.height * .72,
      );
    final glow = Paint()
      ..color = _Tokens.blue.withValues(alpha: .16)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawPath(route, glow);
    final line = Paint()
      ..color = _Tokens.blue.withValues(alpha: routeConfirmed ? .94 : .74)
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (routeConfirmed) {
      canvas.drawPath(route, line);
      final metric = route.computeMetrics().first;
      final progress = (metric.length * t).clamp(0, metric.length).toDouble();
      canvas.drawPath(
        metric.extractPath(0, progress),
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: .75)
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    } else {
      _drawDashedPath(canvas, route, line, phase: t * 14);
    }
    _drawPin(canvas, Offset(size.width * .10, size.height * .72), _Tokens.blue);
    _drawPin(
      canvas,
      Offset(size.width * .90, size.height * .72),
      const Color(0xFF34D399),
    );
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double phase,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = -phase;
      while (distance < metric.length) {
        final start = math.max(0.0, distance);
        final end = math.min(metric.length, distance + 9);
        if (end > 0) canvas.drawPath(metric.extractPath(start, end), paint);
        distance += 17;
      }
    }
  }

  void _drawPin(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(
      center,
      12,
      Paint()..color = color.withValues(alpha: .14),
    );
    canvas.drawCircle(center, 6, Paint()..color = color);
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: .60),
    );
  }

  @override
  bool shouldRepaint(covariant _ReviewRoutePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.routeConfirmed != routeConfirmed;
}

class _ReviewPinLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _ReviewPinLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .58),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ],
    );
  }
}

class _ReviewEtaChip extends StatelessWidget {
  final bool routeConfirmed;
  final double? distanceKm;
  final String speed;

  const _ReviewEtaChip({
    required this.routeConfirmed,
    required this.distanceKm,
    required this.speed,
  });

  @override
  Widget build(BuildContext context) {
    final routeLabel = routeConfirmed
        ? distanceKm == null
            ? 'Route confirmed'
            : '${_formatSenderMilesFromKm(distanceKm!)} · $speed'
        : 'Route calculating · $speed';
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF0D111C).withValues(alpha: .86),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: _Tokens.lightBlue,
                size: 15,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ESTIMATED DELIVERY',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .42),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    routeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatSenderMilesFromKm(double distanceKm) {
  final miles = distanceKm * 0.621371;
  return '${miles.toStringAsFixed(1)} mi';
}

class _ReviewSheet extends StatelessWidget {
  final Widget child;

  const _ReviewSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0D111C).withValues(alpha: .82),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ReviewGrabber extends StatelessWidget {
  const _ReviewGrabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _ReviewListRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? secondary;
  final Widget? badge;

  const _ReviewListRow({
    required this.icon,
    required this.label,
    required this.value,
    this.secondary,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: .08)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReviewRowIcon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReviewRowLabel(label),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (secondary != null && secondary!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    secondary!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .56),
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (badge != null) ...[const SizedBox(height: 7), badge!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandableReviewAddressRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String summary;
  final String fullAddress;

  const _ExpandableReviewAddressRow({
    required this.icon,
    required this.label,
    required this.summary,
    required this.fullAddress,
  });

  @override
  Widget build(BuildContext context) {
    final cleanFullAddress = fullAddress.trim();
    final hasFullAddress = cleanFullAddress.isNotEmpty;
    final showFullAddress = hasFullAddress && cleanFullAddress != summary;
    return Semantics(
      label: '$label address',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: .08)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReviewRowIcon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReviewRowLabel(label),
                  const SizedBox(height: 3),
                  Text(
                    summary,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (showFullAddress) ...[
                    const SizedBox(height: 4),
                    Text(
                      cleanFullAddress,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .62),
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRowIcon extends StatelessWidget {
  final IconData icon;

  const _ReviewRowIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: _Tokens.blue.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _Tokens.blue.withValues(alpha: .18)),
      ),
      child: Icon(icon, color: _Tokens.lightBlue, size: 16),
    );
  }
}

class _ReviewRowLabel extends StatelessWidget {
  final String label;

  const _ReviewRowLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: .40),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        fontFamily: 'JetBrains Mono',
      ),
    );
  }
}

class _VanguardReviewBadge extends StatelessWidget {
  const _VanguardReviewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF34D399).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF34D399).withValues(alpha: .25),
        ),
      ),
      child: const Text(
        'Vanguard protected',
        style: TextStyle(
          color: Color(0xFF34D399),
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }
}

class _ReviewBottomBar extends StatelessWidget {
  final double? total;
  final bool loading;
  final String error;
  final bool canContinue;
  final VoidCallback onContinue;

  const _ReviewBottomBar({
    required this.total,
    required this.loading,
    required this.error,
    required this.canContinue,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 13, 18, 12 + bottom),
          decoration: BoxDecoration(
            color: const Color(0xFF0D111C).withValues(alpha: .88),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: .10)),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 108,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'TOTAL',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .42),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: loading
                          ? const _ReviewTotalSkeleton()
                          : Text(
                              error.isNotEmpty
                                  ? 'Quote needed'
                                  : total == null
                                      ? 'Pending'
                                      : _formatQuoteAmount(total!),
                              key: ValueKey('$total$error$loading'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      const Text(
                        'Unable to retrieve your quote.',
                        style: TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: _PrimaryButton(
                    label: 'Continue to payment',
                    enabled: canContinue,
                    onTap: onContinue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewTotalSkeleton extends StatelessWidget {
  const _ReviewTotalSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('review-total-skeleton'),
      width: 72,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

String _reviewAddressSummary(String address, String? locality) {
  final compact = _compactAddress(address);
  final area = _reviewAddressArea(address, locality);
  if (area.isEmpty || area == compact) return compact;
  return '$compact, $area';
}

String _reviewRouteLabel(String address) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return 'Address pending';
  final parts = trimmed
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length >= 2) return '${parts.first}, ${parts.last}';
  return trimmed;
}

String _reviewAddressArea(String address, String? locality) {
  final cleanLocality = locality?.trim();
  if (cleanLocality != null && cleanLocality.isNotEmpty) return cleanLocality;
  final parts = address
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length >= 2) return parts[parts.length - 2];
  return '';
}

String _maskSenderPhoneForReview(String phone) {
  final trimmed = phone.trim();
  if (trimmed.isEmpty) return 'Phone number pending';
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.length <= 3) return 'Phone masked until Circum Rider assigned';
  final suffix = digits.substring(digits.length - 3);
  final prefix = trimmed.startsWith('+') ? '+${digits.substring(0, 2)} ' : '';
  return '$prefix•••• •••$suffix';
}

String _reviewIrisEstimate(SendPackageState engine, SenderBookingDraft draft) {
  final result = engine.canonicalIrisResult;
  final weight = engine.parcelWeightKg > 0
      ? '${engine.parcelWeightKg.toStringAsFixed(2)} kg'
      : result?.totalWeightLabel ??
          (draft.weightLabel.trim().isEmpty
              ? 'Unavailable'
              : draft.weightLabel.trim());
  final vehicle = draft.selectedVehicle.trim().isNotEmpty
      ? draft.selectedVehicle.trim()
      : _minimumVehicleLabel(result?.recommendedVehicle ?? draft.irisVehicle);
  return 'Final weight $weight • $vehicle selected';
}

class _PaymentPanel extends StatefulWidget {
  final SendPackageState engine;
  final SenderBookingDraft draft;
  final String? draftId;
  final String? senderUid;
  final ValueChanged<SenderBookingDraft> onDraft;

  const _PaymentPanel({
    required this.engine,
    required this.draft,
    required this.draftId,
    required this.senderUid,
    required this.onDraft,
  });

  @override
  State<_PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends State<_PaymentPanel> {
  late Future<SenderPaymentMethodsData> _paymentMethodsFuture;

  SendPackageState get engine => widget.engine;
  SenderBookingDraft get draft => widget.draft;
  String? get draftId => widget.draftId;
  String? get senderUid => widget.senderUid;
  ValueChanged<SenderBookingDraft> get onDraft => widget.onDraft;

  @override
  void initState() {
    super.initState();
    _paymentMethodsFuture = _loadPaymentMethods();
  }

  @override
  void didUpdateWidget(covariant _PaymentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.senderUid != widget.senderUid) {
      _paymentMethodsFuture = _loadPaymentMethods();
    }
  }

  Future<SenderPaymentMethodsData> _loadPaymentMethods() {
    return FirebaseSenderPaymentProfileRepository().paymentMethods().timeout(
      const Duration(seconds: 6),
      onTimeout: () {
        debugPrint(
          'Sender payment methods timed out; falling back to card checkout.',
        );
        return SenderPaymentProfile.empty();
      },
    ).catchError((error) {
      debugPrint(
        'Sender payment methods unavailable; falling back to card checkout: $error',
      );
      return SenderPaymentProfile.empty();
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = engine.senderQuoteTotal;
    final backendRothCredits = engine.senderRothBalance;
    final rothAvailable = backendRothCredits != null;
    final availableRoth = backendRothCredits ?? 0.0;
    final split = total == null
        ? null
        : SenderPaymentSplit.calculate(
            totalDue: total,
            rothEnabled: rothAvailable && draft.rothEnabled,
            availableRothCredits: availableRoth,
            fallbackMethod: draft.selectedPaymentMethod,
          );
    final submitting =
        engine.isSenderPaymentLoading || engine.isSenderDeliveryCreating;
    final canSubmit =
        total != null && split != null && split.canSubmit && !submitting;
    if (engine.senderPaymentStatus == 'succeeded' &&
        engine.senderPaymentClientSecret == null &&
        engine.senderPaymentSessionId != null &&
        engine.senderCreatedRequestId == null &&
        !engine.isSenderDeliveryCreating &&
        engine.senderDeliveryError.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        _createPaidDelivery(context, engine);
      });
    }
    if (engine.senderPaymentClientSecret != null &&
        engine.senderPaymentSessionId != null &&
        engine.senderPaymentStatus != 'succeeded' &&
        draft.paymentStatus == SenderPaymentStatus.processing &&
        !draft.cardConfirmationStarted &&
        !engine.isSenderPaymentLoading &&
        !engine.isSenderDeliveryCreating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        onDraft(draft.copyWith(cardConfirmationStarted: true));
        _confirmCardPayment(context, engine.senderPaymentClientSecret!, engine);
      });
    }
    if (kIsWeb &&
        engine.senderPaymentCheckoutUrl != null &&
        engine.senderPaymentCheckoutUrl!.trim().isNotEmpty &&
        engine.senderPaymentStatus == 'checkout_created' &&
        draft.paymentStatus == SenderPaymentStatus.processing &&
        !draft.cardConfirmationStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        onDraft(draft.copyWith(cardConfirmationStarted: true));
        _openStripeCheckout(context, engine.senderPaymentCheckoutUrl!);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Choose how you'd like to pay for this delivery.",
          style: TextStyle(color: _Tokens.muted, height: 1.35),
        ),
        const SizedBox(height: 14),
        _PaymentCard(
          child: Column(
            children: [
              _SummaryLine(
                label: 'Selected delivery class',
                value: draft.selectedOption,
              ),
              if (engine.senderQuoteError.isNotEmpty)
                const _QuoteErrorText()
              else if (engine.isSenderQuoteLoading || total == null)
                const _QuoteSkeleton()
              else
                _BackendPricingBreakdown(engine: engine),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const _InfoNote(
          text:
              'Estimated using your declared parcel details. Pickup verification may adjust the price if the parcel is heavier, larger, or different from declared.',
        ),
        const SizedBox(height: 14),
        _PaymentCard(
          tinted: true,
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: _Tokens.lightBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rothAvailable
                          ? '${formatSenderRothCredits(availableRoth)} Roth available · ${formatSenderCurrency(availableRoth * senderRothPoundValue)}'
                          : 'Roth currently unavailable',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: rothAvailable && draft.rothEnabled,
                    activeThumbColor: _Tokens.lightBlue,
                    activeTrackColor: _Tokens.blue.withValues(alpha: .40),
                    onChanged: total == null || !rothAvailable
                        ? null
                        : (value) => _setRoth(value, total, availableRoth),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Apply Roth to this payment',
                  style: TextStyle(color: _Tokens.muted, height: 1.35),
                ),
              ),
              if (!rothAvailable) ...[
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Roth balance could not be loaded, so Roth cannot be applied right now.',
                    style: TextStyle(color: _Tokens.muted, height: 1.35),
                  ),
                ),
              ],
              if (engine.isSenderRothLoading) ...[
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Loading Roth balance...',
                    style: TextStyle(color: _Tokens.muted, height: 1.35),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _SummaryLine(
                label: 'Roth applied',
                value: split == null
                    ? 'Pending total'
                    : '${formatSenderCurrency(split.rothAppliedAmount)} (${formatSenderRothCredits(split.rothAppliedCredits)} Roth)',
              ),
              _SummaryLine(
                label: 'Remaining due',
                value: split == null
                    ? 'Pending total'
                    : formatSenderCurrency(split.remainingAmount),
              ),
            ],
          ),
        ),
        if (split == null || split.requiresFallback) ...[
          const SizedBox(height: 14),
          Text(
            rothAvailable && draft.rothEnabled
                ? "Roth doesn't fully cover this delivery. Choose how to pay the remaining amount."
                : 'Roth is switched off. Choose how to pay the full amount.',
            style: const TextStyle(color: _Tokens.muted, height: 1.35),
          ),
          const SizedBox(height: 10),
          FutureBuilder<SenderPaymentMethodsData>(
            future: _paymentMethodsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Column(
                  children: [
                    _checkoutOptionTile(
                      const SenderPaymentProfileOption(
                        SenderPaymentProfileOptionType.addPaymentMethod,
                      ),
                      total,
                      availableRoth,
                    ),
                    const SizedBox(height: 8),
                    const _InfoNote(
                      text:
                          'Loading saved payment methods. Card checkout is available now.',
                    ),
                  ],
                );
              }
              final profile = snapshot.data ?? SenderPaymentProfile.empty();
              final options = senderOrderedPaymentOptions(
                profile,
                platform: Theme.of(context).platform,
              );
              return Column(
                children: options
                    .map(
                      (option) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _checkoutOptionTile(
                          option,
                          total,
                          availableRoth,
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          if (!kIsWeb &&
              draft.selectedPaymentMethod == SenderFallbackPaymentMethod.card &&
              draft.selectedPaymentMethodId.isEmpty) ...[
            const SizedBox(height: 2),
            CardField(
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: .055),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _Tokens.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _Tokens.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _Tokens.lightBlue),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              cursorColor: _Tokens.lightBlue,
            ),
          ],
        ],
        const SizedBox(height: 14),
        _PaymentCard(
          child: Column(
            children: [
              _SummaryLine(
                label: 'Total due today',
                value: total == null
                    ? 'Pending route'
                    : formatSenderCurrency(total),
              ),
              _SummaryLine(
                label: 'Payment split',
                value: split?.splitSummary ?? 'Waiting for route price',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PrimaryButton(
          label: submitting
              ? 'Starting payment...'
              : split?.ctaLabel ?? 'Waiting for price',
          enabled: canSubmit,
          onTap: () => _startPayment(context, total, split),
        ),
        if (kIsWeb &&
            engine.senderPaymentCheckoutUrl != null &&
            engine.senderPaymentCheckoutUrl!.trim().isNotEmpty &&
            engine.senderPaymentStatus == 'checkout_created') ...[
          const SizedBox(height: 12),
          _PrimaryButton(
            label: 'Continue to secure Stripe checkout',
            enabled: true,
            onTap: () =>
                _openStripeCheckout(context, engine.senderPaymentCheckoutUrl!),
          ),
        ],
        if (draft.paymentStatus == SenderPaymentStatus.failed &&
            (engine.senderPaymentCheckoutUrl == null ||
                engine.senderPaymentCheckoutUrl!.trim().isEmpty)) ...[
          const SizedBox(height: 12),
          const _GapNotice(
            title: "Payment couldn't be started",
            body:
                'Please try again. No payment has been confirmed and no Circum Rider broadcast has been created.',
          ),
        ],
        if ((engine.senderPaymentError.isNotEmpty ||
                engine.senderDeliveryError.isNotEmpty) &&
            (engine.senderPaymentCheckoutUrl == null ||
                engine.senderPaymentCheckoutUrl!.trim().isEmpty)) ...[
          const SizedBox(height: 12),
          _GapNotice(
            title: "Payment couldn't be completed",
            body: engine.senderPaymentError.isNotEmpty
                ? engine.senderPaymentError
                : engine.senderDeliveryError,
          ),
        ],
        if (engine.senderPaymentClientSecret != null &&
            draft.paymentStatus == SenderPaymentStatus.processing) ...[
          const SizedBox(height: 12),
          const _GapNotice(
            title: 'Confirming card payment',
            body:
                'Your delivery will only be created after Stripe confirms payment.',
          ),
        ],
      ],
    );
  }

  void _setRoth(bool value, double total, double availableRoth) {
    final split = SenderPaymentSplit.calculate(
      totalDue: total,
      rothEnabled: value,
      availableRothCredits: availableRoth,
      fallbackMethod: draft.selectedPaymentMethod,
    );
    onDraft(
      draft.copyWith(
        rothEnabled: value,
        rothAvailableCredits: availableRoth,
        rothAppliedAmount: split.rothAppliedAmount,
        rothAppliedCredits: split.rothAppliedCredits,
        remainingAmount: split.remainingAmount,
        paymentSplitSummary: split.splitSummary,
        amountDue: total,
        clearSelectedPaymentMethod: split.fullyCoveredByRoth,
      ),
    );
  }

  void _selectMethod(
    double total,
    double availableRoth,
    SenderFallbackPaymentMethod method, {
    String paymentMethodId = '',
    String paymentMethodLabel = '',
  }) {
    final split = SenderPaymentSplit.calculate(
      totalDue: total,
      rothEnabled: draft.rothEnabled,
      availableRothCredits: availableRoth,
      fallbackMethod: method,
    );
    onDraft(
      draft.copyWith(
        selectedPaymentMethod: method,
        selectedPaymentMethodId: paymentMethodId,
        selectedPaymentMethodLabel: paymentMethodLabel,
        paymentStatus: SenderPaymentStatus.ready,
        rothAvailableCredits: availableRoth,
        rothAppliedAmount: split.rothAppliedAmount,
        rothAppliedCredits: split.rothAppliedCredits,
        remainingAmount: split.remainingAmount,
        paymentSplitSummary: split.splitSummary,
        amountDue: total,
        cardConfirmationStarted: false,
      ),
    );
  }

  Widget _checkoutOptionTile(
    SenderPaymentProfileOption option,
    double? total,
    double availableRoth,
  ) {
    switch (option.type) {
      case SenderPaymentProfileOptionType.applePay:
        return _PaymentMethodTile(
          title: 'Apple Pay${option.isDefault ? ' · Default' : ''}',
          subtitle: 'Fast checkout on supported iOS devices.',
          icon: Icons.apple_rounded,
          selected: draft.selectedPaymentMethod ==
              SenderFallbackPaymentMethod.applePay,
          onTap: total == null
              ? null
              : () => _selectMethod(
                    total,
                    availableRoth,
                    SenderFallbackPaymentMethod.applePay,
                  ),
        );
      case SenderPaymentProfileOptionType.googlePay:
        return _PaymentMethodTile(
          title: 'Google Pay${option.isDefault ? ' · Default' : ''}',
          subtitle: 'Fast checkout on supported Android devices.',
          icon: Icons.android_rounded,
          selected: draft.selectedPaymentMethod ==
              SenderFallbackPaymentMethod.googlePay,
          onTap: total == null
              ? null
              : () => _selectMethod(
                    total,
                    availableRoth,
                    SenderFallbackPaymentMethod.googlePay,
                  ),
        );
      case SenderPaymentProfileOptionType.savedCard:
        final method = option.method;
        if (method == null) return const SizedBox.shrink();
        return _PaymentMethodTile(
          title: method.isDefault ? '${method.title} · Default' : method.title,
          subtitle: method.expiry,
          icon: Icons.credit_card_rounded,
          selected: draft.selectedPaymentMethodId == method.id,
          onTap: total == null
              ? null
              : () => _selectMethod(
                    total,
                    availableRoth,
                    SenderFallbackPaymentMethod.card,
                    paymentMethodId: method.id,
                    paymentMethodLabel: method.title,
                  ),
        );
      case SenderPaymentProfileOptionType.addPaymentMethod:
        return _PaymentMethodTile(
          title: 'Pay by card',
          subtitle: kIsWeb
              ? 'Secure Stripe checkout opens next.'
              : 'Secure Stripe card payment.',
          icon: Icons.add_card_outlined,
          selected:
              draft.selectedPaymentMethod == SenderFallbackPaymentMethod.card &&
                  draft.selectedPaymentMethodId.isEmpty,
          onTap: total == null
              ? null
              : () => _selectMethod(
                    total,
                    availableRoth,
                    SenderFallbackPaymentMethod.card,
                  ),
        );
    }
  }

  Future<void> _startPayment(
    BuildContext context,
    double? total,
    SenderPaymentSplit? split,
  ) async {
    if (total == null || split == null || !split.canSubmit) return;
    final method = split.fullyCoveredByRoth
        ? 'Roth'
        : draft.selectedPaymentMethodLabel.isNotEmpty
            ? draft.selectedPaymentMethodLabel
            : senderPaymentMethodLabel(split.fallbackMethod!);
    final confirmed = await confirmSenderPaymentIfRequired(
      context,
      paymentMethod: method,
      amount: '£${total.toStringAsFixed(2)}',
    );
    if (!confirmed || !context.mounted) return;
    onDraft(
      draft.copyWith(
        paymentStatus: SenderPaymentStatus.processing,
        rothAppliedAmount: split.rothAppliedAmount,
        rothAppliedCredits: split.rothAppliedCredits,
        remainingAmount: split.remainingAmount,
        paymentSplitSummary: split.splitSummary,
        amountDue: total,
        cardConfirmationStarted: false,
      ),
    );
    context.read<SendPackageBloc>().add(
          StartSenderPaymentSession(
            rothEnabled: split.rothEnabled,
            fallbackMethod: split.fallbackMethod == null
                ? 'roth'
                : draft.selectedPaymentMethodLabel.isNotEmpty
                    ? 'saved_card'
                    : _stripeFallbackMethodValue(split.fallbackMethod!),
            paymentMethodId: draft.selectedPaymentMethodId,
            checkoutMode: kIsWeb ? 'web_checkout' : '',
            returnUrl: kIsWeb ? _senderAppCheckoutReturnUrl() : '',
            draftId: draftId ?? '',
            idempotencyKey:
                'sender-${senderUid ?? 'anonymous'}-${draftId ?? 'draft'}-${engine.senderQuoteId ?? 'quote'}',
            deliveryPayload: kIsWeb ? _bookingPayload(engine) : const {},
          ),
        );
  }

  Future<void> _openStripeCheckout(BuildContext context, String url) async {
    final checkoutUrl = Uri.tryParse(url);
    if (checkoutUrl == null || checkoutUrl.host.isEmpty) {
      onDraft(draft.copyWith(paymentStatus: SenderPaymentStatus.failed));
      return;
    }
    final opened = await launchUrl(checkoutUrl, webOnlyWindowName: '_self');
    if (!opened && context.mounted) {
      onDraft(draft.copyWith(paymentStatus: SenderPaymentStatus.failed));
    }
  }

  String _stripeFallbackMethodValue(SenderFallbackPaymentMethod method) {
    switch (method) {
      case SenderFallbackPaymentMethod.card:
        return 'card';
      case SenderFallbackPaymentMethod.applePay:
        return 'apple_pay';
      case SenderFallbackPaymentMethod.googlePay:
        return 'google_pay';
    }
  }

  String _senderAppCheckoutReturnUrl() {
    final base = Uri.base.removeFragment();
    return base.replace(
      path: '/send',
      queryParameters: {
        ...base.queryParameters,
        'app': 'sender',
        'tab': '1',
      },
    ).toString();
  }

  Future<void> _confirmCardPayment(
    BuildContext context,
    String clientSecret,
    SendPackageState engine,
  ) async {
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Circum',
          customerId: engine.senderPaymentCustomerId,
          customerEphemeralKeySecret: engine.senderPaymentEphemeralKeySecret,
          applePay: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
              ? const PaymentSheetApplePay(merchantCountryCode: 'GB')
              : null,
          googlePay: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
              ? const PaymentSheetGooglePay(
                  merchantCountryCode: 'GB',
                  currencyCode: 'GBP',
                )
              : null,
          style: ThemeMode.dark,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      if (!context.mounted) return;
      onDraft(draft.copyWith(paymentStatus: SenderPaymentStatus.paid));
      _createPaidDelivery(context, engine);
      SenderAccessibilityScope.maybeOf(
        context,
      )?.haptic(SenderFeedbackEvent.paymentCompleted);
    } on StripeException catch (error) {
      debugPrint('Sender mobile Stripe confirmation failed: $error');
      if (!context.mounted) return;
      onDraft(draft.copyWith(paymentStatus: SenderPaymentStatus.failed));
    } catch (error) {
      debugPrint('Sender mobile Stripe confirmation failed: $error');
      if (!context.mounted) return;
      onDraft(draft.copyWith(paymentStatus: SenderPaymentStatus.failed));
    }
  }

  void _createPaidDelivery(BuildContext context, SendPackageState engine) {
    context.read<SendPackageBloc>().add(
          CreatePaidSenderDelivery(bookingPayload: _bookingPayload(engine)),
        );
  }

  Map<String, dynamic> _bookingPayload(SendPackageState engine) => {
        'draftId': draftId,
        'idempotencyKey':
            'sender-${senderUid ?? 'anonymous'}-${draftId ?? 'draft'}-${engine.senderPaymentSessionId ?? 'session'}',
        'pickup': {
          'address': engine.pickupLocation ?? draft.pickupAddress,
          'subAddress': engine.pickupLocationSubAddress ?? '',
          'locality': engine.pickupLocality ?? '',
          'coordinates': {
            'lat': engine.pickupCoordinate?.lat ?? 0,
            'lng': engine.pickupCoordinate?.lng ?? 0,
          },
        },
        'dropoff': {
          'address': engine.destinationLocation ?? draft.dropoffAddress,
          'subAddress': engine.destinationLocationSubAddress ?? '',
          'locality': engine.destinationLocality ?? '',
          'coordinates': {
            'lat': engine.desinationCoordinate?.lat ?? 0,
            'lng': engine.desinationCoordinate?.lng ?? 0,
          },
        },
        'recipient': {
          'name': draft.receiverName,
          'phone': draft.receiverPhone,
          'deliveryNotes': draft.deliveryNotes,
        },
        'deliveryTime': {
          'type': draft.deliveryTimingType == SenderDeliveryTimingType.now
              ? 'now'
              : 'scheduled',
          'scheduledDate': draft.scheduledDate,
          'scheduledJourneyAt': draft.scheduledJourneyAt,
          'scheduledWindow': draft.scheduledWindow,
          'customWindowStart': draft.customWindowStart,
          'customWindowEnd': draft.customWindowEnd,
          'summary': draft.deliveryTimeSummary,
        },
        'parcel': {
          'itemName': draft.itemName,
          'description': draft.itemDescription,
          'weightLabel': draft.weightLabel,
          'weightKg': engine.parcelWeightKg,
          'fragile': draft.fragile,
          'highValue': draft.highValue,
        },
        'iris': {
          'itemName': engine.canonicalIrisResult?.itemName,
          'quantity': engine.canonicalIrisResult?.quantity,
          'totalWeightKg': engine.canonicalIrisResult?.totalWeightKg,
          'recommendedVehicle': engine.canonicalIrisResult?.recommendedVehicle,
          'confidence': engine.canonicalIrisResult?.confidenceLabel,
          'category': engine.canonicalIrisResult?.category,
          'vanguardRequired': engine.canonicalIrisResult?.vanguardRequired,
          'vanguardRequiredReason':
              engine.canonicalIrisResult?.vanguardRequiredReason,
        },
      };
}

class _RadioGlassTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String caption;
  final VoidCallback onTap;

  const _RadioGlassTile({
    required this.selected,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? _Tokens.blue.withValues(alpha: .14)
              : Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _Tokens.lightBlue : _Tokens.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 19,
              height: 19,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _Tokens.lightBlue : _Tokens.muted,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: _Tokens.lightBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    style: const TextStyle(color: _Tokens.muted, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  final String text;

  const _InfoNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Tokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: _Tokens.muted,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: _Tokens.muted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final Widget child;
  final bool tinted;

  const _PaymentCard({required this.child, this.tinted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tinted
            ? _Tokens.blue.withValues(alpha: .12)
            : Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: tinted
              ? _Tokens.lightBlue.withValues(alpha: .40)
              : _Tokens.border,
        ),
      ),
      child: child,
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _PaymentMethodTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected
              ? _Tokens.blue.withValues(alpha: .14)
              : Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _Tokens.lightBlue : _Tokens.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: _Tokens.lightBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: _Tokens.muted)),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? _Tokens.lightBlue : _Tokens.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final String? helperText;
  final String? errorText;
  final ValueChanged<String> onChanged;

  const _TextInput({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.helperText,
    this.errorText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _Tokens.muted),
        helperText: helperText,
        helperStyle: const TextStyle(color: _Tokens.muted, height: 1.25),
        errorText: errorText,
        errorStyle: const TextStyle(color: Color(0xFFFCA5A5), height: 1.25),
        filled: true,
        fillColor: const Color(0xAA1A2030),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      minLeadingWidth: 0,
      leading: const Icon(Icons.location_on_outlined, color: _Tokens.lightBlue),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(color: _Tokens.muted)),
      onTap: onTap,
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? _Tokens.blue.withValues(alpha: .22)
              : Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _Tokens.lightBlue : _Tokens.border,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _Tokens.lightBlue.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Tokens.lightBlue.withValues(alpha: .28)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: _Tokens.blue.withValues(alpha: .30),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ]
              : const [],
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_Tokens.lightBlue, _Tokens.blue, _Tokens.vanguard],
                )
              : null,
        ),
        child: ElevatedButton(
          onPressed: enabled ? onTap : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: enabled
                ? Colors.transparent
                : Colors.white.withValues(alpha: .10),
            disabledBackgroundColor: Colors.white.withValues(alpha: .10),
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: _Tokens.lightBlue,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _VehicleUpgradeSelector extends StatelessWidget {
  final List<String> values;
  final String selected;
  final String recommended;
  final ValueChanged<String> onSelected;

  const _VehicleUpgradeSelector({
    required this.values,
    required this.selected,
    required this.recommended,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: values.map((value) {
        final active = selected == value;
        final isRecommended = value == recommended;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onSelected(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: active
                    ? _Tokens.blue.withValues(alpha: .20)
                    : Colors.white.withValues(alpha: .055),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? _Tokens.lightBlue : _Tokens.border,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: _Tokens.blue.withValues(alpha: .22),
                          blurRadius: 22,
                          offset: const Offset(0, 12),
                        ),
                      ]
                    : const [],
              ),
              child: Row(
                children: [
                  Icon(
                    active
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: active ? _Tokens.lightBlue : _Tokens.muted,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isRecommended)
                          const Text(
                            'IRIS Recommendation',
                            style: TextStyle(
                              color: _Tokens.lightBlue,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        Text(
                          value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          isRecommended
                              ? 'Fastest suitable vehicle for this parcel.'
                              : 'Upgrade if preferred.',
                          style: const TextStyle(
                            color: _Tokens.muted,
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isRecommended)
                    const Text(
                      'Upgrade',
                      style: TextStyle(
                        color: _Tokens.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AddOnTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String price;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _AddOnTile({
    required this.selected,
    required this.title,
    required this.price,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? _Tokens.vanguard.withValues(alpha: .20)
              : Colors.white.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? _Tokens.lightBlue : _Tokens.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _Tokens.vanguard.withValues(alpha: .26),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ]
              : const [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? _Tokens.lightBlue : Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        price,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _Tokens.muted, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? _Tokens.lightBlue : _Tokens.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool confirmed;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.confirmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          if (confirmed) ...[
            const Icon(
              Icons.check_circle_rounded,
              color: _Tokens.lightBlue,
              size: 16,
            ),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(label, style: const TextStyle(color: _Tokens.muted)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _compactAddress(String address) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return 'Address pending';
  final postcode = RegExp(
    r'\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b',
    caseSensitive: false,
  ).firstMatch(trimmed)?.group(0);
  if (postcode != null && postcode.trim().isNotEmpty) {
    return postcode.toUpperCase();
  }
  final parts = trimmed
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return trimmed;
  return parts.length == 1 ? parts.single : parts.last;
}

class _BackendPricingBreakdown extends StatelessWidget {
  final SendPackageState engine;

  const _BackendPricingBreakdown({required this.engine});

  @override
  Widget build(BuildContext context) {
    final lines = engine.senderQuoteLineItems
        .map(
          (item) => (
            label: _quoteLineLabel(item, engine),
            amount: _quoteLineAmountFromItem(item),
          ),
        )
        .where((item) => item.amount != null)
        .toList(growable: false);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      child: Column(
        key: ValueKey(
          '${engine.senderQuoteId}-${engine.senderQuoteTotal}-${engine.senderQuoteSpeed}',
        ),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Delivery Summary',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...lines.map(
            (item) => _SummaryLine(
              label: item.label,
              value: item.amount!,
              confirmed: item.label.toLowerCase().startsWith('final weight'),
            ),
          ),
          if (engine.senderQuoteTotal != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              height: 1,
              color: Colors.white.withValues(alpha: .12),
            ),
            _EstimatedTotalLine(total: engine.senderQuoteTotal!),
          ],
        ],
      ),
    );
  }
}

class _EstimatedTotalLine extends StatelessWidget {
  final double total;

  const _EstimatedTotalLine({required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Text(
            'Estimated Total Today',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: total, end: total),
          duration: const Duration(milliseconds: 260),
          builder: (context, value, _) {
            return Text(
              _formatQuoteAmount(value),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _QuoteSkeleton extends StatelessWidget {
  const _QuoteSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          margin: const EdgeInsets.symmetric(vertical: 7),
          height: 16,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .07 + index * .015),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _QuoteUnavailable extends StatelessWidget {
  final VoidCallback onRetry;

  const _QuoteUnavailable({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _QuoteErrorText(),
        const SizedBox(height: 10),
        _PrimaryButton(label: 'Retry', enabled: true, onTap: onRetry),
      ],
    );
  }
}

class _RouteQuotePending extends StatelessWidget {
  const _RouteQuotePending();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Calculating route price...',
      textAlign: TextAlign.center,
      style: TextStyle(color: _Tokens.muted, fontWeight: FontWeight.w800),
    );
  }
}

class _QuoteErrorText extends StatelessWidget {
  const _QuoteErrorText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Unable to retrieve your quote.',
      style: TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w800),
    );
  }
}

String _quoteLineLabel(Map<String, dynamic> item, SendPackageState engine) {
  final label = '${item['label'] ?? ''}'.trim();
  final key = '${item['key'] ?? item['type']}'.trim();
  final resolved = label.isNotEmpty
      ? label
      : switch (key) {
          'base_delivery' || 'base' => 'Base delivery',
          'distance_adjustment' || 'distance' => 'Distance adjustment',
          'weight_adjustment' || 'weight' => 'Weight adjustment',
          'speed_adjustment' || 'speed' => 'Speed adjustment',
          'economy_discount' => 'Service adjustment',
          'promotional_credit' || 'promotion' => 'Promotional credit',
          'vanguard' || 'vanguard_protection' => 'Vanguard protection',
          _ => 'Quote line',
        };
  if (_isWeightQuoteLine(key, resolved)) {
    final weight = engine.parcelWeightKg;
    if (weight > 0) {
      return 'Final weight (${weight.toStringAsFixed(2)} kg)';
    }
  }
  return resolved;
}

String? _quoteLineAmountFromItem(Map<String, dynamic> item) {
  final value = item['amount'] ?? item['total'] ?? item['value'];
  if (value == null) return null;
  final key = '${item['key'] ?? item['type']}'.trim();
  final label = '${item['label'] ?? ''}'.trim();
  if (value is num) {
    if (_isWeightQuoteLine(key, label) && value.toDouble() == 0) {
      return 'Included';
    }
    return _formatQuoteAmount(value.toDouble());
  }
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  final parsed = double.tryParse(text);
  if (parsed == null) return text;
  if (_isWeightQuoteLine(key, label) && parsed == 0) return 'Included';
  return _formatQuoteAmount(parsed);
}

bool _isWeightQuoteLine(String key, String label) {
  final normalizedKey = key.toLowerCase();
  final normalizedLabel = label.toLowerCase();
  return normalizedKey == 'weight' ||
      normalizedKey == 'weight_adjustment' ||
      normalizedLabel.contains('parcel weight') ||
      normalizedLabel.contains('weight adjustment');
}

String _formatQuoteAmount(double value) {
  if (value < 0) return '-£${value.abs().toStringAsFixed(2)}';
  return formatSenderCurrency(value);
}

class _ReasonLine extends StatelessWidget {
  final String text;

  const _ReasonLine(this.text);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.check_rounded, color: _Tokens.lightBlue),
      title: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}

class _GapNotice extends StatelessWidget {
  final String title;
  final String body;

  const _GapNotice({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE0A93A).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE0A93A).withValues(alpha: .35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE0A93A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(color: _Tokens.muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  final Widget child;

  const _Glass({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * .54,
          ),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _Tokens.midnight.withValues(alpha: .84),
                _Tokens.bg.withValues(alpha: .72),
                _Tokens.blue.withValues(alpha: .10),
              ],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: .18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .40),
                blurRadius: 36,
                offset: const Offset(0, 22),
              ),
              BoxShadow(
                color: _Tokens.blue.withValues(alpha: .14),
                blurRadius: 34,
              ),
            ],
          ),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _Tokens.glass,
          shape: BoxShape.circle,
          border: Border.all(color: _Tokens.border),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _BookingCancelPill extends StatelessWidget {
  final VoidCallback onTap;

  const _BookingCancelPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cancel booking',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _Tokens.glass,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFFB7185).withValues(alpha: .38),
            ),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: Color(0xFFFF8FA3),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
        ),
      ),
    );
  }
}

class _CancelBookingSheet extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onCancel;

  const _CancelBookingSheet({required this.onContinue, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1324).withValues(alpha: .94),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: .12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .38),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cancel booking?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This will discard your current booking and remove all unsaved information. Your account, wallet and previous deliveries will not be affected.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _PrimaryButton(
                    label: 'Continue Booking',
                    enabled: true,
                    onTap: onContinue,
                  ),
                  const SizedBox(height: 10),
                  _DestructiveSheetButton(
                    label: 'Cancel Booking',
                    onTap: onCancel,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DestructiveSheetButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DestructiveSheetButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: const Color(0xFFFB7185).withValues(alpha: .10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFFB7185).withValues(alpha: .36),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFFF8FA3),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _IrisOrb extends StatelessWidget {
  final bool active;

  const _IrisOrb({this.active = false});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: active ? .94 : 1, end: active ? 1.08 : 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [_Tokens.iris, _Tokens.vanguard, _Tokens.bg],
          ),
          boxShadow: [
            BoxShadow(
              color: _Tokens.iris.withValues(alpha: active ? .34 : .24),
              blurRadius: active ? 34 : 28,
            ),
          ],
        ),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
      ),
    );
  }
}

class _SenderMobileMap extends StatefulWidget {
  final bool active;
  final SendPackageState? engine;
  final bool showDestination;
  final bool showVanguardShield;
  final double? distanceKm;

  const _SenderMobileMap({
    required this.active,
    this.engine,
    this.showDestination = false,
    this.showVanguardShield = false,
    this.distanceKm,
  });

  @override
  State<_SenderMobileMap> createState() => _SenderMobileMapState();
}

class _SenderMobileMapState extends State<_SenderMobileMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  GoogleMapController? _mapController;
  LatLngBounds? _lastBounds;
  LatLng? _lastPickup;
  LatLng? _lastDropoff;
  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _dropoffIcon;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat();
    _loadCircumMarkerIcons();
  }

  @override
  void dispose() {
    _controller.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SenderMobileMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldEngine = oldWidget.engine;
    final nextEngine = widget.engine;
    if (oldEngine != null &&
        nextEngine != null &&
        _coordinatesChanged(oldEngine, nextEngine)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveCamera());
    }
  }

  @override
  Widget build(BuildContext context) {
    final highContrast =
        SenderAccessibilityScope.maybeOf(context)?.settings.highContrast ??
            false;
    final engine = widget.engine;
    final pickup = _latLng(engine?.pickupCoordinate);
    final dropoff = _latLng(engine?.desinationCoordinate);
    final showGoogleMap = senderBookingMapShouldUseGoogle(pickup);
    final pickupForMap = pickup;
    assertPlatformViewAttachVisibility(
      viewName: 'SenderBookingGoogleMap',
      opacity: 1,
      attached: _mapController != null,
    );
    return Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: showGoogleMap
              ? GoogleMap(
                  key: const ValueKey('sender-google-map'),
                  initialCameraPosition: CameraPosition(
                    target: pickupForMap!,
                    zoom: dropoff == null ? 15.4 : 12.5,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _moveCamera(),
                    );
                  },
                  markers: _markers(pickupForMap, dropoff),
                  polylines: _polylines(),
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  trafficEnabled: false,
                  style: _senderMapStyle,
                )
              : AnimatedBuilder(
                  key: const ValueKey('sender-painted-map'),
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _MapPainter(
                      t: _controller.value,
                      active: widget.active,
                      showDestination: widget.showDestination,
                      highContrast: highContrast,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x9907090F), Color(0x3307090F), Color(0xCC07090F)],
              stops: [0, .48, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-.65, -.95),
              radius: 1.15,
              colors: [
                _Tokens.blue.withValues(alpha: .14),
                Colors.transparent,
                _Tokens.bg.withValues(alpha: .42),
              ],
              stops: const [0, .54, 1],
            ),
          ),
        ),
        if (widget.showDestination && widget.showVanguardShield)
          const Align(
            alignment: Alignment(-.02, -.12),
            child: _BookingMapVanguardShield(),
          ),
      ],
    );
  }

  bool _coordinatesChanged(SendPackageState oldEngine, SendPackageState next) {
    return oldEngine.pickupCoordinate?.lat != next.pickupCoordinate?.lat ||
        oldEngine.pickupCoordinate?.lng != next.pickupCoordinate?.lng ||
        oldEngine.desinationCoordinate?.lat != next.desinationCoordinate?.lat ||
        oldEngine.desinationCoordinate?.lng != next.desinationCoordinate?.lng ||
        oldEngine.polylines.length != next.polylines.length ||
        oldEngine.markers.length != next.markers.length;
  }

  LatLng? _latLng(PlaceCoordinate? coordinate) {
    if (coordinate == null) return null;
    return LatLng(coordinate.lat, coordinate.lng);
  }

  Set<Marker> _markers(LatLng pickup, LatLng? dropoff) {
    final engine = widget.engine;
    if (engine != null && engine.markers.isNotEmpty) {
      return engine.markers.values.toSet();
    }
    final pickupIcon = _pickupIcon;
    final dropoffIcon = _dropoffIcon;
    if (pickupIcon == null || (dropoff != null && dropoffIcon == null)) {
      return const {};
    }
    return {
      Marker(
        markerId: const MarkerId('source_marker'),
        position: pickup,
        icon: pickupIcon,
      ),
      if (dropoff != null)
        Marker(
          markerId: const MarkerId('destination_marker'),
          position: dropoff,
          icon: dropoffIcon!,
        ),
    };
  }

  Future<void> _loadCircumMarkerIcons() async {
    final pickupIcon =
        await BitmapDescriptorHelper.getBitmapDescriptorFromSvgAsset(
      'assets/svg/source_marker.svg',
      const Size(27, 43),
    );
    final dropoffIcon =
        await BitmapDescriptorHelper.getBitmapDescriptorFromSvgAsset(
      'assets/svg/destination_marker.svg',
      const Size(27, 43),
    );
    if (!mounted) return;
    setState(() {
      _pickupIcon = pickupIcon;
      _dropoffIcon = dropoffIcon;
    });
  }

  Set<Polyline> _polylines() {
    final engine = widget.engine;
    if (engine == null || engine.polylines.isEmpty) return const {};
    return engine.polylines
        .map(
          (polyline) =>
              polyline.copyWith(colorParam: _Tokens.lightBlue, widthParam: 4),
        )
        .toSet();
  }

  Future<void> _moveCamera() async {
    final controller = _mapController;
    final engine = widget.engine;
    final pickup = _latLng(engine?.pickupCoordinate);
    if (controller == null || pickup == null) return;
    final dropoff = _latLng(engine?.desinationCoordinate);
    if (dropoff == null) {
      if (_lastPickup == pickup && _lastDropoff == null) return;
      _lastPickup = pickup;
      _lastDropoff = null;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: pickup, zoom: 15.4),
        ),
      );
      return;
    }
    final bounds = _boundsFor(pickup, dropoff);
    if (_lastBounds == bounds) return;
    _lastPickup = pickup;
    _lastDropoff = dropoff;
    _lastBounds = bounds;
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
  }

  LatLngBounds _boundsFor(LatLng a, LatLng b) {
    return LatLngBounds(
      southwest: LatLng(
        math.min(a.latitude, b.latitude),
        math.min(a.longitude, b.longitude),
      ),
      northeast: LatLng(
        math.max(a.latitude, b.latitude),
        math.max(a.longitude, b.longitude),
      ),
    );
  }
}

@visibleForTesting
bool senderBookingMapShouldUseGoogle(LatLng? pickup) => pickup != null;

const _senderMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0b1020"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#7f8da3"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#07090f"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1b2638"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#111827"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca3af"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#243655"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1d4ed8"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#05070d"}]}
]
''';

class _BookingMapVanguardShield extends StatelessWidget {
  const _BookingMapVanguardShield();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _Tokens.glass,
        border: Border.all(color: _Tokens.lightBlue.withValues(alpha: .34)),
        boxShadow: [
          BoxShadow(
            color: _Tokens.vanguard.withValues(alpha: .16),
            blurRadius: 18,
          ),
        ],
      ),
      child: const Icon(
        Icons.shield_outlined,
        color: _Tokens.lightBlue,
        size: 18,
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final double t;
  final bool active;
  final bool showDestination;
  final bool highContrast;

  const _MapPainter({
    required this.t,
    required this.active,
    required this.showDestination,
    this.highContrast = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_Tokens.bg, _Tokens.midnight],
        ).createShader(rect),
    );
    final drift = math.sin(t * math.pi * 2) * 8;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: highContrast ? .12 : .025)
      ..strokeWidth = highContrast ? 1.35 : 1;
    for (var x = -70.0 + drift; x < size.width + 70; x += 50) {
      canvas.drawLine(Offset(x, 0), Offset(x + 28, size.height), grid);
    }
    for (var y = -70.0 - drift; y < size.height + 70; y += 58) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 18), grid);
    }
    final pickup = Offset(size.width * .25, size.height * .30);
    final dropoff = Offset(size.width * .73, size.height * .21);
    final route = Path()
      ..moveTo(pickup.dx, pickup.dy)
      ..cubicTo(
        size.width * .23,
        size.height * .12,
        size.width * .70,
        size.height * .40,
        dropoff.dx,
        dropoff.dy,
      );
    if (showDestination) {
      canvas.drawPath(
        route,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = highContrast ? 5 : 3
          ..strokeCap = StrokeCap.round
          ..color = _Tokens.lightBlue.withValues(
            alpha: highContrast ? .96 : (active ? .68 : .24),
          ),
      );
      final metrics = route.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final metric = metrics.first;
        final start = (metric.length * t) % metric.length;
        final end = math.min(metric.length, start + metric.length * .24);
        canvas.drawPath(
          metric.extractPath(start, end),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = highContrast ? 7 : 5
            ..strokeCap = StrokeCap.round
            ..shader = LinearGradient(
              colors: [
                _Tokens.iris.withValues(alpha: 0),
                _Tokens.iris.withValues(alpha: .72),
                _Tokens.lightBlue.withValues(alpha: 0),
              ],
            ).createShader(rect),
        );
      }
    }
    _pin(canvas, pickup, _Tokens.blue, t);
    if (showDestination) {
      _pin(canvas, dropoff, const Color(0xFF22C55E), (t + .45) % 1);
    }
  }

  void _pin(Canvas canvas, Offset point, Color color, double phase) {
    canvas.drawCircle(
      point,
      (highContrast ? 11 : 8) + phase * (highContrast ? 24 : 20),
      Paint()
        ..color = color.withValues(
          alpha: (highContrast ? .26 : .15) * (1 - phase),
        ),
    );
    canvas.drawCircle(point, highContrast ? 8 : 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.active != active ||
      oldDelegate.showDestination != showDestination ||
      oldDelegate.highContrast != highContrast;
}

class _Tokens {
  static const bg = Color(0xFF07090F);
  static const midnight = Color(0xFF0B1020);
  static const blue = Color(0xFF3B82F6);
  static const lightBlue = Color(0xFF60A5FA);
  static const vanguard = Color(0xFF2563EB);
  static const iris = Color(0xFF38BDF8);
  static const muted = Color(0xFF9CA3AF);
  static const border = Color(0x29FFFFFF);
  static const glass = Color(0x12FFFFFF);
}
