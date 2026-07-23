import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../sender_mobile/design_system/sender_design_system.dart';

/// Canonical delivery conversation. Messages are persisted by the
/// communication callable and remain visible after the delivery closes.
class RideChatPageView extends StatefulWidget {
  final String? chatId;
  final String title;
  final String? initialMessage;
  final bool supportConversation;

  const RideChatPageView({
    super.key,
    this.chatId,
    this.title = 'Delivery chat',
    this.initialMessage,
    this.supportConversation = false,
  });

  @override
  State<RideChatPageView> createState() => _RideChatPageViewState();
}

class _RideChatPageViewState extends State<RideChatPageView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _chatId;
  String? _markedReadChatId;
  String? _supportError;
  bool _sending = false;
  Timer? _typingDebounce;

  @override
  void initState() {
    super.initState();
    final initialMessage = widget.initialMessage?.trim();
    if (initialMessage != null && initialMessage.isNotEmpty) {
      _input.text = initialMessage;
      _input.selection = TextSelection.collapsed(offset: initialMessage.length);
    }
    _resolveChatId();
  }

  Future<void> _resolveChatId() async {
    if (widget.supportConversation) {
      await _resolveSupportChatId();
      return;
    }
    if (widget.chatId?.trim().isNotEmpty == true) {
      setState(() => _chatId = widget.chatId!.trim());
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _chatId = preferences.getString('activeRequest'));
    }
  }

  Future<void> _resolveSupportChatId() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() => _supportError = 'Sign in to contact Circum Support.');
        }
        return;
      }
      final result = await FirebaseFunctions.instance
          .httpsCallable('getOrCreateSupportConversation')
          .call({
            'topic': 'wallet_support',
            'title': 'Circum Support',
            'participantRole': 'sender',
          });
      final data = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : const <String, dynamic>{};
      final chatId = '${data['chatId'] ?? ''}'.trim();
      if (chatId.isEmpty) {
        throw StateError('Support conversation was not created.');
      }
      if (mounted) setState(() => _chatId = chatId);
    } catch (_) {
      if (mounted) {
        setState(() {
          _supportError = 'Circum Support is unavailable. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _setTyping(bool typing) async {
    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) return;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('setConversationTyping')
          .call({'chatId': chatId, 'typing': typing});
    } catch (_) {
      // Typing is deliberately best-effort and never blocks messaging.
    }
  }

  Future<void> _markConversationRead(String chatId) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('markConversationRead')
          .call({'chatId': chatId});
    } catch (_) {
      // The visible stream remains available when acknowledgement is offline.
    }
  }

  Future<void> _send(bool readOnly) async {
    final message = _input.text.trim();
    final chatId = _chatId;
    if (message.isEmpty || chatId == null || readOnly || _sending) return;
    setState(() => _sending = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('sendCircumMessage').call({
        'chatId': chatId,
        'message': message,
        'messageType': 'text',
      });
      _input.clear();
      await _setTyping(false);
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Your message could not be sent.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatId = _chatId;
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppTokens.background,
        foregroundColor: AppTokens.text,
        elevation: 0,
      ),
      body: _supportError != null
          ? AppEmptyState(
              icon: Icons.support_agent_outlined,
              title: 'Support is unavailable',
              body: _supportError!,
              actionLabel: 'Back',
              onAction: () => Navigator.of(context).pop(),
            )
          : chatId == null
          ? const _ChatLoadingState(
              title: 'Opening conversation',
              body: 'Preparing your secure Circum chat.',
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
                  .snapshots(),
              builder: (context, chatSnapshot) {
                if (chatSnapshot.hasError) {
                  return _UnavailableChat(
                    onBack: () => Navigator.of(context).pop(),
                  );
                }
                if (!chatSnapshot.hasData) {
                  return const _ChatLoadingState(
                    title: 'Loading messages',
                    body: 'Keeping the conversation up to date.',
                  );
                }
                if (!chatSnapshot.data!.exists) {
                  return _UnavailableChat(
                    onBack: () => Navigator.of(context).pop(),
                  );
                }
                final chat = chatSnapshot.data!.data()!;
                if (_markedReadChatId != chatId) {
                  _markedReadChatId = chatId;
                  unawaited(_markConversationRead(chatId));
                }
                final readOnly = chat['readOnly'] == true;
                final typing = Map<String, dynamic>.from(
                  chat['typing'] as Map? ?? const {},
                );
                final currentId = FirebaseAuth.instance.currentUser?.uid;
                final typingOther = typing.entries.any(
                  (entry) =>
                      entry.key != currentId &&
                      entry.value is num &&
                      (entry.value as num).toInt() >
                          DateTime.now().millisecondsSinceEpoch,
                );
                return Column(
                  children: [
                    if (readOnly)
                      const _ChatNotice(
                        'Delivery completed. This conversation is now read-only.',
                      ),
                    if (typingOther) const _ChatNotice('Rider is typing...'),
                    Expanded(
                      child: _MessageStream(
                        chatId: chatId,
                        scrollController: _scroll,
                      ),
                    ),
                    _Composer(
                      controller: _input,
                      hintText: widget.supportConversation
                          ? 'Message Circum Support'
                          : 'Message your rider',
                      readOnly: readOnly,
                      sending: _sending,
                      role:
                          '${Map<String, dynamic>.from(chat['participantRoles'] as Map? ?? const {})[currentId] ?? 'sender'}',
                      onChanged: (_) {
                        _setTyping(true);
                        _typingDebounce?.cancel();
                        _typingDebounce = Timer(
                          const Duration(seconds: 4),
                          () => _setTyping(false),
                        );
                      },
                      onQuickReply: (reply) {
                        _input.text = reply;
                        _input.selection = TextSelection.collapsed(
                          offset: reply.length,
                        );
                      },
                      onSend: () => _send(readOnly),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _MessageStream extends StatelessWidget {
  final String chatId;
  final ScrollController scrollController;

  const _MessageStream({required this.chatId, required this.scrollController});

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .limitToLast(100)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const AppEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Messages are unavailable',
          body: 'Check your connection and try again.',
        );
      }
      if (!snapshot.hasData) {
        return const _ChatLoadingState(
          title: 'Loading messages',
          body: 'Your chat history will appear here.',
        );
      }
      final messages = snapshot.data!.docs;
      if (messages.isEmpty) {
        return const AppEmptyState(
          icon: Icons.forum_outlined,
          title: 'Chat is ready',
          body:
              'Message your rider once there is something you need to clarify.',
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: AppTokens.fast,
            curve: Curves.easeOut,
          );
        }
      });
      return ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.all(AppTokens.space16),
        itemCount: messages.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _MessageBubble(data: messages[index].data()),
      );
    },
  );
}

class _ChatLoadingState extends StatelessWidget {
  final String title;
  final String body;

  const _ChatLoadingState({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppGlassContainer(
        constraints: const BoxConstraints(maxWidth: 320),
        accent: AppTokens.primary,
        surfaceColor: AppTokens.midnight.withValues(alpha: .84),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: AppTokens.space16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppTokens.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppTokens.space8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTokens.mutedText,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MessageBubble({required this.data});

  @override
  Widget build(BuildContext context) {
    final mine = data['senderId'] == FirebaseAuth.instance.currentUser?.uid;
    final admin = '${data['senderRole'] ?? ''}' == 'admin';
    final message = '${data['messageText'] ?? data['message'] ?? ''}'.trim();
    final timestamp = data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).toDate()
        : null;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 310),
        child: AppGlassContainer(
          radius: AppTokens.radius16,
          accent: mine
              ? AppTokens.primary
              : admin
              ? AppTokens.success
              : null,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (admin)
                const AppStatusBadge(
                  label: 'Circum Support',
                  tone: AppStatusTone.success,
                ),
              if (admin) const SizedBox(height: 6),
              Text(message),
              if (timestamp != null) ...[
                const SizedBox(height: 5),
                Text(
                  '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTokens.mutedText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool readOnly;
  final bool sending;
  final String role;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onQuickReply;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.hintText,
    required this.readOnly,
    required this.sending,
    required this.role,
    required this.onChanged,
    required this.onQuickReply,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!readOnly)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickReplies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => ActionChip(
                label: Text(_quickReplies[index]),
                onPressed: () => onQuickReply(_quickReplies[index]),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !readOnly && !sending,
                  minLines: 1,
                  maxLines: 4,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText: readOnly
                        ? 'This conversation is closed'
                        : hintText,
                    filled: true,
                    fillColor: AppTokens.raisedPanel,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radius16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: readOnly || sending ? null : onSend,
                tooltip: 'Send message',
                icon: sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  List<String> get _quickReplies => role == 'rider'
      ? const [
          "I'm on my way.",
          "I've arrived.",
          'Please come outside.',
          'Running a few minutes late.',
          'Please confirm the pickup PIN.',
          'Thank you.',
        ]
      : const [
          "I'll be outside shortly.",
          'Please wait two minutes.',
          "I'm sending the recipient now.",
          'Please leave at reception.',
          "I'm running late.",
          'Thank you.',
        ];
}

class _ChatNotice extends StatelessWidget {
  final String text;
  const _ChatNotice(this.text);
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    color: AppTokens.primary.withValues(alpha: .12),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppTokens.mutedText),
    ),
  );
}

class _UnavailableChat extends StatelessWidget {
  final VoidCallback onBack;
  const _UnavailableChat({required this.onBack});
  @override
  Widget build(BuildContext context) => AppEmptyState(
    icon: Icons.lock_outline,
    title: 'Chat is not available yet',
    body:
        'Delivery chat becomes available once your rider has accepted the delivery.',
    actionLabel: 'Back',
    onAction: onBack,
  );
}
