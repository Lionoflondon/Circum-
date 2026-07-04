import 'package:cloud_functions/cloud_functions.dart';

class RiderPresenceController {
  final FirebaseFunctions functions;

  const RiderPresenceController({required this.functions});

  Future<String?> goOnline() async {
    try {
      await functions.httpsCallable('goOnline').call();
      return null;
    } on FirebaseFunctionsException catch (error) {
      return error.message ?? 'Unable to go online.';
    } catch (_) {
      return 'Unable to go online.';
    }
  }

  Future<String?> goOffline() async {
    try {
      await functions.httpsCallable('goOffline').call();
      return null;
    } on FirebaseFunctionsException catch (error) {
      return error.message ?? 'Unable to go offline.';
    } catch (_) {
      return 'Unable to go offline.';
    }
  }

  Future<String?> updateHeartbeat() async {
    try {
      await functions.httpsCallable('updateRiderPresence').call();
      return null;
    } on FirebaseFunctionsException catch (error) {
      return error.message ?? 'Unable to update rider presence.';
    } catch (_) {
      return 'Unable to update rider presence.';
    }
  }
}
