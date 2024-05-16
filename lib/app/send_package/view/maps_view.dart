import 'dart:async';

import 'package:circum/app/authentication/bloc/auth_bloc.dart';
import 'package:circum/app/send_package/view/ratings.dart';
import 'package:circum/utils/theme/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../bloc/send_package_bloc.dart';

class MapsView extends StatefulWidget {
  const MapsView({Key? key}) : super(key: key);

  @override
  State<MapsView> createState() => _MapsViewState();
}

class _MapsViewState extends State<MapsView> {
  GlobalKey mapKey = GlobalKey();

  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(0, 0),
    zoom: 0,
  );

  Future<void> setMapFitToTour(Set<Polyline> p) async {
    double minLat = p.first.points.first.latitude;
    double minLong = p.first.points.first.longitude;
    double maxLat = p.first.points.first.latitude;
    double maxLong = p.first.points.first.longitude;
    p.forEach((poly) {
      poly.points.forEach((point) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLong) minLong = point.longitude;
        if (point.longitude > maxLong) maxLong = point.longitude;
      });
    });

    final GoogleMapController mapController = await _controller.future;

    await mapController.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
            southwest: LatLng(minLat, minLong),
            northeast: LatLng(maxLat, maxLong)),
        70));
  }

  void changeCameraPositio(CameraPosition cameraPosition) async {
    final GoogleMapController mapController = await _controller.future;
    await mapController
        .animateCamera(CameraUpdate.newCameraPosition(cameraPosition));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      if (state.mapCameraStatus == MapCameraStatus.initialized &&
          context.read<AuthBloc>().state.locationData != null &&
          _controller.isCompleted == true) {
        changeCameraPositio(CameraPosition(
          target: LatLng(context.read<AuthBloc>().state.locationData!.latitude,
              context.read<AuthBloc>().state.locationData!.longitude),
          zoom: 15,
        ));

        context.read<SendPackageBloc>().add(
            SetMapCameraStatus(status: MapCameraStatus.showingDeviceLocation));
      }

      // Show Rider Location On The Map
      if (state.mapCameraStatus == MapCameraStatus.showRiderLocation &&
          state.riderLocation != null) {
        changeCameraPositio(CameraPosition(
          target: LatLng(state.riderLocation!.lat, state.riderLocation!.lng),
          zoom: 15,
        ));

        context.read<SendPackageBloc>().add(
            SetMapCameraStatus(status: MapCameraStatus.showingRiderLocation));
      }

      if (state.sourceAndDestinationStatus ==
              SourceAndDestinationStatus.selected &&
          state.mapCameraStatus !=
              MapCameraStatus.showingSourceAndDestinationLocations) {
        setMapFitToTour(Set<Polyline>.of(state.polylines));
        context.read<SendPackageBloc>().add(SetMapCameraStatus(
            status: MapCameraStatus.showingSourceAndDestinationLocations));
      }
      if (context.read<AuthBloc>().state.appLocationStatus ==
          AppLocationStatus.available) {
        // print('here');
      }

      return Stack(
        children: [
          GoogleMap(
            // key: mapKey,
            mapType: MapType.normal,
            initialCameraPosition: _initialCameraPosition,
            cameraTargetBounds: CameraTargetBounds.unbounded,
            onMapCreated: (GoogleMapController controller) async {
              print('initializing map');
              print('controller completed: ${_controller.isCompleted}');
              _controller.complete(controller);
            },
            markers: Set<Marker>.of(state.markers.values),
            polylines: Set<Polyline>.of(state.polylines),
          ),
          if (state.deliveryStatus != DeliveryStatus.inital &&
              state.deliveryStatus != DeliveryStatus.deliveryConfirmed &&
              state.deliveryStatus != DeliveryStatus.deliveryOnGoing)
            Padding(
                padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top, left: 24),
                child: TextButton(
                    style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        fixedSize: const Size(60, 60),
                        minimumSize: const Size(60, 60),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            side: const BorderSide(
                                color: AppColors.primary, width: 2),
                            borderRadius: BorderRadius.circular(100))),
                    onPressed: () {
                      context.read<SendPackageBloc>().add(BackButtonPressed());
                    },
                    child: const Icon(
                      Icons.arrow_back_ios_rounded,
                      color: AppColors.primary,
                    )))
        ],
      );
    });
  }
}
