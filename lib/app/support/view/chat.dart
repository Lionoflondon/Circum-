import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../utils/theme/theme.dart';
import '../../authentication/bloc/auth_bloc.dart';
import '../bloc/support_bloc.dart';

class ChatPageView extends StatefulWidget {
  const ChatPageView({Key? key}) : super(key: key);

  @override
  State<ChatPageView> createState() => _ChatPageViewState();
}

class _ChatPageViewState extends State<ChatPageView> {
  TextEditingController textInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    // Scroll to the bottom initially
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SupportBloc, SupportState>(
      listener: (context, state) {
        // Scroll to the bottom when a new message is received
        // if (state.status == ChatStatus.newMessage) {
        //   _scrollToBottom();
        // }
      },
      child: Scaffold(
          backgroundColor: AppColors.secondary,
          // resizeToAvoidBottomInset: false,
          body: Column(
            children: [chatHeader(), Expanded(child: messages()), chatFooter()],
          )),
    );
  }

  Widget chatHeader() {
    return BlocBuilder<SupportBloc, SupportState>(builder: (context, state) {
      return Container(
        color: AppColors.secondary,
        padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top, bottom: 10),
        child: Row(
          children: [
            IconButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.arrow_back, color: Colors.white)),
            const SizedBox(width: 10),
            const SizedBox(width: 10),
            Column(
              children: [
                AppText.text('Live Chat',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)
              ],
            )
          ],
        ),
      );
    });
  }

  Widget messages() {
    return BlocBuilder<SupportBloc, SupportState>(builder: (context, state) {
      return ListView.separated(
          physics: const BouncingScrollPhysics(),
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20)
              .copyWith(bottom: 40),
          itemBuilder: (_, i) {
            // print(state.chatRoomMessages[i]);
            if (i % 2 == 0) {
              return Container(
                  child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.6,
                        ),
                        decoration: const BoxDecoration(
                            color: AppColors.input,
                            borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                                bottomRight: Radius.circular(10))),
                        padding: const EdgeInsets.all(14),
                        child: const Text(
                            'Hi bvcgfdz kjhbfgdxzfgcvh hvftesdrtfy iugyftdr',
                            style: TextStyle(color: Colors.white)),
                      )));
            }
            if (i % 2 != 0) {
              return Container(
                  child: Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        // width: MediaQuery.of(context).size.width * 0.6,
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.6,
                        ),
                        decoration: const BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                                bottomLeft: Radius.circular(10))),
                        padding: const EdgeInsets.all(14),
                        child: const Text('Hello',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white)),
                      )));
            }
            return Container();
          },
          separatorBuilder: (_, i) => const SizedBox(
                height: 10,
              ),
          itemCount: 0);
    });
  }

  Widget chatFooter() {
    return BlocBuilder<SupportBloc, SupportState>(builder: (context, state) {
      return Container(
        // color: Colors,
        decoration: const BoxDecoration(
            // color: Colors.white,
            ),
        padding:
            const EdgeInsets.only(top: 10, bottom: 10, left: 24, right: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: TextField(
              controller: textInputController,
              minLines: 1,
              maxLines: 4,
              style:
                  const TextStyle(fontFamily: 'OpenSans', color: Colors.white),
              decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.input,
                  hintText: 'Enter your message',
                  hintStyle: TextStyle(
                      color: Colors.grey[600], fontFamily: 'OpenSans'),
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none),
              onChanged: (value) {
                // context.read<SupportBloc>().add(SetNewMessage(value: value));
              },
            )),
            const SizedBox(width: 10),
            AppButton.button(
                onPressed: () {},
                widget: SvgPicture.asset('assets/svg/send.svg'))
          ],
        ),
      );
    });
  }
}
