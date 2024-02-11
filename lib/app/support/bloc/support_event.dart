part of 'support_bloc.dart';

abstract class SupportEvent {}

class MessageSupport extends SupportEvent {
  final String message;
  MessageSupport({required this.message});
}

class SetNewSupportMessage extends SupportEvent {
  final String value;
  SetNewSupportMessage({required this.value});
}

class IncomingSupportMessage extends SupportEvent {
  final dynamic data;
  IncomingSupportMessage({required this.data});
}

class LoadSupportChatMessages extends SupportEvent {}
