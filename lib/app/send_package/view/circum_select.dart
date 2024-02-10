import 'package:circum/app/authentication/bloc/auth_bloc.dart';
import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/utils/theme/text_field.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';

import '../../../utils/theme/theme.dart';

class CirccumSelectView extends StatefulWidget {
  const CirccumSelectView({Key? key}) : super(key: key);

  @override
  CirccumSelectViewState createState() => CirccumSelectViewState();
}

class CirccumSelectViewState extends State<CirccumSelectView> {
  TextEditingController sourceQueryController = TextEditingController();
  TextEditingController destinationQueryController = TextEditingController();
  late FocusNode sourceFocusNode;
  late FocusNode destinationFocusNode;

  @override
  void initState() {
    super.initState();
    sourceFocusNode = FocusNode();
    destinationFocusNode = FocusNode();
  }

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
    sourceFocusNode.dispose();
    destinationFocusNode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: AppColors.secondary,
        elevation: 0,
        title: AppText.text('Circum Select',
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
      ),
      body: SafeArea(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [comingSoon()],
      )),
    );
  }

  Widget comingSoon() {
    return Column(
      children: [
        SvgPicture.asset('assets/svg/global_plane.svg'),
        const SizedBox(height: 10),
        AppText.text('Comming soon', fontSize: 20),
        const SizedBox(height: 6),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: AppText.text(
                'Circum Select helps you send parcel to locations in other countries.',
                textAlign: TextAlign.center,
                color: Colors.white.withOpacity(0.7)))
      ],
    );
  }

  Widget addresses() {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Container(
                height: 85,
                child: Column(
                  children: [
                    Icon(
                      Icons.circle,
                      color: Color(0xFF2D89D4),
                      size: 10,
                    ),
                    Expanded(
                        child: DottedLine(
                      direction: Axis.vertical,
                      dashColor: Color(0xFF1F292E),
                    )),
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: Color(0xFF65C436),
                    ),
                  ],
                )),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
              children: [
                AppTextInput.input(
                    hintText: 'Choose pick up location',
                    focusNode: sourceFocusNode,
                    autofocus: true,
                    controller: sourceQueryController,
                    onChanged: (val) {
                      // context.read<SendPackageBloc>().add(SearchAPlaceEvent(
                      //     query: val,
                      //     lang: Localizations.localeOf(context).languageCode));
                    }),
                const SizedBox(height: 12),
                AppTextInput.input(
                    focusNode: destinationFocusNode,
                    controller: destinationQueryController,
                    hintText: 'Choose recipient’s location',
                    onChanged: (val) {
                      // context.read<SendPackageBloc>().add(SearchAPlaceEvent(
                      //     query: val,
                      //     lang: Localizations.localeOf(context).languageCode));
                    })
              ],
            ))
          ],
        ));
  }
}
