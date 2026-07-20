import 'package:flutter/widgets.dart';

import 'business_models.dart';

enum BusinessJourneyType { delivery, healthPlus, gifts }

class BusinessJourneyContext {
  final String businessId;
  final String businessName;
  final String billingEmail;
  final BusinessJourneyType journeyType;
  final String billingSource;
  final String paymentProfileSource;

  const BusinessJourneyContext({
    required this.businessId,
    required this.businessName,
    required this.billingEmail,
    required this.journeyType,
    this.billingSource = 'business_finance',
    this.paymentProfileSource = 'shared_payment_profile',
  });

  factory BusinessJourneyContext.forAccount(
    BusinessAccount account,
    BusinessJourneyType journeyType,
  ) {
    return BusinessJourneyContext(
      businessId: account.id,
      businessName: account.name,
      billingEmail: account.billingEmail.isNotEmpty
          ? account.billingEmail
          : account.contactEmail,
      journeyType: journeyType,
    );
  }

  Map<String, dynamic> toMap() => {
        'businessId': businessId,
        'businessName': businessName,
        'billingEmail': billingEmail,
        'businessMode': true,
        'businessJourney': journeyType.name,
        'billingSource': billingSource,
        'paymentProfileSource': paymentProfileSource,
      };
}

class BusinessJourneyScope extends InheritedWidget {
  final BusinessJourneyContext journey;

  const BusinessJourneyScope({
    super.key,
    required this.journey,
    required super.child,
  });

  static BusinessJourneyContext? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<BusinessJourneyScope>()
        ?.journey;
  }

  @override
  bool updateShouldNotify(BusinessJourneyScope oldWidget) {
    return journey.businessId != oldWidget.journey.businessId ||
        journey.journeyType != oldWidget.journey.journeyType;
  }
}
