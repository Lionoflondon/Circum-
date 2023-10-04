part of 'parcel_bloc.dart';

enum ParcelStatus { inactive, active, connecting, ended }

class ParcelState {
  ParcelStatus parcelStatus;
  ParcelState({this.parcelStatus = ParcelStatus.inactive});

  ParcelState copyWith({ParcelStatus? parcelStatus}) {
    return ParcelState(parcelStatus: parcelStatus ?? this.parcelStatus);
  }
}
