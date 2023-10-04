part of 'home_bloc.dart';

class HomeState {
  final List ongoingRequests;
  const HomeState({this.ongoingRequests = const []});

  HomeState copyWith({List? ongoingRequests}) {
    return HomeState(ongoingRequests: ongoingRequests ?? this.ongoingRequests);
  }
}
