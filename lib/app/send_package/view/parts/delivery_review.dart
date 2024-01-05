part of '../home.dart';

Widget deliveryReview() {
  return Column(
    children: [
      const SizedBox(height: 20),
      selectedAddresses(),
      const SizedBox(height: 38),
      deliveryCost(),
      const SizedBox(height: 66),
      reviewButton(),
      const SizedBox(height: 32),
    ],
  );
}

Widget selectedAddresses() {
  return BlocBuilder<SendPackageBloc, SendPackageState>(
      builder: (context, state) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            const SizedBox(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.text(state.pickupLocation!,
                    fontSize: 16, fontWeight: FontWeight.w600),
                AppText.text(state.pickupLocationSubAddress!,
                    fontSize: 12, color: const Color(0xFFC9D2D7)),
                const SizedBox(height: 12),
                AppText.text(state.destinationLocation!,
                    fontSize: 16, fontWeight: FontWeight.w600),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: AppText.text(state.destinationLocationSubAddress!,
                          fontSize: 12, color: const Color(0xFFC9D2D7)),
                    ),
                    const SizedBox(width: 2),
                    AppText.text(
                        state.distance != null
                            ? '${state.distance}km away'
                            : '',
                        fontSize: 12,
                        color: const Color(0xFFC9D2D7)),
                  ],
                )
              ],
            )),
          ],
        ));
  });
}

Widget deliveryCost() {
  return BlocBuilder<SendPackageBloc, SendPackageState>(
      builder: ((context, state) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Image(
                height: 52,
                width: 52,
                image: AssetImage('assets/images/bike.png')),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                state.price == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Shimmer.fromColors(
                            baseColor: Color.fromARGB(255, 121, 121, 121),
                            highlightColor: Color.fromARGB(255, 176, 176, 176),
                            child: Container(
                              height: 10,
                              width: 50,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Shimmer.fromColors(
                              baseColor: Color.fromARGB(255, 121, 121, 121),
                              highlightColor:
                                  Color.fromARGB(255, 176, 176, 176),
                              child: Container(
                                height: 10,
                                width: 70,
                                color: Colors.white,
                              ))
                        ],
                      )
                    : Column(
                        children: [
                          AppText.text('£${state.price}',
                              fontSize: 24, fontWeight: FontWeight.w600),
                          AppText.text('Delivery price',
                              fontSize: 12, color: const Color(0xFFC9D2D7)),
                        ],
                      )
              ],
            )
          ],
        ));
  }));
}

Widget reviewButton() {
  return BlocBuilder<SendPackageBloc, SendPackageState>(
      builder: ((context, state) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: AppButton.button(
          widget: Center(
              child: AppText.text('Review delivery',
                  fontSize: 16, fontWeight: FontWeight.bold)),
          onPressed: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => DeliveryReviewExpandedView()));
          }),
    );
  }));
}
