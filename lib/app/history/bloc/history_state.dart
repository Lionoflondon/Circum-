part of 'history_bloc.dart';

class HistoryState {
  List<DispatchRequest> ridesHistory;
  HistoryState({this.ridesHistory = const []});

  HistoryState copyWith({List<DispatchRequest>? ridesHistory}) {
    return HistoryState(ridesHistory: ridesHistory ?? this.ridesHistory);
  }
}
