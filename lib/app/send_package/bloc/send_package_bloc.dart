import 'dart:convert';
import 'dart:io';

import 'package:circum/app/send_package/models/place_coordinates.m.dart';
import 'package:circum/utils/theme/colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';

import '../../../helper/bitmap_descriptor_helper.dart';
import '../../../helper/chats_help.dart';
import '../../../helper/messaging_server.dart';
import '../models/contact_info.dart';
import '../models/delivery_data.m.dart';
import '../models/message.m.dart';
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
        final fcmToken = await firebaseMessaging.getToken();
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

    on<SetDrawerHeight>((event, emit) {
      emit(state.copyWith(
          minDrawerHeight: event.minDrawerHeight,
          maxDrawerHeight: event.maxDrawerHeight,
          panelControlStatus: PanelControlStatus.isOpened));
    });

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
          add(SetDrawerHeight(
              minDrawerHeight: state.minDrawerHeight,
              maxDrawerHeight: 0.55.sh));
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
            double tripDistance;
            tripDistance =
                double.parse(polylineResult.distance!.split(' ').first.trim());
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

            emit(state.copyWith(
                polylines: polyLines,
                markers: markers,
                distance: tripDistance));
            add(SetPrice());

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

      // print(uuidStrong);

      try {
        final User? user = auth.currentUser;

        GeoFirePoint pickupLocation = geo.point(
            latitude: event.pickupDetails.address.lat,
            longitude: event.pickupDetails.address.lng);

        GeoFirePoint dropoffLocation = geo.point(
            latitude: event.dropoffDetails.address.lat,
            longitude: event.pickupDetails.address.lng);

        final apnsToken = await firebaseMessaging.getAPNSToken();
        print('apnsToken: $apnsToken');

        final fcmToken = await firebaseMessaging.getToken();

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
          'price': state.price,
          'currency': 'GBP',
          'status': 'requested',
          'createdAt': DateTime.now()
        }).then((value) => print("DocumentSnapshot successfully created!"),
            onError: (e) => print("Error updating document $e"));

        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('activeRequest', uuidStrong);

        // await firebaseMessaging
        //     .subscribeToTopic(uuidStrong)
        //     .then((value) => print(uuidStrong)); // Replace with your topic name

        // print(user);

        emit(state.copyWith(deliveryStatus: DeliveryStatus.deliveryConfirmed));
        add(SetDrawerHeight(minDrawerHeight: 180, maxDrawerHeight: 0.5.sh));
      } catch (e) {
        print(e);
      }
    });

    on<DeliveryAccepted>(
      (event, emit) async {
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
            'updatedAt': DateTime.now()
          });

          await prefs.setString(
              'activeRequest', activeDeliveryData.data()!['requestId']);

          emit(state.copyWith(
              deliveryStatus: DeliveryStatus.deliveryOnGoing,
              deliveryData: deliveryData));
          add(SetDrawerHeight(minDrawerHeight: 180, maxDrawerHeight: 0.7.sh));
        }
      },
    );

    on<DeliveryCompleted>(
      (event, emit) {
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

    on<SetRiderLocation>((event, emit) async {
      final User? user = auth.currentUser;
      try {
        // print('In Bloc');
        double? lat = double.parse(event.data['latitude']);
        double? lng = double.parse(event.data['longitude']);
        PlaceCoordinate riderLocation = PlaceCoordinate(lat: lat, lng: lng);

        final icon =
            await BitmapDescriptorHelper.getBitmapDescriptorFromSvgAsset(
                "assets/svg/motorcycle.svg");
        final Marker riderLocationMarker = Marker(
            markerId: MarkerId('rider_location_marker'),
            position: LatLng(lat, lng), // Destination address location
            icon: icon);

        Map<MarkerId, Marker> markers = {};

        markers[MarkerId('rider_location_marker')] = riderLocationMarker;

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
            emit(
                state.copyWith(deliveryStatus: DeliveryStatus.deliveryOnGoing));

            add(SetDrawerHeight(minDrawerHeight: 180, maxDrawerHeight: 0.7.sh));
          }
        }
      } catch (e) {
        print(e);
      }
    });

    on<CheckForActiveRequest>(
      (event, emit) async {
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
            if (data['status'] == 'accepted' ||
                data['status'] == 'outForDelivery') {
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
      },
    );

    on<SetPanelControlStatus>(
      (event, emit) => emit(state.copyWith(panelControlStatus: event.status)),
    );

    on<SetNewMessage>(
      (event, emit) {
        emit(state.copyWith(message: event.value));
      },
    );

    on<IncomingMessage>(
      (event, emit) async {
        final chatMessages = [...state.chatMessages];

        final newMessage = Message.fromJson(event.data);
        chatMessages.add(newMessage);

        emit(state.copyWith(
            chatMessages: chatMessages, chatStatus: ChatStatus.newMessage));
      },
    );

    on<MessageRider>((event, emit) async {
      try {
        final User? user = auth.currentUser;
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final String? activeRequest = prefs.getString('activeRequest');

        // print('${state.deliveryData!.code}');

        final messageData = {
          'requestId': activeRequest,
          'senderId': user!.uid,
          'message': event.message,
          'timeStamp': '${DateTime.now()}'
        };

        await MessagingServer().sendMessage(
            data: {
              "type": "message",
              "data": """{
                "requestId": "$activeRequest'",
                "senderId": "${user.uid}",
                "message": "${event.message}",
                "timeStamp": "${DateTime.now()}"
              }"""
            },
            code: state.deliveryData!.code,
            message: event.message,
            title: user.displayName!.split(' ').first.trim());

        add(IncomingMessage(data: messageData));

        ChatsHelper().storeChat(messageData);
      } catch (e) {
        print('Sending messsage failed');
        print(e);
      }
    });

    on<LoadChatMessages>(
      (event, emit) async {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final String? activeRequest = prefs.getString('activeRequest');
        final directory = await getApplicationDocumentsDirectory();
        final chats = File('${directory.path}/$activeRequest.json');

        if (await chats.exists()) {
          print('Loading chats');
          final contents = await chats.readAsString();
          // print(contents);
          final jsonData = await jsonDecode(contents) as List;

          final messagesList =
              jsonData.map((e) => Message.fromJson(e)).toList();
          emit(state.copyWith(
              chatMessages: messagesList, chatStatus: ChatStatus.newMessage));
        }
      },
    );

    on<RateRider>(
      (event, emit) async {
        try {
          if (state.lastHistoryId != null) {
            await db.collection('history').doc(state.lastHistoryId).update(
                {'riderRating': event.rating, 'updatedAt': DateTime.now()});
          }
        } catch (e) {
          print(e);
        }
      },
    );
    on<DeleteCompletedDelivery>(
      (event, emit) async {
        try {
          User user = auth.currentUser!;
          final documentReference =
              db.collection('deliveryRequests').doc(user.uid);

          await documentReference.delete();
        } catch (e) {
          print(e);
        }
      },
    );
  }
}
