import 'dart:convert';

import 'package:circum/app/send_package/models/place_coordinates.m.dart';
import 'package:circum/utils/theme/colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';

import '../../../helper/messaging_server.dart';
import '../models/contact_info.dart';
import '../models/delivery_data.m.dart';
import '../models/suggestions.m.dart';
import '../repo/place_api.dart';

part 'send_package_event.dart';
part 'send_package_state.dart';

class SendPackageBloc extends Bloc<SendPackageEvent, SendPackageState> {
  SendPackageBloc() : super(SendPackageState()) {
    FirebaseAuth auth = FirebaseAuth.instance;
    FirebaseFirestore db = FirebaseFirestore.instance;
    final FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
    final geo = GeoFlutterFire();
    on<SendPackageEvent>((event, emit) {
      // TODO: implement event handler
    });

    on<CheckForPushToken>(
      (event, emit) async {
        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          try {
            final User? user = auth.currentUser;

            final documentReference = db.collection('users').doc(user?.uid);

            // Get the document snapshot
            final documentSnapshot = await documentReference.get();
            if (documentSnapshot.exists) {
              print('FCMToken: $fcmToken');
              await db.collection("users").doc(user?.uid).update({
                'fcmToken': fcmToken,
              }).then(
                  (value) => print("DocumentSnapshot successfully updated!"),
                  onError: (e) => print("Error updating document $e"));
            }
          } catch (e) {
            print('Push Token update error');
            print(e);
          }
        }
      },
    );

    on<SearchAPlaceEvent>(
      (event, emit) async {
        const uuid = Uuid();
        try {
          List<Suggestion> suggestions = await PlaceApiProvider(uuid)
              .fetchSuggestions(event.query, event.lang);

          emit(state.copyWith(suggestions: suggestions));
        } catch (e) {
          print(e);
        }
      },
    );

    on<ClearSuggestions>((event, emit) {
      emit(state.copyWith(suggestions: []));
    });

    on<SetPickupAddress>((event, emit) async {
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
    });

    on<SetDeliveryAddress>((event, emit) async {
      const uuid = Uuid();
      emit(state.copyWith(
          destinationLocation: event.val,
          destinationLocationSubAddress: event.destinationLocationSubAddress));

      try {
        PlaceCoordinate coordinate = await PlaceApiProvider(uuid)
            .fetchPlaceDetails(event.placeId, event.lang);

        print('Destination coordinate: $coordinate');
        var address =
            await placemarkFromCoordinates(coordinate.lat, coordinate.lng);

        emit(state.copyWith(
            desinationCoordinate: coordinate,
            destinationLocality: address[0].locality));

        if (state.pickupCoordinate != null) {
          List<LatLng> latLngList = [];

          PolylinePoints points = PolylinePoints();

          PolylineResult polylineResult =
              await points.getRouteBetweenCoordinates(
            'AIzaSyDWH0L6pjdf2W_ZZrjfv6z5OvMZQ2TVNMI',
            PointLatLng(
                state.pickupCoordinate!.lat, state.pickupCoordinate!.lng),
            PointLatLng(state.desinationCoordinate!.lat,
                state.desinationCoordinate!.lng),
            travelMode: TravelMode.driving,
          );

          if (polylineResult.points.isNotEmpty) {
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
                  state.desinationCoordinate!
                      .lng), // Destination address location
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
            );

            Map<MarkerId, Marker> markers = {
              const MarkerId('source_marker'): sourceMarker,
              const MarkerId('destination_marker'): destinationMarker
            };

            emit(state.copyWith(polylines: polyLines, markers: markers));
            add(SetSourceAndDestinationStatus(
                status: SourceAndDestinationStatus.selected));
          }
          // add(CalculateDistance());
        }
      } catch (e) {
        print(e);
      }
    });

    on<SetDeliveryStatus>((event, emit) {
      emit(state.copyWith(deliveryStatus: event.deliveryStatus));
    });

    on<CalculateDistance>((event, emit) async {
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
    });

    on<SetDistance>(((event, emit) {
      emit(state.copyWith(distance: event.value));
      add(SetPrice());
    }));

    on<SetPrice>(((event, emit) {
      double distanceKmToMiles = state.distance! / 1.6093;
      int roundedMiles = distanceKmToMiles.ceil();

      // Set the base price and additional charge per mile
      double basePrice = 6.0;
      double additionalChargePerMile = 3.0;

      // Calculate the total price
      double totalPrice =
          basePrice + (distanceKmToMiles - 1) * additionalChargePerMile;

      // Make sure the additional charge only applies for distances greater than 1 mile
      if (distanceKmToMiles < 1.6) {
        totalPrice = basePrice;
      }

      String inString = totalPrice.toStringAsFixed(2);
      double totalPriceInTwoDecimalPlaces = double.parse(inString);

      emit(state.copyWith(price: totalPriceInTwoDecimalPlaces));
    }));

    on<SendDeliveryRequest>((event, emit) async {
      print('Pickup Details');
      print(event.pickupDetails);
      print('Delivery Details');
      print(event.dropoffDetails);

      const uuid = Uuid();
      final uuid2 = uuid.v4();
      final uuid3 = uuid.v4();
      final uuidStrong = "$uuid2-$uuid3";

      print(uuidStrong);

      try {
        final User? user = auth.currentUser;

        GeoFirePoint pickupLocation = geo.point(
            latitude: event.pickupDetails.address.lat,
            longitude: event.pickupDetails.address.lng);

        GeoFirePoint dropoffLocation = geo.point(
            latitude: event.dropoffDetails.address.lat,
            longitude: event.pickupDetails.address.lng);

        final fcmToken = await FirebaseMessaging.instance.getToken();

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
          'pickupPosition': pickupLocation.data,
          'pickupLocality': event.pickupDetails.locality,
          'requestId': uuidStrong,
          'code': fcmToken,
          'status': 'requested'
        }).then((value) => print("DocumentSnapshot successfully created!"),
            onError: (e) => print("Error updating document $e"));

        // await firebaseMessaging
        //     .subscribeToTopic(uuidStrong)
        //     .then((value) => print(uuidStrong)); // Replace with your topic name

        // print(user);

        emit(state.copyWith(deliveryStatus: DeliveryStatus.deliveryConfirmed));
      } catch (e) {
        print(e);
      }
    });

    on<DeliveryAccepted>(
      (event, emit) async {
        final User? user = auth.currentUser;

        final activeDelivery = db.collection("deliveryRequests").doc(user?.uid);

        final activeDeliveryData = await activeDelivery.get();

        if (activeDeliveryData.exists &&
            activeDeliveryData.data()!['status'] == 'requested') {
          final DeliveryData deliveryData = DeliveryData.fromJson(event.data);

          await activeDelivery
              .update({'status': 'accepted', 'riderId': deliveryData.riderId});

          emit(state.copyWith(
              deliveryStatus: DeliveryStatus.deliveryOnGoing,
              deliveryData: deliveryData));
        }
      },
    );

    on<SetSourceAndDestinationStatus>(
      (event, emit) {
        emit(state.copyWith(sourceAndDestinationStatus: event.status));
      },
    );

    on<SetMapCameraStatus>(
      (event, emit) {
        emit(state.copyWith(mapCameraStatus: event.status));
      },
    );

    // Function to send a notification message
    void sendNotification() async {
      await MessagingServer().sendMessage(data: {
        'type': 'connection',
        'status': 'accepted',
      }, topic: 'your_topic_name');
    }
  }
}
