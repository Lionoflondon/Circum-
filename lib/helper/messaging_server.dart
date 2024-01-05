import 'package:firebase_cloud_messaging_flutter/firebase_cloud_messaging_flutter.dart';

class MessagingServer {
  sendMessage(
      {required Map<String, String> data,
      required String code,
      required String message,
      String? title}) async {
    try {
      /// My Service Account Json File Content
      final serviceAccountFileContent = <String, String>{
        "type": "service_account",
        "project_id": "circum-2797c",
        "private_key_id": "6f4302ea31ee7f3c12eeedb847e5c381373af1b1",
        "private_key":
            "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQChEfYzJlXNM+gH\njr0FcU8PgKcMZjgOuCRB5/MpfvINrEItgP7gnkhCrq/McNOYJib7UocPLgzzhiTn\nveYmXbW7yx/jP+Ga1Bl6Bl4qHWkbKGDw0smsfAo0hyZVq1CcYF+Zm5pVb0DHIMFn\nL/n+fI7DbX6M+cpfcbncOpZxlG5idsYUHMva29OHd4YXaYKXgjlBXFNKu+H49O2H\nvRwrgCCq6IDvzG0ryKcEJdQhpR58oRHVEVeBXKfMw2D2v7HPHkwy+IxKXxvguw2R\nZiNxcxJ6CZ1ThLbA8ZPaRM51gTaCNRKyrThG9vGD/CYqGE+/PAHKieOBLKmrfPuM\nbQhjs3GBAgMBAAECggEAC2mN467mKm1wlcR/0RhnrSYE8AR4GVbjvsWz/W8wsFZR\ntA6tQHYGka715srhuyiM34bH6gPtx/1rtP3IBlTicQVh44SdtA4uJe64kkxWK6Xv\nRHDy+CUrxfADf9NtGT9c1rHnPAFvegxwl6KXGHhz1xX1fwCd3ahdrmR6T17geVpr\nFqoHnY7otRvBni+sJfhEecc5yXpZX/3dQzkbUCSRjsOv5da+hLLDB33R4NDb5xCs\nDhm1nY/+WfMkSAGbXY2xb+D5dhGYs5TYSjIosouqQysj9+16OX94kgCw/5NRSc18\nr4vh70Vn/Gtv3gDWY6DHpBhWdGuIjTZCiVLBHWbZJwKBgQDjIbZJCcpZN4CpiTCK\ny6NgcIS1Z47SrLV4agEojcEekIsnRO717Ay608qSfezaatLpfas9lOEi1FNstipv\noM7Z1AH0qGCe5eyTk731NnkGg61uB2KAQ03X5WQ2uJ2/aBABECFPSPM2nlplRB1l\nUUvS5gqcdxZn5Scq/uo6jVYTiwKBgQC1isaIkq+3V1qUqwo54/CTEqE6AbYDScD5\nLV74s7jnu2p2Y6DUbFjXCEHSGjXek/AAVDbXnSu46CWDxvh5OF5VJcwmgH+6P3Ee\nm/fLnhwLpAcOIegKm6XFMUI6t6lIO/rd655hR3w0Tf+uPWgGjE5U8JJuxkbUKUAU\nVOAk2k8AowKBgHZ+CekEsInmyLqpladzIWKYkMNKqVoDPBD7zGrpuQxHADGWZsvp\nP6LgBthx1XUFMc8Z/pH775AKEROv3WerDv7Y+cQ3a2C6Nreu5fTdXDony/yQ4bRk\naGHvjF535eQLV/4V+iqwtiGSbzpRVLycst/tny+NeSTuiYaGwo+VWIiNAoGBAIwn\ni4a82HPPONs2ATsYQw8IfvhtgbugIR8+a+fNuJ8PDe5AlFXrH9tDQK2YFqazx8I5\nQe3MJYknkG7gGcxcPFe4Spge9H0xpX9gIjpM4pIKHHhIrQAjkiNfGCaEzGg8Bj12\nPlwT+EvZO9+lAL6ta3wgDqz+3ofFIPeRX0qUUBHJAoGBAOFXmicg3d9PV/4BIrQ9\n0/PrVxq3VqQijq1jl8+U1f+cXuxR24x0zT/xrqlkWFSI7ziETNzfu++tPDaKNwAK\nIYZ5blcevCilT9Rydjbpx3+pXg3r+0E5AU5ihwP4KT/qgfvd9Z/G/tfxeTgz4G13\nMAU48rGgb3MGeTNU9gB2MFix\n-----END PRIVATE KEY-----\n",
        "client_email":
            "firebase-adminsdk-ged9l@circum-2797c.iam.gserviceaccount.com",
        "client_id": "106136873750259055946",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url":
            "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url":
            "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-ged9l%40circum-2797c.iam.gserviceaccount.com",
        "universe_domain": "googleapis.com"
      };

      /// Add Your Service Account File Content as Map
      var server = FirebaseCloudMessagingServer(
        serviceAccountFileContent,
      );

      /// Get Firebase  Messagin Token [Optional, If you want to send message to specific user]
      /// Don't pass token if you want to send message to all registered users
      // String? token = await FirebaseMessaging.instance.geToken();

      /// Send a Message
      var result = await server.send(
        FirebaseSend(
          validateOnly: false,
          message: FirebaseMessage(
            apns: const FirebaseApnsConfig(payload: {
              'aps': {'content-available': 1}
            }),
            token:
                code, // only required If you want to send message to specific user.
            data: data,
            // topic: topic,
            notification: FirebaseNotification(
              title: title,
              body: message,
            ),
            android: FirebaseAndroidConfig(
              // ttl: '3s',
              /// Add Delay in String. If you want to add 1 minute delat then add it like "60s"
              notification: FirebaseAndroidNotification(
                title: title,
                body: message,
                // icon: 'ic_notification',
                // color: '#009999',
              ),
            ),
          ),
        ),
      );

      /// Print Request response
      print(result.toString());
    } catch (err) {
      print(err);
    }
  }
}
