part of 'support_bloc.dart';

enum ChatStatus { initial, newMessage }

class SupportState {
  String? message;
  String? chatId;
  List<Message> chatMessages;
  ChatStatus chatStatus;
  SupportState(
      {this.message,
      this.chatId,
      this.chatMessages = const [],
      this.chatStatus = ChatStatus.initial});

  SupportState copyWith(
      {String? message,
      String? chatId,
      List<Message>? chatMessages,
      ChatStatus? chatStatus}) {
    return SupportState(
        message: message ?? this.message,
        chatId: chatId ?? this.chatId,
        chatMessages: chatMessages ?? this.chatMessages,
        chatStatus: chatStatus ?? this.chatStatus);
  }
}
