import 'package:cloud_functions/cloud_functions.dart';
import 'package:circum/app/authentication/bloc/auth_bloc.dart';
import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/helper/toast_helper.dart';
import 'package:circum/pricing/delivery_pricing.dart';
import 'package:circum/utils/theme/theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import 'package:circum/env/env.dart';
import '../../../utils/theme/text_field.dart';

class DeliveryReviewExpandedView extends StatefulWidget {
  const DeliveryReviewExpandedView({super.key});

  @override
  State<DeliveryReviewExpandedView> createState() =>
      _DeliveryReviewExpandedViewState();
}

class _DeliveryReviewExpandedViewState
    extends State<DeliveryReviewExpandedView> {
  final TextEditingController _textFieldController = TextEditingController();

  String? username;
  String? phoneNumber;
  String? additonalPickupInformation;

  String? dropoffContactName;
  String? dropoffContactPhoneNumber;
  String? dropoffAdditionalInformation;

  String? email;
  bool _isConfirmingDelivery = false;

  @override
  void initState() {
    final authBloc = context.read<AuthBloc>();
    username = authBloc.state.username;
    phoneNumber = authBloc.state.phoneNumber;
    email = authBloc.state.email;
    super.initState();
  }

  @override
  void dispose() {
    _textFieldController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: AppColors.secondary,
        elevation: 0,
        centerTitle: true,
        title: AppText.text('Review delivery',
            fontSize: 16, fontWeight: FontWeight.bold),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    pickupDetail(),
                    const SizedBox(height: 52),
                    dropOffDetails(),
                  ],
                ))),
        confirmDeliveryButton()
      ]),
    );
  }

  Widget reviewTile({
    required String iconPath,
    required String label,
    required String? value,
    String? placeholder,
    VoidCallback? onTap,
  }) {
    final hasValue = value != null && value.trim().isNotEmpty;
    final tileContent = Row(
      children: [
        SvgPicture.asset(
          iconPath,
          height: 32,
          width: 32,
        ),
        const SizedBox(width: 18),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText.text(label, color: const Color(0xFFC9D2D7), fontSize: 12),
            AppText.text(hasValue ? value.trim() : placeholder ?? '',
                fontSize: 16,
                color: hasValue ? Colors.white : const Color(0xFFC9D2D7)),
          ],
        )),
        if (onTap != null)
          const Icon(
            Icons.arrow_forward_ios,
            color: Color(0xFF415058),
          )
      ],
    );

    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: tileContent,
      );
    }

    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      title: tileContent,
    );
  }

  Widget pickupDetail() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(left: 24),
              child: AppText.text('Pick-up details',
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          reviewTile(
            iconPath: 'assets/svg/profile.svg',
            label: 'Contact name',
            value: username,
            onTap: () async {
              final contactName = await textDetailsBottomSheet(
                title: 'Contact name',
                initialText: username,
              );

              if (contactName != null) {
                setState(() {
                  username = contactName;
                });
              }
            },
          ),
          const SizedBox(height: 20),
          reviewTile(
            iconPath: 'assets/svg/location.svg',
            label: 'Address',
            value: '${state.pickupLocation}, ${state.pickupLocationSubAddress}',
          ),
          const SizedBox(height: 20),
          reviewTile(
            iconPath: 'assets/svg/phone.svg',
            label: 'Phone number',
            value: phoneNumber,
            placeholder: 'Phone number',
            onTap: () async {
              final newPhone = await phoneBottomSheet(title: 'Phone number');

              if (newPhone != null) {
                if (!mounted) return;
                setState(() {
                  phoneNumber = newPhone;
                });
                if (!context.mounted) return;
                context
                    .read<AuthBloc>()
                    .add(UpdatePhoneNumber(value: newPhone));
              }
            },
          ),
          const SizedBox(height: 20),
          reviewTile(
            iconPath: 'assets/svg/legal.svg',
            label: 'More information',
            value: additonalPickupInformation,
            placeholder: 'Add an additional information',
            onTap: () async {
              final info = await textDetailsBottomSheet(
                title: 'More information',
                initialText: additonalPickupInformation,
                hintText: 'Add an additional information',
                minLines: 4,
                maxLines: 4,
              );

              if (info != null) {
                setState(() {
                  additonalPickupInformation = info;
                });
              }
            },
          ),
        ],
      );
    });
  }

  Widget dropOffDetails() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(left: 24),
              child: AppText.text('Drop-off details',
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          reviewTile(
            iconPath: 'assets/svg/profile.svg',
            label: 'Contact name',
            value: dropoffContactName,
            placeholder: 'Full name',
            onTap: () async {
              final info = await textDetailsBottomSheet(
                title: 'Contact name',
                initialText: dropoffContactName,
              );

              if (info != null) {
                setState(() {
                  dropoffContactName = info;
                });
              }
            },
          ),
          const SizedBox(height: 20),
          reviewTile(
            iconPath: 'assets/svg/location.svg',
            label: 'Address',
            value:
                '${state.destinationLocation}, ${state.destinationLocationSubAddress}',
          ),
          const SizedBox(height: 20),
          reviewTile(
            iconPath: 'assets/svg/phone.svg',
            label: 'Phone number',
            value: dropoffContactPhoneNumber,
            placeholder: 'Phone number',
            onTap: () async {
              final info = await phoneBottomSheet(title: 'Phone number');

              if (info != null) {
                setState(() {
                  dropoffContactPhoneNumber = info;
                });
              }
            },
          ),
          const SizedBox(height: 20),
          reviewTile(
            iconPath: 'assets/svg/legal.svg',
            label: 'Delivery instructions',
            value: dropoffAdditionalInformation,
            placeholder: 'Access code, flat number…',
            onTap: () async {
              final info = await textDetailsBottomSheet(
                title: 'Delivery instructions',
                initialText: dropoffAdditionalInformation,
                hintText: 'Access code, flat number…',
                minLines: 4,
                maxLines: 4,
              );

              if (info != null) {
                setState(() {
                  dropoffAdditionalInformation = info;
                });
              }
            },
          ),
        ],
      );
    });
  }

  Widget confirmDeliveryButton() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      final isBusy = _isConfirmingDelivery ||
          state.isSenderPaymentLoading ||
          state.isSenderDeliveryCreating;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32)
            .copyWith(top: 16),
        child: AppButton.button(
            widget: Center(
                child: AppText.text(
                    isBusy ? 'Confirming...' : 'Confirm delivery',
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            onPressed: () async {
              if (isBusy) return;
              if (phoneNumber == null || phoneNumber!.trim().isEmpty) {
                return ShowToast()
                    .errorToast(title: 'Please add a pick-up phone number');
              }
              if (dropoffContactName == null ||
                  dropoffContactName!.trim().length < 2) {
                return ShowToast()
                    .errorToast(title: 'Please add a drop-off contact name');
              }
              if (dropoffContactPhoneNumber == null ||
                  dropoffContactPhoneNumber!.trim().isEmpty) {
                return ShowToast()
                    .errorToast(title: 'Please add a drop-off phone number');
              }
              if (state.pickupCoordinate == null ||
                  state.desinationCoordinate == null) {
                return ShowToast().errorToast(
                    title: 'Add pickup and drop-off addresses to continue');
              }
              await _confirmWithCanonicalPayment(context, state);
            }),
      );
    });
  }

  Future<void> _confirmWithCanonicalPayment(
    BuildContext context,
    SendPackageState state,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ShowToast().errorToast(title: 'Sign in to confirm this delivery');
      return;
    }
    setState(() => _isConfirmingDelivery = true);
    try {
      final quote = await _ensureCanonicalQuote(state);
      final quoteId = '${quote['quoteId'] ?? state.senderQuoteId ?? ''}';
      if (quoteId.isEmpty) {
        throw StateError('Could not load delivery estimate. Try again.');
      }
      final payment = await _startCanonicalPaymentSession(quoteId);
      final paymentStatus = '${payment['paymentStatus'] ?? payment['status']}';
      if (paymentStatus != 'succeeded') {
        final clientSecret = '${payment['clientSecret'] ?? ''}';
        if (clientSecret.isEmpty) {
          throw StateError('Payment could not be started. Try again.');
        }
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret,
            merchantDisplayName: 'Circum',
            customerId: '${payment['customerId'] ?? ''}'.isEmpty
                ? null
                : '${payment['customerId']}',
            customerEphemeralKeySecret:
                '${payment['ephemeralKeySecret'] ?? ''}'.isEmpty
                    ? null
                    : '${payment['ephemeralKeySecret']}',
            applePay: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
                ? const PaymentSheetApplePay(merchantCountryCode: 'GB')
                : null,
            googlePay:
                !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                    ? const PaymentSheetGooglePay(
                        merchantCountryCode: 'GB',
                        currencyCode: 'GBP',
                      )
                    : null,
            style: ThemeMode.dark,
          ),
        );
        await Stripe.instance.presentPaymentSheet();
      }

      final paymentSessionId = '${payment['paymentSessionId'] ?? ''}';
      if (paymentSessionId.isEmpty) {
        throw StateError('Payment could not be confirmed. Try again.');
      }
      final created = await _createCanonicalPaidDelivery(
        state: state,
        quoteId: quoteId,
        paymentSessionId: paymentSessionId,
        userId: user.uid,
      );
      final requestId = '${created['requestId'] ?? ''}';
      if (requestId.isEmpty) {
        throw StateError('Delivery could not be created after payment.');
      }
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('sendPackage')
          .call({'requestId': requestId});
      if (!context.mounted) return;
      context
          .read<SendPackageBloc>()
          .add(WatchActiveDelivery(requestId: requestId));
      ShowToast().successToast(title: 'Delivery confirmed');
      Navigator.pop(context);
    } on StripeException {
      ShowToast().errorToast(title: 'Payment was cancelled.');
    } on FirebaseFunctionsException catch (error) {
      ShowToast().errorToast(
          title: error.message ?? 'Delivery could not be confirmed.');
    } catch (error) {
      ShowToast().errorToast(title: '$error'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _isConfirmingDelivery = false);
    }
  }

  Future<Map<String, dynamic>> _ensureCanonicalQuote(
    SendPackageState state,
  ) async {
    if (state.senderQuoteId != null && state.senderQuoteId!.isNotEmpty) {
      return {
        'quoteId': state.senderQuoteId,
        'total': state.senderQuoteTotal ?? state.price,
        'selectedSpeed': state.senderQuoteSpeed ?? 'standard',
      };
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('createSenderBookingQuote')
        .call({
      'selectedSpeed': 'standard',
      'vanguardProtocolEnabled':
          state.canonicalIrisResult?.vanguardRequired == true,
      'distanceMiles': state.distance == null
          ? 0
          : DeliveryPricing.kilometresToMiles(state.distance!),
      'weightKg': state.parcelWeightKg,
      'parcel': {
        'itemName': state.canonicalIrisResult?.itemName ??
            state.itemDescription ??
            'Parcel',
        'description': state.itemDescription ?? '',
        'weightKg': state.parcelWeightKg,
        'fragile': false,
        'highValue': state.canonicalIrisResult?.vanguardRequired == true,
      },
      'iris': {
        if (state.canonicalIrisResult != null) ...{
          'itemName': state.canonicalIrisResult!.itemName,
          'quantity': state.canonicalIrisResult!.quantity,
          'totalWeightKg': state.canonicalIrisResult!.totalWeightKg,
          'category': state.canonicalIrisResult!.category,
          'recommendedVehicle': state.canonicalIrisResult!.recommendedVehicle,
          'confidence': state.canonicalIrisResult!.confidenceLabel,
          'vanguardRequired': state.canonicalIrisResult!.vanguardRequired,
          'vanguardRequiredReason':
              state.canonicalIrisResult!.vanguardRequiredReason,
        },
      },
    });
    return result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _startCanonicalPaymentSession(
    String quoteId,
  ) async {
    Stripe.publishableKey = Env.publishableLiveKey;
    await Stripe.instance.applySettings();
    final result = await FirebaseFunctions.instance
        .httpsCallable('createSenderPaymentSession')
        .call({
      'quoteId': quoteId,
      'rothEnabled': false,
      'fallbackMethod': 'card',
    });
    return result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _createCanonicalPaidDelivery({
    required SendPackageState state,
    required String quoteId,
    required String paymentSessionId,
    required String userId,
  }) async {
    final requestId = 'sender-${DateTime.now().millisecondsSinceEpoch}';
    final result = await FirebaseFunctions.instance
        .httpsCallable('createSenderPaidDelivery')
        .call({
      'requestId': requestId,
      'draftId': requestId,
      'idempotencyKey': 'sender-$userId-$requestId-$quoteId',
      'quoteId': quoteId,
      'paymentSessionId': paymentSessionId,
      'pickup': {
        'fullname': username,
        'phone': phoneNumber,
        'address': state.pickupLocation,
        'subAddress': state.pickupLocationSubAddress ?? '',
        'locality': state.pickupLocality ?? '',
        'instructions': additonalPickupInformation ?? '',
        'coordinates': {
          'lat': state.pickupCoordinate!.lat,
          'lng': state.pickupCoordinate!.lng,
        },
      },
      'dropoff': {
        'fullname': dropoffContactName,
        'phone': dropoffContactPhoneNumber,
        'address': state.destinationLocation,
        'subAddress': state.destinationLocationSubAddress ?? '',
        'locality': state.destinationLocality ?? '',
        'instructions': dropoffAdditionalInformation ?? '',
        'coordinates': {
          'lat': state.desinationCoordinate!.lat,
          'lng': state.desinationCoordinate!.lng,
        },
      },
      'recipient': {
        'name': dropoffContactName,
        'phone': dropoffContactPhoneNumber,
        'deliveryNotes': dropoffAdditionalInformation,
      },
      'deliveryTime': {
        'type': 'now',
        'summary': 'Deliver now',
      },
      'parcel': {
        'itemName': state.canonicalIrisResult?.itemName ??
            state.itemDescription ??
            'Parcel',
        'description': state.itemDescription ?? '',
        'weightKg': state.parcelWeightKg,
        'highValue': state.canonicalIrisResult?.vanguardRequired == true,
      },
      'iris': {
        if (state.canonicalIrisResult != null) ...{
          'itemName': state.canonicalIrisResult!.itemName,
          'quantity': state.canonicalIrisResult!.quantity,
          'totalWeightKg': state.canonicalIrisResult!.totalWeightKg,
          'recommendedVehicle': state.canonicalIrisResult!.recommendedVehicle,
          'confidence': state.canonicalIrisResult!.confidenceLabel,
          'category': state.canonicalIrisResult!.category,
          'vanguardRequired': state.canonicalIrisResult!.vanguardRequired,
          'vanguardRequiredReason':
              state.canonicalIrisResult!.vanguardRequiredReason,
        },
      },
    });
    return result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : <String, dynamic>{};
  }

  Future<String?> textDetailsBottomSheet({
    required String title,
    String? initialText,
    String? hintText,
    int minLines = 1,
    int maxLines = 1,
  }) {
    _textFieldController.text = initialText ?? '';
    return showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20))),
        builder: (_) {
          return Wrap(
            children: [
              Container(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: AppText.text(title),
                      ),
                      const SizedBox(height: 12),
                      Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          child: AppTextInput.input(
                              hintText: hintText,
                              minLines: minLines,
                              maxLines: maxLines,
                              keyboardType: TextInputType.text,
                              autofocus: true,
                              controller: _textFieldController)),
                      const SizedBox(height: 20),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Expanded(
                                  child: AppButton.button(
                                      backgroundColor: Colors.grey[400],
                                      widget: AppText.text('Cancel',
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600),
                                      onPressed: () {
                                        Navigator.pop(context);
                                      })),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: AppButton.button(
                                      widget: AppText.text('Done',
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600),
                                      onPressed: () async {
                                        final text =
                                            _textFieldController.text.trim();
                                        if (text.length > 2) {
                                          Navigator.pop(context, text);
                                          _textFieldController.clear();
                                        } else {
                                          await ShowToast().errorToast(
                                              title: 'Name is too short');
                                        }
                                      })),
                            ],
                          )),
                      const SizedBox(height: 60),
                    ],
                  ))
            ],
          );
        });
  }

  Future<String?> phoneBottomSheet({required String title}) {
    return showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20))),
        builder: (_) {
          bool isPhoneValid = false;
          String? completeNumber;

          return StatefulBuilder(builder: (context, setSheetState) {
            return Wrap(
              children: [
                Container(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height * 0.8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: AppText.text(title),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          child: IntlPhoneField(
                            style: const TextStyle(
                                color: Colors.white, fontFamily: 'Helvetica'),
                            dropdownTextStyle: const TextStyle(
                                color: Colors.white, fontFamily: 'Helvetica'),
                            decoration: InputDecoration(
                              fillColor: AppColors.input,
                              filled: true,
                              labelStyle: const TextStyle(
                                  fontFamily: 'Helvetica',
                                  fontSize: 14.0,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.grey),
                              hintStyle: TextStyle(
                                  color: const Color(0xFF050529)
                                      .withValues(alpha: 0.25),
                                  fontFamily: 'Helvetica'),
                              focusedBorder: const OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(0)),
                                borderSide: BorderSide(
                                    width: 1, color: AppColors.primary),
                              ),
                              enabledBorder: const OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(0)),
                                borderSide:
                                    BorderSide(color: Color(0xFF050529)),
                              ),
                            ),
                            initialCountryCode: 'GB',
                            onChanged: (val) {
                              setSheetState(() {
                                isPhoneValid = val.isValidNumber();
                                completeNumber = val.completeNumber;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              children: [
                                Expanded(
                                    child: AppButton.button(
                                        backgroundColor: Colors.grey[400],
                                        widget: AppText.text('Cancel',
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600),
                                        onPressed: () {
                                          Navigator.pop(context);
                                        })),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: AppButton.button(
                                        widget: AppText.text('Done',
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600),
                                        onPressed: () async {
                                          if (isPhoneValid &&
                                              completeNumber != null) {
                                            Navigator.pop(
                                                context, completeNumber);
                                          } else {
                                            await ShowToast().errorToast(
                                                title:
                                                    'Please enter a valid phone number');
                                          }
                                        })),
                              ],
                            )),
                        const SizedBox(height: 60),
                      ],
                    ))
              ],
            );
          });
        });
  }
}
