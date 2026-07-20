import 'package:bloc/bloc.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../helper/chats_help.dart';
import '../../send_package/models/message.m.dart';

part 'support_event.dart';
part 'support_state.dart';

class SupportBloc extends Bloc<SupportEvent, SupportState> {
  SupportBloc() : super(SupportState()) {
    FirebaseAuth auth = FirebaseAuth.instance;
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    on<SupportEvent>((event, emit) {
      // TODO: implement event handler
    });

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
          final User? user = auth.currentUser;
          String msg = event.message;

          emit(state.copyWith(message: ''));
          final messageData = {
            "requestId": "support",
            'senderId': user!.uid,
            'message': msg,
            'timeStamp': '${DateTime.now()}'
          };

          await functions.httpsCallable('getOrCreateSupportConversation').call({
            'topic': 'support',
            'title': 'Circum Support',
            'initialMessage': msg,
            'participantRole': 'sender',
          });

          add(IncomingSupportMessage(data: messageData));

          ChatsHelper().storeChat(messageData);
        } catch (e) {}
      },
    );

    on<LoadSupportChatMessages>(
      (event, emit) async {
        final jsonData = await ChatsHelper().loadChat('support');
        if (jsonData.isNotEmpty) {
          final messagesList =
              jsonData.map((e) => Message.fromJson(e)).toList();
          emit(state.copyWith(
              chatMessages: messagesList, chatStatus: ChatStatus.newMessage));
        }
      },
    );
  }
}
