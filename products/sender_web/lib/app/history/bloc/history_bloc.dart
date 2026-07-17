import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../send_package/models/dispatch_request.m..dart';

part 'history_event.dart';
part 'history_state.dart';

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc() : super(HistoryState()) {
    FirebaseAuth auth = FirebaseAuth.instance;
    FirebaseFirestore db = FirebaseFirestore.instance;
    on<HistoryEvent>((event, emit) {
      // TODO: implement event handler
    });

    on<FetchHistory>(((event, emit) async {
      try {
        User? user = auth.currentUser;
        final documentReference = db
            .collection('history')
            .where('userId', isEqualTo: user!.uid)
            .orderBy('createdAt', descending: event.descending);
        ;

        final docResponse = await documentReference.get();

        List<DispatchRequest> ridesHistory = [];

        for (final doc in docResponse.docs) {
          final data = doc.data();
          final request = DispatchRequest.fromJson(data);

          ridesHistory.add(request);
        }

        emit(state.copyWith(ridesHistory: ridesHistory));
      } catch (e) {
        print(e);
      }
    }));
  }
}
