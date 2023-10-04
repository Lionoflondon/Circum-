part of 'navbar_bloc.dart';

@immutable
abstract class NavbarEvent {}

class ChangeTabIndex extends NavbarEvent {
  final int index;
  ChangeTabIndex({required this.index});
}
