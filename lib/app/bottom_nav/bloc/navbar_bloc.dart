import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

part 'navbar_event.dart';
part 'navbar_state.dart';

class NavbarBloc extends Bloc<NavbarEvent, NavbarState> {
  NavbarBloc() : super(NavbarState()) {
    on<NavbarEvent>((event, emit) {
      if (event is ChangeTabIndex) {
        emit(state.copyWith(currentNavIndex: event.index));
      }
    });
  }
}
