part of 'parcel_bloc.dart';

class ParcelEvent {}

class SetParcelStatus extends ParcelEvent {
  ParcelStatus status;
  SetParcelStatus({required this.status});
}
