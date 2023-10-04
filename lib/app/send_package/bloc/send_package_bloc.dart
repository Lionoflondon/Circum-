import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';

import '../repo/place_api.dart';

part 'send_package_event.dart';
part 'send_package_state.dart';

class SendPackageBloc extends Bloc<SendPackageEvent, SendPackageState> {
  SendPackageBloc() : super(SendPackageState()) {
    on<SendPackageEvent>((event, emit) {
      // TODO: implement event handler
    });

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

        emit(state.copyWith(pickupCoordinate: coordinate));
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
        emit(state.copyWith(desinationCoordinate: coordinate));

        if (state.pickupCoordinate != null) {
          add(CalculateDistance());
        }
      } catch (e) {
        print(e);
      }
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

        print(distanceInKilometres);
      } catch (e) {
        print(e);
      }
    });
  }
}
