import 'dart:async';

import 'package:circum/app/iris/iris_learning_bridge.dart';
import 'package:circum/app/iris/iris_weight_estimator.dart';
import 'package:circum/app/send_package/models/place_coordinates.m.dart';
import 'package:circum/pricing/delivery_pricing.dart';
import 'package:circum/utils/theme/colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';

import '../../../helper/bitmap_descriptor_helper.dart';
import '../../../helper/calculate_bearing.dart';
import '../../../helper/chats_help.dart';
import '../models/canonical_iris_result.dart';
import '../models/contact_info.dart';
import '../models/delivery_data.m.dart';
import '../models/message.m.dart';
import '../models/suggestions.m.dart';
import '../repo/place_api.dart';

part 'send_package_event.dart';
part 'send_package_state.dart';

class SendPackageBloc extends Bloc<SendPackageEvent, SendPackageState> {
  FirebaseAuth auth = FirebaseAuth.instance;
  FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _activeDeliverySubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _activeDeliveryLiveLocationSubscription;
  String? _activeDeliveryLiveLocationId;
  SendPackageBloc() : super(SendPackageState()) {
    on<CheckForPushToken>(_handleCheckForPushToken);
    on<SearchAPlaceEvent>(_handleSearchAPlaceEvent);
    on<SetDrawerHeight>(_handleSetDrawerHeight);
    on<ClearSuggestions>(_handleClearSuggestionsEvent);
    on<SetPickupAddress>(_handleSetPickupAddressEvent);
    on<SetDeliveryAddress>(_handleSetDeliveryAddress);
    on<SetDeliveryStatus>(_handleSetDeliveryStatusEvent);
    on<CalculateDistance>(_handleCalculateDistance);
    on<SetDistance>(_handleSetDistance);
    on<SetPrice>(_handleSetPrice);
    on<SetParcelWeight>(_handleSetParcelWeight);
    on<RequestCanonicalIrisEstimate>(_handleRequestCanonicalIrisEstimate);
    on<RequestSenderBookingQuote>(_handleRequestSenderBookingQuote);
    on<LoadSenderRothBalance>(_handleLoadSenderRothBalance);
    on<StartSenderPaymentSession>(_handleStartSenderPaymentSession);
    on<CreatePaidSenderDelivery>(_handleCreatePaidSenderDelivery);
    on<SendDeliveryRequest>(_handleSendDeliveryRequestEvent);
    on<DeliveryAccepted>(_handleDeliveryAcceptedEvent);
    on<DeliveryCompleted>(_handleDeliveryCompleted);
    on<SetSourceAndDestinationStatus>(_handleSetSourceAndDestinationStatus);
    on<SetMapCameraStatus>(_handleSetMapCameraStatusEvent);
    on<SetRiderLocation>(_handleSetRiderLocationEvent);
    on<CheckForActiveRequest>(_handleCheckForActiveRequestEvent);
    on<WatchActiveDelivery>(_handleWatchActiveDeliveryEvent);
    on<ActiveDeliverySnapshotChanged>(_handleActiveDeliverySnapshotChanged);
    on<ActiveDeliveryLiveLocationChanged>(
      _handleActiveDeliveryLiveLocationChanged,
    );
    on<SetPanelControlStatus>(_handleSetPanelControlStatusEvent);
    on<SetNewMessage>(_handleSetNewMessage);
    on<IncomingMessage>(_handleIncomingMessage);
    on<MessageRider>(_handleMessageRiderEvent);
    on<LoadChatMessages>(_handleLoadChatMessagesEvent);
    on<DeleteCompletedDelivery>(_handleDeleteCompletedDelivery);
    on<CancelRequest>(_handleCancelRequestEvent);
    on<BackButtonPressed>(_handleBackButtonPressedEvent);
  }

  @override
  Future<void> close() {
    _activeDeliverySubscription?.cancel();
    _activeDeliveryLiveLocationSubscription?.cancel();
    return super.close();
  }

  void _listenToActiveDelivery(String requestId) {
    final normalized = requestId.trim();
    if (normalized.isEmpty) return;
    _activeDeliverySubscription?.cancel();
    _activeDeliverySubscription = db
        .collection('deliveryRequests')
        .where('requestId', isEqualTo: normalized)
        .limit(1)
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.docs.isEmpty) {
          add(const ActiveDeliverySnapshotChanged());
          return;
        }
        final doc = snapshot.docs.first;
        _listenToActiveDeliveryLiveLocation(doc.id);
        add(
          ActiveDeliverySnapshotChanged(
            data: {...doc.data(), 'id': doc.id},
          ),
        );
      },
      onError: (Object error) {
        add(
          ActiveDeliverySnapshotChanged(
            errorMessage: 'Unable to load live delivery status.',
          ),
        );
      },
    );
  }

  void _listenToActiveDeliveryLiveLocation(String deliveryId) {
    final normalized = deliveryId.trim();
    if (normalized.isEmpty || normalized == _activeDeliveryLiveLocationId) {
      return;
    }
    _activeDeliveryLiveLocationId = normalized;
    _activeDeliveryLiveLocationSubscription?.cancel();
    _activeDeliveryLiveLocationSubscription = db
        .collection('activeDeliveries')
        .doc(normalized)
        .snapshots()
        .listen((snapshot) {
      add(ActiveDeliveryLiveLocationChanged(data: snapshot.data()));
    });
  }

  void _handleCheckForPushToken(
    CheckForPushToken event,
    Emitter<SendPackageState> emit,
  ) async {
    final storage = FlutterSecureStorage();
    final fcmToken = await firebaseMessaging.getToken();
    if (fcmToken != null) {
      try {
        await storage.write(key: "pushToken", value: fcmToken);
        final User? user = auth.currentUser;

        final documentReference = db.collection('users').doc(user?.uid);

        // Get the document snapshot
        final documentSnapshot = await documentReference.get();
        if (documentSnapshot.exists) {
          await db
              .collection("users")
              .doc(user?.uid)
              .update({'fcmToken': fcmToken}).then(
            (value) {},
            onError: (e) {},
          );
        }
      } catch (e) {
        debugPrint('Push token update failed');
      }
    }
  }

  void _handleSearchAPlaceEvent(
    SearchAPlaceEvent event,
    Emitter<SendPackageState> emit,
  ) async {
    const uuid = Uuid();
    if (event.query.trim().length < 3) {
      emit(
        state.copyWith(
          suggestions: [],
          isAddressSearching: false,
          addressSearchError: '',
        ),
      );
      return;
    }
    emit(state.copyWith(isAddressSearching: true, addressSearchError: ''));
    try {
      List<Suggestion> suggestions = await PlaceApiProvider(
        uuid,
      ).fetchSuggestions(event.query, event.lang);

      emit(
        state.copyWith(
          suggestions: suggestions,
          isAddressSearching: false,
          addressSearchError: suggestions.isEmpty
              ? "Couldn't find matching addresses. Please continue typing or try again."
              : '',
        ),
      );
    } catch (e) {
      print(e);
      emit(
        state.copyWith(
          suggestions: [],
          isAddressSearching: false,
          addressSearchError:
              "Couldn't find matching addresses. Please continue typing or try again.",
        ),
      );
    }
  }

  void _handleSetDrawerHeight(
    SetDrawerHeight event,
    Emitter<SendPackageState> emit,
  ) {
    emit(
      state.copyWith(
        minDrawerHeight: event.minDrawerHeight,
        maxDrawerHeight: event.maxDrawerHeight,
        panelControlStatus: PanelControlStatus.isOpened,
      ),
    );
  }

  void _handleClearSuggestionsEvent(
    ClearSuggestions event,
    Emitter<SendPackageState> emit,
  ) {
    emit(state.copyWith(suggestions: []));
  }

  void _handleSetPickupAddressEvent(
    SetPickupAddress event,
    Emitter<SendPackageState> emit,
  ) async {
    const uuid = Uuid();

    emit(
      state.copyWith(
        pickupLocation: event.val,
        pickupLocationSubAddress: event.pickupLocationSubAddress,
        destinationLocation: '',
        destinationLocationSubAddress: '',
      ),
    );

    try {
      PlaceCoordinate coordinate = await PlaceApiProvider(
        uuid,
      ).fetchPlaceDetails(event.placeId, event.lang);

      print('Pickup coordinate: $coordinate');

      var address = await placemarkFromCoordinates(
        coordinate.lat,
        coordinate.lng,
      );

      emit(
        state.copyWith(
          pickupCoordinate: coordinate,
          pickupLocality: address[0].locality,
        ),
      );
    } catch (e) {
      print(e);
    }
  }

  void _handleSetDeliveryAddress(SetDeliveryAddress event, Emitter emit) async {
    const uuid = Uuid();
    emit(
      state.copyWith(
        destinationLocation: event.val,
        destinationLocationSubAddress: event.destinationLocationSubAddress,
      ),
    );

    if (state.pickupLocationSubAddress?.split(',').last ==
        event.destinationLocationSubAddress.split(',').last) {
      add(
        SetDrawerHeight(
          minDrawerHeight: state.minDrawerHeight,
          maxDrawerHeight: 0.55.sh,
        ),
      );
    }
    try {
      PlaceCoordinate coordinate = await PlaceApiProvider(
        uuid,
      ).fetchPlaceDetails(event.placeId, event.lang);

      print('Destination coordinate: $coordinate');
      // var addresses = await Geocoder.google ( '<---------YOUR APIKEY-------->' ).findAddressesFromCoordinates(coordinates);
      var address = await placemarkFromCoordinates(
        coordinate.lat,
        coordinate.lng,
        // localeIdentifier: "en_US"
      );

      emit(
        state.copyWith(
          desinationCoordinate: coordinate,
          destinationLocality: address[0].locality,
        ),
      );

      if (state.pickupCoordinate != null &&
          state.pickupLocationSubAddress?.split(',').last ==
              event.destinationLocationSubAddress.split(',').last) {
        List<LatLng> latLngList = [];

        PolylinePoints points = PolylinePoints();

        PolylineResult polylineResult = await points.getRouteBetweenCoordinates(
          request: PolylineRequest(
            origin: PointLatLng(
              state.pickupCoordinate!.lat,
              state.pickupCoordinate!.lng,
            ),
            destination: PointLatLng(
              state.desinationCoordinate!.lat,
              state.desinationCoordinate!.lng,
            ),
            mode: TravelMode.driving,
          ),
          googleApiKey: 'AIzaSyDWH0L6pjdf2W_ZZrjfv6z5OvMZQ2TVNMI',
        );

        if (polylineResult.points.isNotEmpty) {
          double tripDistance;
          tripDistance = polylineResult.totalDistanceValue!.toDouble() / 1000;
          // print(polylineResult.distance);
          // print(polylineResult.distanceText);
          // print(polylineResult.distanceValue);
          polylineResult.points.forEach((ele) {
            latLngList.add(LatLng(ele.latitude, ele.longitude));
          });

          List<Polyline> polyLines = [];
          polyLines.add(
            Polyline(
              polylineId: const PolylineId('PolylineId'),
              points: latLngList,
              width: 3,
              color: AppColors.primary,
            ),
          );

          final Marker sourceMarker = Marker(
            markerId: const MarkerId('source_marker'),
            position: LatLng(
              state.pickupCoordinate!.lat,
              state.pickupCoordinate!.lng,
            ), // Source address location
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
          );

          final Marker destinationMarker = Marker(
            markerId: const MarkerId('destination_marker'),
            position: LatLng(
              state.desinationCoordinate!.lat,
              state.desinationCoordinate!.lng,
            ), // Destination address location
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
          );

          Map<MarkerId, Marker> markers = {
            const MarkerId('source_marker'): sourceMarker,
            const MarkerId('destination_marker'): destinationMarker,
          };

          emit(
            state.copyWith(
              polylines: polyLines,
              markers: markers,
              distance: tripDistance,
            ),
          );
          add(SetPrice());

          add(
            SetSourceAndDestinationStatus(
              status: SourceAndDestinationStatus.selected,
            ),
          );
        }
        // add(CalculateDistance());
      }
    } catch (e) {
      print(e);
    }
  }

  void _handleSetDeliveryStatusEvent(
    SetDeliveryStatus event,
    Emitter<SendPackageState> emit,
  ) {
    emit(state.copyWith(deliveryStatus: event.deliveryStatus));
  }

  void _handleCalculateDistance(
    CalculateDistance event,
    Emitter<SendPackageState> emit,
  ) async {
    print('${state.pickupCoordinate!.lat}');
    print('${state.pickupCoordinate!.lng}');
    print('${state.desinationCoordinate!.lat}');
    print('${state.desinationCoordinate!.lng}');
    try {
      final double distanceInMetres = Geolocator.distanceBetween(
        state.pickupCoordinate!.lat,
        state.pickupCoordinate!.lng,
        state.desinationCoordinate!.lat,
        state.desinationCoordinate!.lng,
      );

      double distanceInKilometres = distanceInMetres / 1000;
      String inString = distanceInKilometres.toStringAsFixed(2);
      double distanceInTwoDecimalPlaces = double.parse(inString);

      emit(state.copyWith(distance: distanceInTwoDecimalPlaces));

      // print(distanceInKilometres);
    } catch (e) {
      print(e);
    }
  }

  void _handleSetDistance(SetDistance event, Emitter<SendPackageState> emit) {
    emit(state.copyWith(distance: event.value));
    add(SetPrice());
  }

  void _handleSetPrice(SetPrice event, Emitter<SendPackageState> emit) {
    final distanceKm = state.distance ?? 0;
    final quote = DeliveryPricing.calculate(
      DeliveryPricingInput(
        distanceMiles: DeliveryPricing.kilometresToMiles(distanceKm),
        weightKg: state.parcelWeightKg,
      ),
    );

    emit(state.copyWith(price: quote.total));
  }

  void _handleSetParcelWeight(
    SetParcelWeight event,
    Emitter<SendPackageState> emit,
  ) async {
    final itemDescription =
        event.itemDescription ?? state.itemDescription ?? '';
    final quickEstimate = itemDescription.trim().isEmpty
        ? null
        : IrisWeightEstimator.knownProductEstimate(itemDescription);
    final quickWeight = DeliveryPricing.checkoutPricingWeightKg(
      userEnteredWeightKg: event.weightKg,
      irisEstimatedWeightKg: quickEstimate?.weightKg,
    );
    emit(
      state.copyWith(
        parcelWeightKg: quickWeight,
        irisResult: quickEstimate,
        itemDescription:
            itemDescription.trim().isEmpty ? null : itemDescription,
        isIrisResolving: quickEstimate != null,
      ),
    );
    add(SetPrice());
    if (quickEstimate == null) return;
    try {
      final trusted = await IrisLearningBridge.resolveWithHistory(
        description: itemDescription,
        quantity: quickEstimate.quantity,
        userWeightKg: event.weightKg,
      );
      final finalWeight = DeliveryPricing.checkoutPricingWeightKg(
        userEnteredWeightKg: event.weightKg,
        irisEstimatedWeightKg: trusted.pricingWeightKg,
      );
      emit(
        state.copyWith(
          parcelWeightKg: finalWeight,
          irisResult: quickEstimate,
          itemDescription: itemDescription,
          isIrisResolving: false,
        ),
      );
      add(SetPrice());
    } catch (_) {
      emit(
        state.copyWith(
          parcelWeightKg: quickWeight,
          irisResult: quickEstimate,
          itemDescription: itemDescription,
          isIrisResolving: false,
        ),
      );
      add(SetPrice());
    }
  }

  void _handleRequestCanonicalIrisEstimate(
    RequestCanonicalIrisEstimate event,
    Emitter<SendPackageState> emit,
  ) async {
    final itemDescription = [
      event.itemName,
      event.description,
    ].where((value) => value.trim().isNotEmpty).join(' · ');
    emit(
      state.copyWith(
        itemDescription:
            itemDescription.trim().isEmpty ? null : itemDescription,
        isIrisResolving: true,
        irisErrorMessage: '',
        canonicalIrisResult: null,
      ),
    );
    try {
      final payload = <String, dynamic>{
        'description':
            itemDescription.trim().isEmpty ? event.itemName : itemDescription,
        'packageDescription':
            itemDescription.trim().isEmpty ? event.itemName : itemDescription,
        'declaredWeightText': event.declaredWeightText,
        'weight': event.declaredWeightText,
        'quantity': event.quantity,
        'fragile': event.fragile,
        'highValue': event.highValue,
        'pickupAddress': state.pickupLocation,
        'dropoffAddress': state.destinationLocation,
        'pickupPostcode': state.pickupLocationSubAddress,
        'dropoffPostcode': state.destinationLocationSubAddress,
        if (state.distance != null)
          'distanceMiles': DeliveryPricing.kilometresToMiles(state.distance!),
      };
      final result = await FirebaseFunctions.instance
          .httpsCallable('analyseIris')
          .call(payload);
      final data = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : <String, dynamic>{};
      final canonical = CanonicalIrisResult.fromCallable(
        data,
        fallbackItemName: event.itemName,
        fallbackQuantity: event.quantity <= 0 ? 1 : event.quantity,
      );
      emit(
        state.copyWith(
          canonicalIrisResult: canonical,
          isIrisResolving: false,
          irisErrorMessage: '',
          parcelWeightKg: canonical.totalWeightKg ?? state.parcelWeightKg,
        ),
      );
      add(SetPrice());
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'analyseIris failed: code=${error.code}, message=${error.message}, details=${error.details}',
      );
      emit(
        state.copyWith(
          isIrisResolving: false,
          irisErrorMessage:
              "IRIS couldn't complete the estimate. Please try again.",
        ),
      );
    } catch (error) {
      debugPrint('analyseIris unexpected failure: $error');
      emit(
        state.copyWith(
          isIrisResolving: false,
          irisErrorMessage:
              "IRIS couldn't complete the estimate. Please try again.",
        ),
      );
    }
  }

  double _numFrom(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  List<Map<String, dynamic>> _lineItemsFrom(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _callableMap(
    String name,
    Map<String, dynamic> payload,
  ) async {
    final result =
        await FirebaseFunctions.instance.httpsCallable(name).call(payload);
    return result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : <String, dynamic>{};
  }

  void _handleRequestSenderBookingQuote(
    RequestSenderBookingQuote event,
    Emitter<SendPackageState> emit,
  ) async {
    emit(
      state.copyWith(
        isSenderQuoteLoading: true,
        senderQuoteError: '',
      ),
    );
    try {
      final data = await _callableMap('createSenderBookingQuote', {
        if (event.businessContext != null)
          'businessContext': event.businessContext,
        'selectedSpeed': event.selectedSpeed,
        'vanguardProtocolEnabled': event.vanguardProtocolEnabled,
        'distanceMiles': state.distance == null
            ? 0
            : DeliveryPricing.kilometresToMiles(state.distance!),
        'weightKg':
            state.parcelWeightKg <= 0 ? event.weightKg : state.parcelWeightKg,
        'parcel': {
          'itemName': event.itemName,
          'description': event.description,
          'weightKg': event.weightKg,
          'fragile': event.fragile,
          'highValue': event.highValue,
        },
        'iris': {
          if (state.canonicalIrisResult != null) ...{
            'itemName': state.canonicalIrisResult!.itemName,
            'quantity': state.canonicalIrisResult!.quantity,
            'totalWeightKg': state.canonicalIrisResult!.totalWeightKg,
            'category': state.canonicalIrisResult!.category,
            'recommendedVehicle': state.canonicalIrisResult!.recommendedVehicle,
            'confidence': state.canonicalIrisResult!.confidenceLabel,
            'vanguardRequired': state.canonicalIrisResult!.vanguardRequired,
            'vanguardRequiredReason':
                state.canonicalIrisResult!.vanguardRequiredReason,
          },
        },
      });
      emit(
        state.copyWith(
          isSenderQuoteLoading: false,
          senderQuoteId: '${data['quoteId'] ?? ''}',
          senderQuoteTotal: _numFrom(
            data['total'] ?? data['finalAmount'] ?? data['amountDue'],
          ),
          senderQuoteSpeed: '${data['selectedSpeed'] ?? event.selectedSpeed}',
          senderQuoteLineItems: _lineItemsFrom(data['lineItems']),
          price: _numFrom(
            data['total'] ?? data['finalAmount'] ?? data['amountDue'],
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'createSenderBookingQuote failed: code=${error.code}, message=${error.message}, details=${error.details}',
      );
      emit(
        state.copyWith(
          isSenderQuoteLoading: false,
          senderQuoteError:
              error.message ?? 'Could not load delivery quote. Try again.',
        ),
      );
    } catch (error) {
      debugPrint('createSenderBookingQuote unexpected failure: $error');
      emit(
        state.copyWith(
          isSenderQuoteLoading: false,
          senderQuoteError: 'Could not load delivery quote. Try again.',
        ),
      );
    }
  }

  void _handleLoadSenderRothBalance(
    LoadSenderRothBalance event,
    Emitter<SendPackageState> emit,
  ) async {
    emit(
      state.copyWith(isSenderRothLoading: true, senderRothError: ''),
    );
    try {
      final data = await _callableMap('getSenderRothBalance', const {});
      emit(
        state.copyWith(
          isSenderRothLoading: false,
          senderRothBalance: _numFrom(data['availableRoth'] ?? data['balance']),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'getSenderRothBalance failed: code=${error.code}, message=${error.message}, details=${error.details}',
      );
      emit(
        state.copyWith(
          isSenderRothLoading: false,
          senderRothError:
              error.message ?? 'Roth balance is unavailable right now.',
        ),
      );
    } catch (error) {
      debugPrint('getSenderRothBalance unexpected failure: $error');
      emit(
        state.copyWith(
          isSenderRothLoading: false,
          senderRothError: 'Roth balance is unavailable right now.',
        ),
      );
    }
  }

  void _handleStartSenderPaymentSession(
    StartSenderPaymentSession event,
    Emitter<SendPackageState> emit,
  ) async {
    if (state.senderQuoteId == null || state.senderQuoteId!.isEmpty) {
      emit(
        state.copyWith(
          senderPaymentError: 'Load your delivery estimate before payment.',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        isSenderPaymentLoading: true,
        senderPaymentError: '',
      ),
    );
    try {
      final data = await _callableMap('createSenderPaymentSession', {
        'quoteId': state.senderQuoteId,
        'rothEnabled': event.rothEnabled,
        'fallbackMethod': event.fallbackMethod,
        'paymentMethodId': event.paymentMethodId,
      });
      emit(
        state.copyWith(
          isSenderPaymentLoading: false,
          senderPaymentSessionId: '${data['paymentSessionId'] ?? ''}',
          senderPaymentStatus:
              '${data['paymentStatus'] ?? data['status'] ?? ''}',
          senderPaymentClientSecret:
              data['clientSecret'] == null ? null : '${data['clientSecret']}',
          senderPaymentIntentId: data['stripePaymentIntentId'] == null
              ? null
              : '${data['stripePaymentIntentId']}',
          senderPaymentCustomerId:
              data['customerId'] == null ? null : '${data['customerId']}',
          senderPaymentEphemeralKeySecret: data['ephemeralKeySecret'] == null
              ? null
              : '${data['ephemeralKeySecret']}',
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'createSenderPaymentSession failed: code=${error.code}, message=${error.message}, details=${error.details}',
      );
      emit(
        state.copyWith(
          isSenderPaymentLoading: false,
          senderPaymentError:
              error.message ?? "Payment couldn't be started. Please try again.",
        ),
      );
    } catch (error) {
      debugPrint('createSenderPaymentSession unexpected failure: $error');
      emit(
        state.copyWith(
          isSenderPaymentLoading: false,
          senderPaymentError: "Payment couldn't be started. Please try again.",
        ),
      );
    }
  }

  void _handleCreatePaidSenderDelivery(
    CreatePaidSenderDelivery event,
    Emitter<SendPackageState> emit,
  ) async {
    if (state.senderPaymentStatus != 'succeeded' ||
        state.senderPaymentSessionId == null ||
        state.senderQuoteId == null) {
      emit(
        state.copyWith(
          senderDeliveryError:
              'Payment must be confirmed before delivery creation.',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        isSenderDeliveryCreating: true,
        senderDeliveryError: '',
      ),
    );
    try {
      final payload = {
        ...event.bookingPayload,
        'quoteId': state.senderQuoteId,
        'paymentSessionId': state.senderPaymentSessionId,
      };
      final data = await _callableMap('createSenderPaidDelivery', payload);
      final requestId = '${data['requestId'] ?? ''}';
      if (requestId.isNotEmpty) {
        await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('sendPackage')
            .call({'requestId': requestId});
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('activeRequest', requestId);
        add(WatchActiveDelivery(requestId: requestId));
      }
      emit(
        state.copyWith(
          isSenderDeliveryCreating: false,
          senderCreatedRequestId: requestId,
          deliveryStatus: DeliveryStatus.deliveryConfirmed,
          deliveryRequestStatus: 'requested',
        ),
      );
      add(SetDrawerHeight(minDrawerHeight: 180, maxDrawerHeight: 0.5.sh));
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'createSenderPaidDelivery failed: code=${error.code}, message=${error.message}, details=${error.details}',
      );
      emit(
        state.copyWith(
          isSenderDeliveryCreating: false,
          senderDeliveryError:
              error.message ?? 'Delivery could not be created after payment.',
        ),
      );
    } catch (error) {
      debugPrint('createSenderPaidDelivery unexpected failure: $error');
      emit(
        state.copyWith(
          isSenderDeliveryCreating: false,
          senderDeliveryError: 'Delivery could not be created after payment.',
        ),
      );
    }
  }

  void _handleSendDeliveryRequestEvent(
    SendDeliveryRequest event,
    Emitter emit,
  ) async {
    emit(
      state.copyWith(
        senderDeliveryError:
            'Please continue with the secure booking flow to create this delivery.',
      ),
    );
  }

  void _handleDeliveryAcceptedEvent(
    DeliveryAccepted event,
    Emitter emit,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final requestId = '${event.data['requestId'] ?? event.data['id'] ?? ''}';
    final DeliveryData deliveryData = DeliveryData.fromJson(event.data);
    if (requestId.isNotEmpty) {
      await prefs.setString('activeRequest', requestId);
      add(WatchActiveDelivery(requestId: requestId));
    }
    emit(
      state.copyWith(
        deliveryStatus: DeliveryStatus.deliveryOnGoing,
        deliveryRequestStatus: 'accepted',
        deliveryData: deliveryData,
      ),
    );
    add(SetDrawerHeight(minDrawerHeight: 180, maxDrawerHeight: 0.7.sh));
  }

  void _handleDeliveryCompleted(DeliveryCompleted event, Emitter emit) {
    print(event.data['historyId']);
    add(
      SetDrawerHeight(
        minDrawerHeight: state.minDrawerHeight,
        maxDrawerHeight: state.minDrawerHeight,
      ),
    );
    emit(
      state.copyWith(
        polylines: [],
        polylineCoordinates: [],
        markers: {},
        deliveryStatus: DeliveryStatus.deliveryCompleted,
        deliveryRequestStatus: 'completed',
        lastHistoryId: event.data['historyId'],
      ),
    );
  }

  void _handleSetSourceAndDestinationStatus(
    SetSourceAndDestinationStatus event,
    Emitter<SendPackageState> emit,
  ) {
    emit(state.copyWith(sourceAndDestinationStatus: event.status));
  }

  void _handleSetMapCameraStatusEvent(SetMapCameraStatus event, Emitter emit) {
    emit(state.copyWith(mapCameraStatus: event.status));
  }

  void _handleSetRiderLocationEvent(
    SetRiderLocation event,
    Emitter emit,
  ) async {
    final User? user = auth.currentUser;
    try {
      // print('In Bloc');
      double? lat = double.parse(event.data['latitude']);
      double? lng = double.parse(event.data['longitude']);
      PlaceCoordinate riderLocation = PlaceCoordinate(lat: lat, lng: lng);

      final icon = await BitmapDescriptorHelper.getBitmapDescriptorFromSvgAsset(
        "assets/svg/bike_top.svg",
      );
      final Marker riderLocationMarker = Marker(
        markerId: const MarkerId('rider_location_marker'),
        position: LatLng(lat, lng), // Destination address location
        rotation: state.riderLocation == null
            ? 0.0
            : calculateBearing(
                LatLng(state.riderLocation!.lat, state.riderLocation!.lng),
                LatLng(riderLocation.lat, riderLocation.lng),
              ),
        icon: icon,
      );

      Map<MarkerId, Marker> markers = {};

      markers[const MarkerId('rider_location_marker')] = riderLocationMarker;

      emit(
        state.copyWith(
          riderLocation: riderLocation,
          markers: markers,
          polylines: [],
        ),
      );
      add(SetMapCameraStatus(status: MapCameraStatus.showRiderLocation));

      if (state.deliveryData == null) {
        final documentReference =
            db.collection('deliveryRequests').doc(user!.uid);

        final docResponse = await documentReference.get();

        if (docResponse.exists) {
          final deliveryData = DeliveryData.fromJson(event.data);
          emit(state.copyWith(deliveryData: deliveryData));
        }

        if (state.deliveryStatus != DeliveryStatus.deliveryOnGoing) {
          emit(state.copyWith(deliveryStatus: DeliveryStatus.deliveryOnGoing));

          add(SetDrawerHeight(minDrawerHeight: 180, maxDrawerHeight: 0.7.sh));
        }
      }
    } catch (e) {
      print(e);
    }
  }

  void _handleWatchActiveDeliveryEvent(
    WatchActiveDelivery event,
    Emitter<SendPackageState> emit,
  ) {
    _listenToActiveDelivery(event.requestId);
  }

  void _handleActiveDeliverySnapshotChanged(
    ActiveDeliverySnapshotChanged event,
    Emitter<SendPackageState> emit,
  ) {
    if (event.errorMessage != null) {
      emit(state.copyWith(senderDeliveryError: event.errorMessage));
      return;
    }
    final data = event.data;
    if (data == null) return;

    final requestStatus = '${data['status'] ?? ''}'.trim();
    final pickupDetails = _contactFromDelivery(
      data['pickupDetails'],
      fallback: state.pickupDetails,
    );
    final dropoffDetails = _contactFromDelivery(
      data['dropoffDetails'],
      fallback: state.dropoffDetails,
    );
    final riderLocation = _riderLocationFromDelivery(data);
    final deliveryData = DeliveryData.fromJson(data);

    emit(
      state.copyWith(
        deliveryStatus: _deliveryStatusForBackendStatus(requestStatus),
        deliveryRequestStatus: requestStatus,
        activeDeliveryData: Map<String, dynamic>.from(data),
        pickupDetails: pickupDetails,
        dropoffDetails: dropoffDetails,
        pickupLocation:
            '${data['pickupDetails']?['address'] ?? state.pickupLocation ?? ''}'
                    .trim()
                    .isEmpty
                ? state.pickupLocation
                : '${data['pickupDetails']?['address']}',
        destinationLocation:
            '${data['dropoffDetails']?['address'] ?? state.destinationLocation ?? ''}'
                    .trim()
                    .isEmpty
                ? state.destinationLocation
                : '${data['dropoffDetails']?['address']}',
        price: (data['price'] as num?)?.toDouble() ?? state.price,
        currency: '${data['currency'] ?? state.currency}',
        deliveryData: deliveryData,
        riderLocation: riderLocation ?? state.riderLocation,
        collectionPinVerified: data['collectionPinVerified'] == true,
        deliveryPinVerified: data['deliveryPinVerified'] == true,
        senderDeliveryError: '',
      ),
    );
  }

  void _handleActiveDeliveryLiveLocationChanged(
    ActiveDeliveryLiveLocationChanged event,
    Emitter<SendPackageState> emit,
  ) {
    final liveLocation = event.data?['riderLiveLocation'];
    final riderLocation = _coordinateFromPosition(liveLocation);
    if (riderLocation == null) return;
    emit(
      state.copyWith(
        riderLocation: riderLocation,
        riderLiveLocationUpdatedAt: _dateTimeFromValue(
          liveLocation is Map ? liveLocation['updatedAt'] : null,
        ),
        riderLiveLocationHeading: _doubleFromValue(
          liveLocation is Map ? liveLocation['heading'] : null,
        ),
      ),
    );
  }

  DeliveryStatus _deliveryStatusForBackendStatus(String status) {
    final normalized = status.trim().toLowerCase().replaceAll('-', '_');
    if (normalized == 'delivered' ||
        normalized == 'completed' ||
        normalized == 'delivery_completed') {
      return DeliveryStatus.deliveryCompleted;
    }
    if (_activeRequestStatuses.contains(normalized)) {
      return DeliveryStatus.reconnectingWithRider;
    }
    if (normalized == 'requested' ||
        normalized == 'pending' ||
        normalized == 'unmatched' ||
        normalized == 'finding_rider') {
      return DeliveryStatus.deliveryConfirmed;
    }
    return DeliveryStatus.reconnectingWithRider;
  }

  static const Set<String> _activeRequestStatuses = {
    'requested',
    'pending',
    'unmatched',
    'finding_rider',
    'accepted',
    'rider_assigned',
    'navigating_to_pickup',
    'arrived_at_pickup',
    'waiting',
    'pickup_verification',
    'pickup_verified',
    'collected',
    'outfordelivery',
    'out_for_delivery',
    'navigating_to_dropoff',
    'arrived_at_dropoff',
    'pin_required',
    'issue_reported',
    'cancelled',
    'canceled',
    'cancelled_verified_discrepancy',
    'sender_no_show_pickup',
  };

  ContactInfo? _contactFromDelivery(
    Object? value, {
    ContactInfo? fallback,
  }) {
    if (value is! Map) return fallback;
    final coordinate = _coordinateFromPosition(value['position']);
    if (coordinate == null) return fallback;
    return ContactInfo.fromJson(
      address: coordinate,
      fullname: '${value['fullname'] ?? ''}',
      phoneNumber: '${value['phone'] ?? ''}',
      moreInformation: '${value['moreInformation'] ?? ''}',
      locality: '${value['locality'] ?? ''}',
    );
  }

  PlaceCoordinate? _coordinateFromPosition(Object? value) {
    if (value is! Map) return null;
    final geo = value['geopoint'] ?? value['geoPoint'] ?? value['location'];
    if (geo is GeoPoint) {
      return PlaceCoordinate(lat: geo.latitude, lng: geo.longitude);
    }
    if (geo is Map) {
      final lat = (geo['latitude'] ?? geo['lat']) as num?;
      final lng = (geo['longitude'] ?? geo['lng']) as num?;
      if (lat != null && lng != null) {
        return PlaceCoordinate(lat: lat.toDouble(), lng: lng.toDouble());
      }
    }
    final lat = (value['latitude'] ?? value['lat']) as num?;
    final lng = (value['longitude'] ?? value['lng']) as num?;
    if (lat != null && lng != null) {
      return PlaceCoordinate(lat: lat.toDouble(), lng: lng.toDouble());
    }
    return null;
  }

  PlaceCoordinate? _riderLocationFromDelivery(Map<String, dynamic> data) {
    for (final candidate in [
      data['riderLiveLocation'],
      data['riderLocation'],
    ]) {
      final parsed = _coordinateFromPosition(candidate);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _dateTimeFromValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  double? _doubleFromValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}');
  }

  void _handleCheckForActiveRequestEvent(
    CheckForActiveRequest event,
    Emitter emit,
  ) async {
    final User? user = auth.currentUser;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? activeRequest = prefs.getString('activeRequest');

    if (activeRequest != null) {
      add(WatchActiveDelivery(requestId: activeRequest));
      final userDocumentReference =
          db.collection('deliveryRequests').doc(user!.uid);
      final requestDocumentReference =
          db.collection('deliveryRequests').doc(activeRequest);

      var docResponse = await userDocumentReference.get();
      if (!docResponse.exists) {
        docResponse = await requestDocumentReference.get();
      }

      if (docResponse.exists) {
        _listenToActiveDeliveryLiveLocation(docResponse.id);
        print('There is an active ride');
        final data = docResponse.data();
        String? pickupAddress = data!['pickupDetails']['address'];
        String? dropoffAddress = data['dropoffDetails']['address'];
        double? price = data['price'];
        String? currency = data['currency'];

        GeoPoint pickUpGeoPoint = data['pickupDetails']['position']['geopoint'];
        GeoPoint dropoffGeoPoint =
            data['pickupDetails']['position']['geopoint'];

        PlaceCoordinate pickUpCoordinates = PlaceCoordinate(
          lat: pickUpGeoPoint.latitude,
          lng: pickUpGeoPoint.longitude,
        );
        PlaceCoordinate dropoffCoordinates = PlaceCoordinate(
          lat: dropoffGeoPoint.latitude,
          lng: dropoffGeoPoint.longitude,
        );

        final ContactInfo pickupDetails = ContactInfo.fromJson(
          address: pickUpCoordinates,
          moreInformation: data['pickupDetails']['moreInformation'],
        );

        final ContactInfo dropoffDetails = ContactInfo.fromJson(
          address: dropoffCoordinates,
          moreInformation: data['dropoffDetails']['moreInformation'],
        );

        DeliveryStatus? status;
        // print(data['status']);
        // if (data['status'] == 'requested') {
        //   await documentReference.delete();
        // }

        final requestStatus = '${data['status'] ?? ''}';
        if (_activeRequestStatuses
            .contains(requestStatus.toLowerCase().replaceAll('-', '_'))) {
          status = DeliveryStatus.reconnectingWithRider;
          final deliveryData = DeliveryData.fromJson(data);
          emit(
            state.copyWith(
              deliveryStatus: status,
              deliveryRequestStatus: requestStatus,
              pickupDetails: pickupDetails,
              dropoffDetails: dropoffDetails,
              pickupLocation: pickupAddress,
              destinationLocation: dropoffAddress,
              price: price,
              currency: currency,
              deliveryData: deliveryData,
              riderLocation: _riderLocationFromDelivery(data),
              collectionPinVerified: data['collectionPinVerified'] == true,
              deliveryPinVerified: data['deliveryPinVerified'] == true,
            ),
          );
        }

        if (requestStatus == 'completed' || requestStatus == 'delivered') {
          status = DeliveryStatus.deliveryCompleted;
          emit(
            state.copyWith(
              lastHistoryId: data['historyId'],
              deliveryStatus: status,
              deliveryRequestStatus: requestStatus,
              deliveryData: DeliveryData.fromJson(data),
              collectionPinVerified: data['collectionPinVerified'] == true,
              deliveryPinVerified: data['deliveryPinVerified'] == true,
            ),
          );
        }

        if (requestStatus == 'cancelled' || requestStatus == 'canceled') {
          emit(
            state.copyWith(
              deliveryStatus: DeliveryStatus.reconnectingWithRider,
              deliveryRequestStatus: requestStatus,
              pickupDetails: pickupDetails,
              dropoffDetails: dropoffDetails,
              pickupLocation: pickupAddress,
              destinationLocation: dropoffAddress,
              price: price,
              currency: currency,
              deliveryData: DeliveryData.fromJson(data),
              riderLocation: _riderLocationFromDelivery(data),
              collectionPinVerified: data['collectionPinVerified'] == true,
              deliveryPinVerified: data['deliveryPinVerified'] == true,
            ),
          );
        }

        // emit(state.copyWith());
      }
    } else {
      print('There is no active ride 🏍️');
    }
  }

  void _handleSetPanelControlStatusEvent(
    SetPanelControlStatus event,
    Emitter emit,
  ) {
    emit(state.copyWith(panelControlStatus: event.status));
  }

  void _handleSetNewMessage(SetNewMessage event, Emitter emit) {
    emit(state.copyWith(message: event.value));
  }

  void _handleIncomingMessage(IncomingMessage event, Emitter emit) async {
    final chatMessages = [...state.chatMessages];

    final newMessage = Message.fromJson(event.data);
    chatMessages.add(newMessage);

    emit(
      state.copyWith(
        chatMessages: chatMessages,
        chatStatus: ChatStatus.newMessage,
      ),
    );
  }

  void _handleMessageRiderEvent(MessageRider event, Emitter emit) async {
    try {
      final User? user = auth.currentUser;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? activeRequest = prefs.getString('activeRequest');

      final riderId = state.deliveryData?.riderId;

      if (user == null || activeRequest == null || riderId == null) {
        throw Exception('Cannot send message without an active delivery.');
      }

      emit(state.copyWith(message: ''));
      final callable =
          FirebaseFunctions.instance.httpsCallable('sendCircumMessage');
      await callable.call({
        'chatId': activeRequest,
        'message': event.message,
        'messageType': 'text',
      });
    } catch (e) {
      debugPrint('Sending message failed: $e');
    }
  }

  void _handleLoadChatMessagesEvent(
    LoadChatMessages event,
    Emitter emit,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? activeRequest = prefs.getString('activeRequest');

    if (activeRequest != null) {
      final jsonData = await ChatsHelper().loadChat(activeRequest);
      if (jsonData.isEmpty) return;
      print('Loading chats');

      final messagesList = jsonData.map((e) => Message.fromJson(e)).toList();
      emit(
        state.copyWith(
          chatMessages: messagesList,
          chatStatus: ChatStatus.newMessage,
        ),
      );
    }
  }

  void _handleDeleteCompletedDelivery(
    DeleteCompletedDelivery event,
    Emitter emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('activeRequest');
    emit(state.copyWith(lastHistoryId: ''));
  }

  void _handleCancelRequestEvent(CancelRequest event, Emitter emit) async {
    final prefs = await SharedPreferences.getInstance();
    final activeRequest = prefs.getString('activeRequest') ??
        '${state.activeDeliveryData['id'] ?? ''}';
    if (activeRequest.trim().isNotEmpty) {
      try {
        await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('requestSenderCancellation')
            .call({
          'deliveryId': activeRequest,
          'idempotencyKey': '$activeRequest:legacy_sender_cancel',
        });
      } on FirebaseFunctionsException catch (error) {
        emit(
          state.copyWith(
            senderDeliveryError:
                error.message ?? 'Cancellation could not be completed.',
          ),
        );
        return;
      }
    }
    add(
      SetDrawerHeight(
        minDrawerHeight: state.minDrawerHeight,
        maxDrawerHeight: state.minDrawerHeight,
      ),
    );
    emit(
      state.copyWith(
        polylines: [],
        polylineCoordinates: [],
        markers: {},
        deliveryStatus: DeliveryStatus.inital,
      ),
    );
  }

  void _handleBackButtonPressedEvent(BackButtonPressed event, Emitter emit) {
    add(
      SetDrawerHeight(
        minDrawerHeight: state.minDrawerHeight,
        maxDrawerHeight: state.minDrawerHeight,
      ),
    );
    emit(
      state.copyWith(
        polylines: [],
        polylineCoordinates: [],
        markers: {},
        deliveryStatus: DeliveryStatus.inital,
      ),
    );
  }
}
