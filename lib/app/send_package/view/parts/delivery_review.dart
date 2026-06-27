part of '../home.dart';

Widget deliveryReview() {
  return Column(
    children: [
      const SizedBox(height: 20),
      selectedAddresses(),
      const SizedBox(height: 20),
      irisResultCard(),
      const SizedBox(height: 28),
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

Widget irisResultCard() {
  return BlocBuilder<SendPackageBloc, SendPackageState>(
      builder: (context, state) {
    final iris = state.irisResult;
    if (iris == null) return const SizedBox.shrink();

    final confidenceLabel = iris.confidenceScore < 0.65
        ? 'Low confidence'
        : iris.confidenceScore < 0.85
            ? 'Medium confidence'
            : 'Matched';
    final confidenceColor = iris.confidenceScore < 0.65
        ? const Color(0xFFE9B84C)
        : iris.confidenceScore < 0.85
            ? const Color(0xFF65B7F3)
            : const Color(0xFF65C436);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111B22),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: const Color(0xFF2D89D4).withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D89D4).withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppText.text('IRIS Estimate',
                    fontSize: 14, fontWeight: FontWeight.w700),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: confidenceColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: confidenceColor.withValues(alpha: 0.5)),
                  ),
                  child: AppText.text(confidenceLabel,
                      fontSize: 11,
                      color: confidenceColor,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppText.text(iris.matchedItemName,
                fontSize: 16, fontWeight: FontWeight.w700),
            const SizedBox(height: 8),
            AppText.text(
                '${iris.weightKg.toStringAsFixed(2)}kg · ${iris.weightBand} · ${iris.vehicleSuitability}',
                fontSize: 13,
                color: const Color(0xFFC9D2D7),
                fontWeight: FontWeight.w600),
            if (iris.vanguardRecommended) ...[
              const SizedBox(height: 10),
              AppText.text('Vanguard protection recommended',
                  fontSize: 12,
                  color: const Color(0xFF65B7F3),
                  fontWeight: FontWeight.w700),
            ],
            if (iris.confidenceScore < 0.85) ...[
              const SizedBox(height: 10),
              AppText.text(
                  'IRIS will use trusted history where available before payment. Rider verification still happens at pickup.',
                  fontSize: 12,
                  color: const Color(0xFFC9D2D7)),
            ],
            if (state.isIrisResolving) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: Color(0xFF2D89D4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppText.text('Finalising trusted IRIS estimate...',
                      fontSize: 12,
                      color: const Color(0xFFC9D2D7),
                      fontWeight: FontWeight.w600),
                ],
              ),
            ],
          ],
        ),
      ),
    );
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
                        crossAxisAlignment: CrossAxisAlignment.end,
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
    final isBlocked = state.isIrisResolving;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: AppButton.button(
          backgroundColor: isBlocked ? const Color(0xFF415058) : null,
          widget: Center(
              child: AppText.text(
                  isBlocked ? 'Finalising IRIS estimate...' : 'Review delivery',
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          onPressed: () {
            if (isBlocked) return;
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => DeliveryReviewExpandedView()));
          }),
    );
  }));
}
