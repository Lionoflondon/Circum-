part of 'history_bloc.dart';

abstract class HistoryEvent {
  const HistoryEvent();
}

class FetchHistory extends HistoryEvent {
  bool descending;
  FetchHistory({required this.descending});
}
