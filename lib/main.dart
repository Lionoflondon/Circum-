import 'package:circum/app/account/bloc/account_bloc.dart';
import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app.dart';
import 'app/authentication/bloc/auth_bloc.dart';
import 'app/bottom_nav/bloc/navbar_bloc.dart';
import 'app/home/bloc/home_bloc.dart';
import 'app/history/bloc/history_bloc.dart';
import 'app/ride_bloc/bloc/parcel_bloc.dart';
import 'app/support/bloc/support_bloc.dart';
import 'utils/nav/nav_key.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:bot_toast/bot_toast.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

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
                  BlocProvider<ParcelBloc>(
                      create: (BuildContext context) => ParcelBloc()),
                  BlocProvider<HomeBloc>(
                    create: (BuildContext context) => HomeBloc(),
                  ),
                  BlocProvider<SendPackageBloc>(
                    create: (BuildContext context) => SendPackageBloc(),
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
