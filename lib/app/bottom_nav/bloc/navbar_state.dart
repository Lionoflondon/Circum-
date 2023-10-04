part of 'navbar_bloc.dart';

class NavbarState {
  final int currentNavIndex;
  NavbarState({this.currentNavIndex = 0});

  NavbarState copyWith({int? currentNavIndex}) {
    return NavbarState(
        currentNavIndex: currentNavIndex ?? this.currentNavIndex);
  }
}
