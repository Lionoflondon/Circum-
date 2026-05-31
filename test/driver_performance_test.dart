import 'package:circum/app/rider_profiles/driver_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Driver profiles and ratings', () {
    test('creates a driver profile with vehicle and plate details', () {
      final profile = DriverProfile.fromMap('driver-1', {
        'fullName': 'Marcus A.',
        'phoneNumber': '+44 7700 900111',
        'verificationStatus': 'verified',
        'vehicleType': 'Car',
        'vehicleMakeModel': 'Toyota Prius',
        'vehicleColour': 'Black',
        'plateNumber': 'CIR 24K',
      });

      expect(profile.fullName, 'Marcus A.');
      expect(profile.phoneNumber, '+44 7700 900111');
      expect(profile.vehicle.type, 'Car');
      expect(profile.vehicle.makeModel, 'Toyota Prius');
      expect(profile.vehicle.colour, 'Black');
      expect(profile.vehicle.plateNumber, 'CIR 24K');
    });

    test('models a five-star driver rating linked to a delivery', () {
      final rating = DriverRating(
        driverId: 'driver-1',
        customerId: 'customer-1',
        deliveryId: 'CIR-123',
        starRating: 5,
        feedbackText: 'Really careful with the parcel.',
        feedbackTags: const ['on_time', 'handled_item_carefully'],
      );

      expect(rating.toJson()['driverId'], 'driver-1');
      expect(rating.toJson()['deliveryId'], 'CIR-123');
      expect(rating.toJson()['starRating'], 5);
    });

    test('uses delivery and customer ids to prevent duplicate ratings', () {
      const deliveryId = 'CIR-123';
      const customerId = 'customer-1';
      final ratingDocumentId = DriverRating.documentId(
        deliveryId: deliveryId,
        customerId: customerId,
      );

      expect(ratingDocumentId, 'CIR-123_customer-1');
    });

    test('sanitizes rating document ids and identifies complaint tags', () {
      final rating = DriverRating(
        driverId: 'driver-1',
        customerId: 'sender/1',
        deliveryId: 'CIR/123',
        starRating: 4,
        feedbackTags: const ['poor_communication'],
      );

      expect(
        DriverRating.documentId(
          deliveryId: rating.deliveryId,
          customerId: rating.customerId,
        ),
        'CIR-123_sender-1',
      );
      expect(rating.isComplaint, isTrue);
    });

    test('calculates average rating and distribution', () {
      final metric = DriverPerformanceService.calculate(
        DriverPerformanceInput(
          driverId: 'driver-1',
          completedTrips: 6,
          ratings: const [
            DriverRating(
              driverId: 'driver-1',
              customerId: 'a',
              deliveryId: '1',
              starRating: 5,
            ),
            DriverRating(
              driverId: 'driver-1',
              customerId: 'b',
              deliveryId: '2',
              starRating: 4,
            ),
            DriverRating(
              driverId: 'driver-1',
              customerId: 'c',
              deliveryId: '3',
              starRating: 3,
            ),
          ],
        ),
      );

      expect(metric.averageRating, 4);
      expect(metric.totalRatings, 3);
      expect(metric.ratingDistribution[5], 1);
      expect(metric.ratingDistribution[4], 1);
      expect(metric.ratingDistribution[3], 1);
    });

    test('calculates quality score with delivery risk penalties', () {
      final score = DriverPerformanceService.qualityScore(
        averageRating: 4.8,
        completedTrips: 80,
        cancelledTrips: 2,
        lateDeliveries: 4,
        failedDeliveries: 1,
        complaints: 1,
      );

      expect(score, greaterThan(70));
      expect(score, lessThanOrEqualTo(100));
    });

    test('flags low-rated drivers for review', () {
      final metric = DriverPerformanceService.calculate(
        DriverPerformanceInput(
          driverId: 'driver-1',
          completedTrips: 10,
          complaints: 2,
          ratings: const [
            DriverRating(
              driverId: 'driver-1',
              customerId: 'a',
              deliveryId: '1',
              starRating: 2,
            ),
            DriverRating(
              driverId: 'driver-1',
              customerId: 'b',
              deliveryId: '2',
              starRating: 3,
            ),
          ],
        ),
      );

      expect(metric.driverStatus, 'under_review');
      expect(DriverPerformanceService.shouldFlagLowRatedDriver(metric), isTrue);
    });
  });
}
