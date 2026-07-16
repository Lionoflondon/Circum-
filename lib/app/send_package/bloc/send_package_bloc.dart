import 'dart:convert';
import 'package:circum/app/send_package/models/place_coordinates.m.dart';
import 'package:circum/pricing/delivery_pricing.dart';
import 'package:circum/utils/theme/colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geocoding/geocoding.dart';
// import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';

import '../../../helper/bitmap_descriptor_helper.dart';
import '../../../helper/calculate_bearing.dart';
import '../../../helper/chats_help.dart';
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
    on<SendDeliveryRequest>(_handleSendDeliveryRequestEvent);
    on<DeliveryAccepted>(_handleDeliveryAcceptedEvent);
    on<DeliveryCompleted>(_handleDeliveryCompleted);
    on<SetSourceAndDestinationStatus>(_handleSetSourceAndDestinationStatus);
    on<SetMapCameraStatus>(_handleSetMapCameraStatusEvent);
    on<SetRiderLocation>(_handleSetRiderLocationEvent);
    on<CheckForActiveRequest>(_handleCheckForActiveRequestEvent);
    on<SetPanelControlStatus>(_handleSetPanelControlStatusEvent);
    on<SetNewMessage>(_handleSetNewMessage);
    on<IncomingMessage>(_handleIncomingMessage);
    on<MessageRider>(_handleMessageRiderEvent);
    on<LoadChatMessages>(_handleLoadChatMessagesEvent);
    on<DeleteCompletedDelivery>(_handleDeleteCompletedDelivery);
    on<CancelRequest>(_handleCancelRequestEvent);
    on<BackButtonPressed>(_handleBackButtonPressedEvent);
  }

  void _handleCheckForPushToken(
      CheckForPushToken event, Emitter<SendPackageState> emit) async {
    final storage = FlutterSecureStorage();
    final fcmToken = await firebaseMessaging.getToken();
    if (fcmToken != null) {
      try {
        print('saved token');
        await storage.write(key: "pushToken", value: fcmToken);
        final User? user = auth.currentUser;

        final documentReference = db.collection('users').doc(user?.uid);

        // Get the document snapshot
        final documentSnapshot = await documentReference.get();
        if (documentSnapshot.exists) {
          print('FCMToken: $fcmToken');
          await db.collection("users").doc(user?.uid).update({
            'fcmToken': fcmToken,
          }).then((value) => print("DocumentSnapshot successfully updated!"),
              onError: (e) => print("Error updating document $e"));
        }
      } catch (e) {
        print('Push Token update error');
        print(e);
      }
    }
  }

  void _handleSearchAPlaceEvent(
      SearchAPlaceEvent event, Emitter<SendPackageState> emit) async {
    const uuid = Uuid();
    try {
      List<Suggestion> suggestions = await PlaceApiProvider(uuid)
          .fetchSuggestions(event.query, event.lang);

      emit(state.copyWith(suggestions: suggestions));
    } catch (e) {
      print(e);
    }
  }

  void _handleSetDrawerHeight(
      SetDrawerHeight event, Emitter<SendPackageState> emit) {
    emit(state.copyWith(
        minDrawerHeight: event.minDrawerHeight,
        maxDrawerHeight: event.maxDrawerHeight,
        panelControlStatus: PanelControlStatus.isOpened));
  }

  void _handleClearSuggestionsEvent(
      ClearSuggestions event, Emitter<SendPackageState> emit) {
    emit(state.copyWith(suggestions: []));
  }

  void _handleSetPickupAddressEvent(
      SetPickupAddress event, Emitter<SendPackageState> emit) async {
    const uuid = Uuid();

    emit(state.copyWith(
        pickupLocation: event.val,
        pickupLocationSubAddress: event.pickupLocationSubAddress,
        destinationLocation: '',
        destinationLocationSubAddress: ''));

    try {
      PlaceCoordinate coordinate = await PlaceApiProvider(uuid)
          .fetchPlaceDetails(event.placeId, event.lang);

      print('Pickup coordinate: $coordinate');

      var address =
          await placemarkFromCoordinates(coordinate.lat, coordinate.lng);

      emit(state.copyWith(
          pickupCoordinate: coordinate, pickupLocality: address[0].locality));
    } catch (e) {
      print(e);
    }
  }

  void _handleSetDeliveryAddress(SetDeliveryAddress event, Emitter emit) async {
    const uuid = Uuid();
    emit(state.copyWith(
        destinationLocation: event.val,
        destinationLocationSubAddress: event.destinationLocationSubAddress));

    if (state.pickupLocationSubAddress?.split(',').last ==
        event.destinationLocationSubAddress.split(',').last) {
      add(SetDrawerHeight(
          minDrawerHeight: state.minDrawerHeight, maxDrawerHeight: 0.55.sh));
    }
    try {
      PlaceCoordinate coordinate = await PlaceApiProvider(uuid)
          .fetchPlaceDetails(event.placeId, event.lang);

      print('Destination coordinate: $coordinate');
      // var addresses = await Geocoder.google ( '<---------YOUR APIKEY-------->' ).findAddressesFromCoordinates(coordinates);
      var address = await placemarkFromCoordinates(
        coordinate.lat, coordinate.lng,
        // localeIdentifier: "en_US"
      );

      emit(state.copyWith(
          desinationCoordinate: coordinate,
          destinationLocality: address[0].locality));

      if (state.pickupCoordinate != null &&
          state.pickupLocationSubAddress?.split(',').last ==
              event.destinationLocationSubAddress.split(',').last) {
        List<LatLng> latLngList = [];

        PolylinePoints points = PolylinePoints();

        PolylineResult polylineResult = await points.getRouteBetweenCoordinates(
          request: PolylineRequest(
            origin: PointLatLng(
                state.pickupCoordinate!.lat, state.pickupCoordinate!.lng),
            destination: PointLatLng(state.desinationCoordinate!.lat,
                state.desinationCoordinate!.lng),
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
          polyLines.add(Polyline(
              polylineId: const PolylineId('PolylineId'),
              points: latLngList,
              width: 3,
              color: AppColors.primary));

          final Marker sourceMarker = Marker(
            markerId: const MarkerId('source_marker'),
            position: LatLng(state.pickupCoordinate!.lat,
                state.pickupCoordinate!.lng), // Source address location
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
          );

          final Marker destinationMarker = Marker(
            markerId: const MarkerId('destination_marker'),
            position: LatLng(
                state.desinationCoordinate!.lat,
                state
                    .desinationCoordinate!.lng), // Destination address location
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
          );

          Map<MarkerId, Marker> markers = {
            const MarkerId('source_marker'): sourceMarker,
            const MarkerId('destination_marker'): destinationMarker
          };

          emit(state.copyWith(
              polylines: polyLines, markers: markers, distance: tripDistance));
          add(SetPrice());

          add(SetSourceAndDestinationStatus(
              status: SourceAndDestinationStatus.selected));
        }
        // add(CalculateDistance());
      }
    } catch (e) {
      print(e);
    }
  }

  void _handleSetDeliveryStatusEvent(
      SetDeliveryStatus event, Emitter<SendPackageState> emit) {
    emit(state.copyWith(deliveryStatus: event.deliveryStatus));
  }

  void _handleCalculateDistance(
      CalculateDistance event, Emitter<SendPackageState> emit) async {
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
      SetParcelWeight event, Emitter<SendPackageState> emit) {
    emit(state.copyWith(parcelWeightKg: event.weightKg));
    add(SetPrice());
  }

  void _handleSendDeliveryRequestEvent(
      SendDeliveryRequest event, Emitter emit) async {
    const uuid = Uuid();
    final uuid2 = uuid.v4();
    final uuid3 = uuid.v4();
    final uuidStrong = "$uuid2-$uuid3";

    // print(uuidStrong);

    try {
      final User? user = auth.currentUser;
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final HttpsCallable callable = functions.httpsCallable('sendPackage');
      final apnsToken = await firebaseMessaging.getAPNSToken();
      // print('apnsToken: $apnsToken');
      final fcmToken = await firebaseMessaging.getToken();

      GeoFirePoint pickupLocation = GeoFirePoint(GeoPoint(
          event.pickupDetails.address.lat, event.pickupDetails.address.lng));

      GeoFirePoint dropoffLocation = GeoFirePoint(GeoPoint(
          event.dropoffDetails.address.lat, event.pickupDetails.address.lng));

      // Document does not exist
      // print('Document does not exist');
      await db.collection("deliveryRequests").doc(user?.uid).set({
        'pickupDetails': {
          'fullname': event.pickupDetails.fullname,
          'phone': event.pickupDetails.phoneNumber,
          'position': pickupLocation.data,
          'moreInformation': event.pickupDetails.moreInformation,
          'locality': event.pickupDetails.locality,
          'address': state.pickupLocation,
          'subAddress': state.pickupLocationSubAddress
        },
        'dropoffDetails': {
          'fullname': event.dropoffDetails.fullname,
          'phone': event.dropoffDetails.phoneNumber,
          'position': dropoffLocation.data,
          'moreInformation': event.dropoffDetails.moreInformation,
          'locality': event.dropoffDetails.locality,
          'address': state.destinationLocation,
          'subAddress': state.destinationLocationSubAddress
        },
        "role": 'user',
        'userId': user?.uid,
        'senderId': user?.uid,
        'senderName': user?.displayName,
        'senderEmail': user?.email,
        'pickupPosition': pickupLocation.data,
        'pickupLocality': event.pickupDetails.locality,
        'requestId': uuidStrong,
        'code': fcmToken,
        'price': state.price,
        'weightKg': state.parcelWeightKg,
        'pricingBreakdown': DeliveryPricing.calculate(
          DeliveryPricingInput(
            distanceMiles:
                DeliveryPricing.kilometresToMiles(state.distance ?? 0),
            weightKg: state.parcelWeightKg,
          ),
        ).toJson(),
        'currency': 'GBP',
        'stripePaymentIntentId': event.paymentIntentId,
        'paymentStatus': event.paymentIntentId == null ? 'pending' : 'succeeded',
        'status': 'requested',
        'createdAt': DateTime.now()
      }).then((value) => print("DocumentSnapshot successfully created!"),
          onError: (e) => print("Error updating document $e"));

      final response = await callable.call({
        // Any data you want to send to the function
        'requestId': uuidStrong
      });

      print('Function response: ${response.data}');

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('activeRequest', uuidStrong);

      // await firebaseMessaging
      //     .subscribeToTopic(uuidStrong)
      //     .then((value) => print(uuidStrong));
      // print(user);

      emit(state.copyWith(deliveryStatus: DeliveryStatus.deliveryConfirmed));
      add(SetDrawerHeight(minDrawerHeight: 180, maxDrawerHeight: 0.5.sh));
    } catch (e) {
      print(e);
    }
  }

  void _handleDeliveryAcceptedEvent(
      DeliveryAccepted event, Emitter emit) async {
    final User? user = auth.currentUser;
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final activeDelivery = db.collection("deliveryRequests").doc(user?.uid);

    final activeDeliveryData = await activeDelivery.get();

    if (activeDeliveryData.exists &&
        activeDeliveryData.data()!['status'] == 'requested') {
      print('Requested');
      final DeliveryData deliveryData = DeliveryData.fromJson(event.data);

      await activeDelivery.update({
        'status': 'accepted',
        'riderId': deliveryData.riderId,
        'estimatedDeliveryTime': deliveryData.estimatedDeliveryTime,
        'updatedAt': DateTime.now()
      });

      await prefs.setString(
          'activeRequest', activeDeliveryData.data()!['requestId']);

      emit(state.copyWith(
          deliveryStatus: DeliveryStatus.deliveryOnGoing,
          deliveryData: deliveryData));
      add(SetDrawerHeight(minDrawerHeight: 180, maxDrawerHeight: 0.7.sh));
    }
  }

  void _handleDeliveryCompleted(DeliveryCompleted event, Emitter emit) {
    print(event.data['historyId']);
    add(SetDrawerHeight(
        minDrawerHeight: state.minDrawerHeight,
        maxDrawerHeight: state.minDrawerHeight));
    emit(state.copyWith(
        polylines: [],
        polylineCoordinates: [],
        markers: {},
        deliveryStatus: DeliveryStatus.deliveryCompleted,
        lastHistoryId: event.data['historyId']));
  }

  void _handleSetSourceAndDestinationStatus(
      SetSourceAndDestinationStatus event, Emitter<SendPackageState> emit) {
    emit(state.copyWith(sourceAndDestinationStatus: event.status));
  }

  void _handleSetMapCameraStatusEvent(SetMapCameraStatus event, Emitter emit) {
    emit(state.copyWith(mapCameraStatus: event.status));
  }

  void _handleSetRiderLocationEvent(
      SetRiderLocation event, Emitter emit) async {
    final User? user = auth.currentUser;
    try {
      // print('In Bloc');
      double? lat = double.parse(event.data['latitude']);
      double? lng = double.parse(event.data['longitude']);
      PlaceCoordinate riderLocation = PlaceCoordinate(lat: lat, lng: lng);

      final icon = await BitmapDescriptorHelper.getBitmapDescriptorFromSvgAsset(
          "assets/svg/bike_top.svg");
      final Marker riderLocationMarker = Marker(
          markerId: const MarkerId('rider_location_marker'),
          position: LatLng(lat, lng), // Destination address location
          rotation: state.riderLocation == null
              ? 0.0
              : calculateBearing(
                  LatLng(state.riderLocation!.lat, state.riderLocation!.lng),
                  LatLng(riderLocation.lat, riderLocation.lng)),
          icon: icon);

      Map<MarkerId, Marker> markers = {};

      markers[const MarkerId('rider_location_marker')] = riderLocationMarker;

      emit(state.copyWith(
          riderLocation: riderLocation, markers: markers, polylines: []));
      add(SetMapCameraStatus(status: MapCameraStatus.showRiderLocation));

      if (state.deliveryData == null) {
        final documentReference =
            db.collection('deliveryRequests').doc(user!.uid);

        final docResponse = await documentReference.get();

        if (docResponse.exists) {
          final data = docResponse.data();

          // print(data);

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

  void _handleCheckForActiveRequestEvent(
      CheckForActiveRequest event, Emitter emit) async {
    final User? user = auth.currentUser;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? activeRequest = prefs.getString('activeRequest');

    if (activeRequest != null) {
      final documentReference =
          db.collection('deliveryRequests').doc(user!.uid);

      final docResponse = await documentReference.get();

      if (docResponse.exists) {
        print('There is an active ride');
        final data = docResponse.data();
        String? pickupAddress = data!['pickupDetails']['address'];
        String? dropoffAddress = data['dropoffDetails']['address'];
        double? price = data['price'];
        String? currency = data['currency'];

        GeoPoint pickUpGeoPoint =
            data!['pickupDetails']['position']['geopoint'];
        GeoPoint dropoffGeoPoint =
            data['pickupDetails']['position']['geopoint'];

        PlaceCoordinate pickUpCoordinates = PlaceCoordinate(
            lat: pickUpGeoPoint.latitude, lng: pickUpGeoPoint.longitude);
        PlaceCoordinate dropoffCoordinates = PlaceCoordinate(
            lat: dropoffGeoPoint.latitude, lng: dropoffGeoPoint.longitude);

        final ContactInfo pickupDetails = ContactInfo.fromJson(
            address: pickUpCoordinates,
            moreInformation: data['pickupDetails']['moreInformation']);

        final ContactInfo dropoffDetails = ContactInfo.fromJson(
            address: dropoffCoordinates,
            moreInformation: data['dropoffDetails']['moreInformation']);

        DeliveryStatus? status;
        // print(data['status']);
        // if (data['status'] == 'requested') {
        //   await documentReference.delete();
        // }

        if (data['status'] == 'accepted' ||
            data['status'] == 'outForDelivery' ||
            data['status'] == 'requested') {
          status = DeliveryStatus.reconnectingWithRider;
          emit(state.copyWith(
              deliveryStatus: status,
              pickupDetails: pickupDetails,
              dropoffDetails: dropoffDetails,
              pickupLocation: pickupAddress,
              destinationLocation: dropoffAddress,
              price: price,
              currency: currency));
        }

        if (data['status'] == 'completed') {
          status = DeliveryStatus.deliveryCompleted;
          emit(state.copyWith(
            lastHistoryId: data['historyId'],
            deliveryStatus: status,
          ));
        }

        // emit(state.copyWith());
      }
    } else {
      print('There is no active ride 🏍️');
    }
  }

  void _handleSetPanelControlStatusEvent(
      SetPanelControlStatus event, Emitter emit) {
    emit(state.copyWith(panelControlStatus: event.status));
  }

  void _handleSetNewMessage(SetNewMessage event, Emitter emit) {
    emit(state.copyWith(message: event.value));
  }

  void _handleIncomingMessage(IncomingMessage event, Emitter emit) async {
    final chatMessages = [...state.chatMessages];

    final newMessage = Message.fromJson(event.data);
    chatMessages.add(newMessage);

    emit(state.copyWith(
        chatMessages: chatMessages, chatStatus: ChatStatus.newMessage));
  }

  void _handleMessageRiderEvent(MessageRider event, Emitter emit) async {
    try {
      final User? user = auth.currentUser;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? activeRequest = prefs.getString('activeRequest');

      String msg = event.message;
      final riderId = state.deliveryData?.riderId;

      if (user == null || activeRequest == null || riderId == null) {
        throw Exception('Cannot send message without an active delivery.');
      }

      emit(state.copyWith(message: ''));

      // print('${state.deliveryData!.code}');

      final messageData = {
        'requestId': activeRequest,
        'senderId': user.uid,
        'message': msg,
        'timeStamp': '${DateTime.now()}'
      };

      final callable = FirebaseFunctions.instance.httpsCallable('sendMessage');
      await callable.call({
        'recipientId': riderId,
        'requestId': activeRequest,
        'message': event.message,
      });

      add(IncomingMessage(data: messageData));

      ChatsHelper().storeChat(messageData);
    } catch (e) {
      print('Sending messsage failed');
      print(e);
    }
  }

  void _handleLoadChatMessagesEvent(
      LoadChatMessages event, Emitter emit) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? activeRequest = prefs.getString('activeRequest');

    if (activeRequest != null) {
      final jsonData = await ChatsHelper().loadChat(activeRequest);
      if (jsonData.isEmpty) return;
      print('Loading chats');

      final messagesList = jsonData.map((e) => Message.fromJson(e)).toList();
      emit(state.copyWith(
          chatMessages: messagesList, chatStatus: ChatStatus.newMessage));
    }
  }

  void _handleDeleteCompletedDelivery(
      DeleteCompletedDelivery event, Emitter emit) async {
    try {
      User user = auth.currentUser!;
      final documentReference = db.collection('deliveryRequests').doc(user.uid);

      await documentReference.delete();
    } catch (e) {
      print(e);
    }
  }

  void _handleCancelRequestEvent(CancelRequest event, Emitter emit) async {
    final User? user = auth.currentUser;
    if (user == null) return;
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('cancelDelivery')
          .call({'deliveryId': user.uid});
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['success'] != true) {
        emit(state.copyWith(message:
            '${(data['decision'] as Map?)?['userFacingMessage'] ?? 'This delivery requires support review.'}'));
        return;
      }
      add(SetDrawerHeight(
          minDrawerHeight: state.minDrawerHeight,
          maxDrawerHeight: state.minDrawerHeight));
      emit(state.copyWith(
        polylines: [],
        polylineCoordinates: [],
        markers: {},
        deliveryStatus: DeliveryStatus.inital,
        message: 'Delivery cancelled.',
      ));
    } on FirebaseFunctionsException catch (error) {
      emit(state.copyWith(
          message: error.message ?? 'Cancellation was not confirmed.'));
    }
  }

  void _handleBackButtonPressedEvent(BackButtonPressed event, Emitter emit) {
    add(SetDrawerHeight(
        minDrawerHeight: state.minDrawerHeight,
        maxDrawerHeight: state.minDrawerHeight));
    emit(state.copyWith(
      polylines: [],
      polylineCoordinates: [],
      markers: {},
      deliveryStatus: DeliveryStatus.inital,
    ));
  }
}
