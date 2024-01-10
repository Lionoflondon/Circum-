import 'dart:convert';
import 'package:circum/app/account/bloc/account_bloc.dart';
import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/helper/chats_help.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app.dart';
import 'app/authentication/bloc/auth_bloc.dart';
import 'app/bottom_nav/bloc/navbar_bloc.dart';
import 'app/history/bloc/history_bloc.dart';
import 'app/support/bloc/support_bloc.dart';
import 'utils/nav/nav_key.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:bot_toast/bot_toast.dart';

final sendPackageBloc = SendPackageBloc();

foregoundMessage() {
  // chatBloc.add(event);
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    print('Got a message whilst in the foreground!');
    // print('Message data: ${message.data}');

    if (message.data['type'] == 'connection') {
      if (message.data['status'] == 'accepted') {
        print('accepted');
        try {
          // Remove leading and trailing whitespace
          String jsonString = message.data['data'].trim();

          // Replace single quotes with double quotes to make it valid JSON
          jsonString = jsonString.replaceAll("'", '"');
          print(jsonString);

          // Parse the modified string into a map
          Map<String, dynamic> mapData = jsonDecode(jsonString);

          sendPackageBloc.add(DeliveryAccepted(data: mapData));
        } catch (e) {
          print(e);
        }
      }
    }

    if (message.data['type'] == 'location-broadcast') {
      try {
        // Remove leading and trailing whitespace
        String jsonString = message.data['data'].trim();

        // Replace single quotes with double quotes to make it valid JSON
        jsonString = jsonString.replaceAll("'", '"');
        // print(jsonString);

        // Parse the modified string into a map
        Map<String, dynamic> mapData = jsonDecode(jsonString);

        sendPackageBloc.add(SetRiderLocation(data: mapData));
      } catch (e) {
        print(e);
      }
    }

    if (message.data['type'] == 'message') {
      // Remove leading and trailing whitespace
      // String jsonString = message.data['data'].trim();

      // // Replace single quotes with double quotes to make it valid JSON
      // jsonString = jsonString.replaceAll("'", '"');
      // // print(jsonString);

      // Parse the modified string into a map
      Map<String, dynamic> msg = jsonDecode(message.data['data']);
      sendPackageBloc.add(IncomingMessage(data: msg));

      await ChatsHelper().storeChat(msg);
    }

    if (message.data['type'] == 'delivery-completed') {
      print('Delivery completed');
      try {
        // Remove leading and trailing whitespace
        String jsonString = message.data['data'].trim();

        // Replace single quotes with double quotes to make it valid JSON
        jsonString = jsonString.replaceAll("'", '"');
        print(jsonString);

        // Parse the modified string into a map
        Map<String, dynamic> mapData = jsonDecode(jsonString);

        sendPackageBloc.add(DeliveryCompleted(data: mapData));
      } catch (e) {
        print(e);
      }
    }
  });
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();

  print('Got a message whilst in the background!');
  // print('Message data: ${message.data}');

  if (message.data['type'] == 'connection') {
    if (message.data['status'] == 'accepted') {
      print('accepted');
      try {
        // Remove leading and trailing whitespace
        String jsonString = message.data['data'].trim();

        // Replace single quotes with double quotes to make it valid JSON
        jsonString = jsonString.replaceAll("'", '"');
        print(jsonString);

        // Parse the modified string into a map
        Map<String, dynamic> mapData = jsonDecode(jsonString);

        sendPackageBloc.add(DeliveryAccepted(data: mapData));
      } catch (e) {
        print(e);
      }
    }
  }

  if (message.data['type'] == 'message') {
    // Remove leading and trailing whitespace
    String jsonString = message.data['data'].trim();

    // Replace single quotes with double quotes to make it valid JSON
    jsonString = jsonString.replaceAll("'", '"');
    // print(jsonString);

    // Parse the modified string into a map
    Map<String, dynamic> msg = jsonDecode(jsonString);
    sendPackageBloc.add(IncomingMessage(data: msg));

    await ChatsHelper().storeChat(msg);
  }

  // if (message.data['type'] == 'connection') {
  //   if (message.data['status'] == 'accepted') {
  //     print('accepted');
  //     try {
  //       // Remove leading and trailing whitespace
  //       String jsonString = message.data['data'].trim();

  //       // Replace single quotes with double quotes to make it valid JSON
  //       jsonString = jsonString.replaceAll("'", '"');
  //       print(jsonString);

  //       // Parse the modified string into a map
  //       Map<String, dynamic> mapData = jsonDecode(jsonString);

  //       sendPackageBloc.add(DeliveryAccepted(data: mapData));
  //     } catch (e) {
  //       print(e);
  //     }
  //   }
  // }
  if (message.data['type'] == 'message') {
    final msg = jsonDecode(message.data['data']);
    sendPackageBloc.add(IncomingMessage(data: msg));

    await ChatsHelper().storeChat(msg);
  }

  return Future<void>.value();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true, // Required to display a heads up notification
    badge: true,
    sound: true,
  );

  foregoundMessage();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Lock app in portrait mode
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      // statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light));

  SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown])
      .then((value) {
    Bloc.observer = SimpleBlocObserver();
    runApp(Circum());
  });
}

class Circum extends StatelessWidget {
  const Circum({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        builder: (_, __) {
          final botToastBuilder = BotToastInit();
          return MaterialApp(
              // navigatorKey: NavKey.navKey,
              // onGenerateRoute: (_) => null,
              debugShowCheckedModeBanner: false,
              title: 'Circum',
              builder: (context, child) {
                // ScreenUtil.setContext(context);
                child = botToastBuilder(context, child);
                return MediaQuery(
                  //Setting font does not change with system font size
                  data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
                  child: child,
                );
              },
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              navigatorObservers: [BotToastNavigatorObserver()],
              home: WillPopScope(
                onWillPop: () async =>
                    !await NavKey.navKey.currentState!.maybePop(),
                child: MultiBlocProvider(providers: [
                  BlocProvider<AuthBloc>(
                    create: (BuildContext context) =>
                        AuthBloc()..add(SortSessionState()),
                  ),
                  BlocProvider(
                    create: (context) => NavbarBloc(),
                  ),
                  BlocProvider<SendPackageBloc>(
                    create: (BuildContext context) => sendPackageBloc,
                  ),
                  BlocProvider<HistoryBloc>(
                    create: (BuildContext context) => HistoryBloc(),
                  ),
                  BlocProvider<SupportBloc>(
                    create: (BuildContext context) => SupportBloc(),
                  ),
                  BlocProvider<AccountBloc>(
                    create: (BuildContext context) => AccountBloc(),
                  ),
                ], child: const App()),
              ));
        });
  }
}

class SimpleBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    //   debugPrint('''
    //           Change: ${change.toString()},
    //           RuntimeType: ${bloc.runtimeType},
    //           ''');
  }

  @override
  void onEvent(Bloc bloc, Object? event) {
    super.onEvent(bloc, event);
    // print(event);
    // print(bloc);
  }

  @override
  void onTransition(Bloc bloc, Transition transition) {
    super.onTransition(bloc, transition);
    // debugPrint('$transition');
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    // debugPrint('$error');
    super.onError(bloc, error, stackTrace);
  }
}
