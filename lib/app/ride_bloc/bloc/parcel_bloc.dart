import 'package:flutter_bloc/flutter_bloc.dart';

part 'parcel_event.dart';
part 'parcel_state.dart';

class ParcelBloc extends Bloc<ParcelEvent, ParcelState> {
  ParcelBloc() : super(ParcelState()) {
    on<ParcelEvent>((event, emit) {});

    on<SetParcelStatus>(
      (event, emit) {
        emit(state.copyWith(parcelStatus: event.status));
      },
    );
  }
}
