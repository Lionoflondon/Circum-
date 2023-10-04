import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../utils/theme/theme.dart';
import '../bloc/history_bloc.dart';

class HistoryView extends StatelessWidget {
  const HistoryView({Key? key}) : super(key: key);

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
    return Container(
        width: 160,
        margin: const EdgeInsets.only(left: 24, top: 20),
        child: DropdownButtonFormField(
            elevation: 0,
            dropdownColor: AppColors.input,
            style: const TextStyle(
                color: Colors.white,
                fontFamily: 'OpenSans',
                fontWeight: FontWeight.w500,
                fontSize: 15,
                decoration: TextDecoration.none),
            decoration: const InputDecoration(
              filled: true,
              fillColor: AppColors.input,
              hintText: 'Date Filter',
              hintStyle: TextStyle(
                fontFamily: 'OpenSans',
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: Colors.transparent),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: Colors.black),
              ),
            ),
            items: ['Last week', 'Last month']
                .map((e) => DropdownMenuItem(value: e, child: AppText.text(e)))
                .toList(),
            onChanged: (data) {}));
  }

  Widget history() {
    return BlocBuilder<HistoryBloc, HistoryState>(builder: (context, state) {
      return SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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
                          children: [
                            AppText.text('Placeholder Address',
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600),
                            AppText.text('Placeholder subaddress',
                                color: AppColors.textGrey)
                          ],
                        ),
                        Icon(
                          Icons.keyboard_arrow_right_rounded,
                          color: Colors.white.withOpacity(0.15),
                        )
                      ],
                    ),
                    onPressed: () {});
              },
              separatorBuilder: (_, i) => Divider(
                  height: 5,
                  thickness: 1,
                  color: Colors.white.withOpacity(0.15)),
              itemCount: 3));
    });
  }
}
