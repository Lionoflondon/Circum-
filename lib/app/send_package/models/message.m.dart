import 'package:equatable/equatable.dart';

class Message extends Equatable {
  final String requestId;
  final String senderId;
  final String message;
  final String timeStamp;
  const Message(
      {required this.requestId,
      required this.senderId,
      required this.message,
      required this.timeStamp});

  @override
  List<Object> get props => [
        {requestId},
        {senderId},
        {message},
        {timeStamp},
      ];

  static Message fromJson(dynamic json) {
    return Message(
      requestId: json['requestId'],
      senderId: json['senderId'],
      message: json['message'],
      timeStamp: json['timeStamp'],
    );
  }

  @override
  String toString() => '''Message { 
      requestId: $requestId, 
      senderId: $senderId,
      message: $message,
      timeStamp: $timeStamp,
      }
''';
}
