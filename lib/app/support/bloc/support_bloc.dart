import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../send_package/models/message.m.dart';

part 'support_event.dart';
part 'support_state.dart';

class SupportBloc extends Bloc<SupportEvent, SupportState> {
  SupportBloc() : super(SupportState()) {
    FirebaseAuth auth = FirebaseAuth.instance;
    FirebaseFirestore db = FirebaseFirestore.instance;
    FirebaseFunctions functions = FirebaseFunctions.instance;
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
          if (user == null) return;
          final chatId = state.chatId ?? await _supportChatId(functions);

          emit(state.copyWith(message: ''));
          await functions.httpsCallable('sendCircumMessage').call({
            'chatId': chatId,
            'message': event.message,
            'messageType': 'text',
          });
          final messages = await _loadMessages(db, chatId);
          emit(state.copyWith(
            chatId: chatId,
            chatMessages: messages,
            chatStatus: ChatStatus.newMessage,
          ));
        } catch (e) {
          // The support surface remains available; failures are shown by the UI
          // staying on the current composer state.
        }
      },
    );

    on<LoadSupportChatMessages>(
      (event, emit) async {
        try {
          final chatId = state.chatId ?? await _supportChatId(functions);
          final messages = await _loadMessages(db, chatId);
          emit(state.copyWith(
            chatId: chatId,
            chatMessages: messages,
            chatStatus:
                messages.isEmpty ? ChatStatus.initial : ChatStatus.newMessage,
          ));
        } catch (_) {}
      },
    );
  }

  Future<String> _supportChatId(FirebaseFunctions functions) async {
    final result =
        await functions.httpsCallable('getOrCreateSupportConversation').call({
      'topic': 'support',
      'title': 'Circum Support',
      'participantRole': 'sender',
    });
    final data = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : const <String, dynamic>{};
    final chatId = '${data['chatId'] ?? ''}'.trim();
    if (chatId.isEmpty) throw StateError('Support conversation unavailable.');
    return chatId;
  }

  Future<List<Message>> _loadMessages(
    FirebaseFirestore db,
    String chatId,
  ) async {
    final snapshot = await db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt')
        .limit(100)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      final createdAt = data['createdAt'];
      return Message.fromJson({
        'requestId': chatId,
        'senderId': data['senderId'] ?? '',
        'message': data['messageText'] ?? data['message'] ?? '',
        'timeStamp': createdAt is Timestamp
            ? createdAt.toDate().toIso8601String()
            : '${data['timeStamp'] ?? ''}',
      });
    }).toList(growable: false);
  }
}
