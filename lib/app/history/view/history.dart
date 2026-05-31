import 'package:currency_symbols/currency_symbols.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../helper/format_date.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/history_bloc.dart';
import 'history_details.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({Key? key}) : super(key: key);

  @override
  HistoryViewState createState() => HistoryViewState();
}

class HistoryViewState extends State<HistoryView> {
  @override
  void initState() {
    super.initState();
    context.read<HistoryBloc>().add(FetchHistory(descending: true));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [appBar(context), filter(), history()],
      ),
    );
  }

  Widget appBar(context) {
    return Container(
      margin: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 20, left: 24),
      width: double.maxFinite,
      child: AppText.text('History',
          color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
    );
  }

  Widget filter() {
    return BlocBuilder<HistoryBloc, HistoryState>(builder: (context, state) {
      if (state.ridesHistory.isEmpty) {
        return Container();
      }
      return Container(
          width: 160,
          margin: const EdgeInsets.only(left: 24, top: 20),
          child: DropdownButtonFormField(
              elevation: 0,
              iconSize: 0.0,
              dropdownColor: AppColors.input,
              style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Helvetica',
                  fontWeight: FontWeight.w500,
                  // fontSize: 15,
                  decoration: TextDecoration.none),
              decoration: const InputDecoration(
                // isCollapsed: true,
                alignLabelWithHint: true,
                // icon:
                //     Visibility(visible: false, child: Icon(Icons.arrow_downward)),
                hintMaxLines: 1,
                suffixIcon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                ),

                constraints: BoxConstraints(
                    maxHeight: 40, minHeight: 40, minWidth: 80, maxWidth: 120),
                filled: true,
                fillColor: AppColors.input,
                contentPadding: EdgeInsets.only(left: 16, top: 0),

                hintText: 'Filter',
                hintStyle: TextStyle(
                    fontFamily: 'Helvetica', color: Colors.white, fontSize: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(0)),
                  borderSide: BorderSide(color: Colors.transparent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(0)),
                  borderSide: BorderSide(color: Colors.black),
                ),
              ),
              items: ['Ascending', 'Descending']
                  .map((e) => DropdownMenuItem(
                      value: e, child: AppText.text(e, fontSize: 16)))
                  .toList(),
              onChanged: (data) {
                context.read<HistoryBloc>().add(FetchHistory(
                    descending: data == 'Descending' ? true : false));
              }));
    });
  }

  Widget history() {
    return BlocBuilder<HistoryBloc, HistoryState>(builder: (context, state) {
      if (state.ridesHistory.isEmpty) {
        return Expanded(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: MediaQuery.of(context).size.width,
            ),
            SvgPicture.asset(
              'assets/svg/delivery_history.svg',
              color: const Color.fromARGB(255, 171, 171, 171),
              width: 60,
            ),
            AppText.text('Your delivery history will appear here.',
                color: const Color(0xFFBFBFBF))
          ],
        ));
      }
      return Expanded(
          child: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                  padding: const EdgeInsets.only(top: 24, bottom: 24),
                  shrinkWrap: true,
                  // physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (contxt, index) {
                    return TextButton(
                        // borderSide: BorderSide.none,
                        // backgroundColor: AppColors.secondary,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText.text(
                                    '${state.ridesHistory[index].dropoffData.address}',
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    AppText.text(
                                        '${cSymbol(state.ridesHistory[index].currency)}${state.ridesHistory[index].price}',
                                        color: AppColors.textGrey),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.circle,
                                      color: AppColors.textGrey,
                                      size: 6,
                                    ),
                                    const SizedBox(width: 8),
                                    AppText.text(
                                        formatTimestamp(state
                                            .ridesHistory[index].createdAt!),
                                        fontSize: 12,
                                        color: AppColors.textGrey)
                                  ],
                                )
                              ],
                            ),
                            Icon(
                              Icons.keyboard_arrow_right_rounded,
                              color: Colors.white.withOpacity(0.15),
                            )
                          ],
                        ),
                        onPressed: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => HistoryDetailsView(
                                        data: state.ridesHistory[index],
                                      )));
                        });
                  },
                  separatorBuilder: (_, i) => Divider(
                      height: 5,
                      thickness: 1,
                      color: Colors.white.withOpacity(0.15)),
                  itemCount: state.ridesHistory.length)));
    });
  }
}
