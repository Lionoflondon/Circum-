part of 'support_bloc.dart';

enum ChatStatus { initial, newMessage }

class SupportState {
  String? message;
  List<Message> chatMessages;
  ChatStatus chatStatus;
  SupportState(
      {this.message,
      this.chatMessages = const [],
      this.chatStatus = ChatStatus.initial});

  SupportState copyWith(
      {String? message, List<Message>? chatMessages, ChatStatus? chatStatus}) {
    return SupportState(
        message: message ?? this.message,
        chatMessages: chatMessages ?? this.chatMessages,
        chatStatus: chatStatus ?? this.chatStatus);
  }
}
