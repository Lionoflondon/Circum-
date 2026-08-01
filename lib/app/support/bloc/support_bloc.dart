import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../send_package/models/message.m.dart';

part 'support_event.dart';
part 'support_state.dart';

class SupportBloc extends Bloc<SupportEvent, SupportState> {
  SupportBloc() : super(SupportState()) {
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');

    on<SetNewSupportMessage>(
      (event, emit) {
        emit(state.copyWith(message: event.value));
      },
    );

    on<IncomingSupportMessage>(
      (event, emit) async {
        final chatMessages = [...state.chatMessages];

        final newMessage = Message.fromJson(event.data);
        chatMessages.add(newMessage);

        emit(state.copyWith(
            chatMessages: chatMessages, chatStatus: ChatStatus.newMessage));
      },
    );

    on<MessageSupport>(
      (event, emit) async {
        try {
          final msg = event.message;

          emit(state.copyWith(message: ''));
          await functions.httpsCallable('getOrCreateSupportConversation').call({
            'topic': 'support',
            'title': 'Circum Support',
            'initialMessage': msg,
            'participantRole': 'sender',
          });
        } catch (e) {
          emit(state.copyWith(message: event.message));
        }
      },
    );

    on<LoadSupportChatMessages>(
      (event, emit) async {},
    );
  }
}
