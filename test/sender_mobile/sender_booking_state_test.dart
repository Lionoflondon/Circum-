import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sender mobile booking state', () {
    test('uses the locked Sender Engine step order', () {
      expect(SenderBookingStep.values, const [
        SenderBookingStep.pickup,
        SenderBookingStep.dropoff,
        SenderBookingStep.recipient,
        SenderBookingStep.deliveryTime,
        SenderBookingStep.parcel,
        SenderBookingStep.iris,
        SenderBookingStep.options,
        SenderBookingStep.review,
        SenderBookingStep.payment,
        SenderBookingStep.findingRider,
        SenderBookingStep.liveTracking,
      ]);
    });

    test('back and forward retain entered booking data', () {
      final draft = const SenderBookingDraft()
          .copyWith(pickupAddress: 'Flat 2, 14 Harley Street')
          .next()
          .copyWith(dropoffAddress: 'Chelsea')
          .next()
          .back();

      expect(draft.step, SenderBookingStep.dropoff);
      expect(draft.pickupAddress, 'Flat 2, 14 Harley Street');
      expect(draft.dropoffAddress, 'Chelsea');
    });

    test('recipient step requires name and phone', () {
      final draft = const SenderBookingDraft(
        step: SenderBookingStep.recipient,
        receiverName: 'Ada',
      );

      expect(draft.canContinue, isFalse);
      expect(
          draft.copyWith(receiverPhone: '+447891362527').canContinue, isTrue);
    });

    test('schedule is not treated as live booking support', () {
      const draft = SenderBookingDraft(
        step: SenderBookingStep.deliveryTime,
        deliveryTime: 'Schedule',
      );

      expect(draft.canContinue, isFalse);
    });

    test('IRIS confidence exposes labels only', () {
      expect(mapConfidenceLabel(.91), 'High');
      expect(mapConfidenceLabel(.70), 'Medium');
      expect(mapConfidenceLabel(.40), 'Low');
    });

    test('Vanguard is not treated as a delivery speed', () {
      expect(senderDeliverySpeeds, const ['Economy', 'Standard', 'Express']);
      expect(isSenderDeliverySpeed('Standard'), isTrue);
      expect(isSenderDeliverySpeed('Vanguard'), isFalse);
    });

    test('Vanguard add-on does not replace selected delivery speed', () {
      final draft = const SenderBookingDraft(
        step: SenderBookingStep.options,
        selectedOption: 'Express',
      ).copyWith(vanguard: true);

      expect(draft.selectedOption, 'Express');
      expect(draft.vanguard, isTrue);
      expect(draft.addOnTotalGbp, senderVanguardAddOnPriceGbp);
      expect(draft.totalWithAddOns(8), 9.99);
    });

    test('removing Vanguard removes only the add-on price', () {
      final draft =
          const SenderBookingDraft(vanguard: true).copyWith(vanguard: false);

      expect(draft.selectedOption, 'Standard');
      expect(draft.addOnTotalGbp, 0);
      expect(draft.totalWithAddOns(8), 8);
    });

    test('payment cannot fake success', () {
      const unpaid = SenderBookingDraft(
        step: SenderBookingStep.payment,
        paymentStatus: SenderPaymentStatus.notReady,
      );
      const paidButNotConfirmed = SenderBookingDraft(
        step: SenderBookingStep.payment,
        paymentStatus: SenderPaymentStatus.paid,
      );

      expect(unpaid.canContinue, isFalse);
      expect(unpaid.next().step, SenderBookingStep.payment);
      expect(paidButNotConfirmed.exposesPaymentSuccess, isFalse);
    });
  });
}
