import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'app/account/bloc/account_bloc.dart';
import 'app/authentication/bloc/auth_bloc.dart';
import 'app/authentication/view/index_page.dart';
import 'app/bottom_nav/bloc/navbar_bloc.dart';
import 'app/bottom_nav/view/app_nav.dart';
import 'app/history/bloc/history_bloc.dart';
import 'app/onboarding/view/onboarding.dart';
import 'app/send_package/bloc/send_package_bloc.dart';
import 'app/support/bloc/support_bloc.dart';
import 'main.dart';
import 'utils/app_state/app_state.dart';
import 'utils/theme/theme.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final AuthBloc _authBloc;
  late final NavbarBloc _navbarBloc;
  late final HistoryBloc _historyBloc;
  late final SupportBloc _supportBloc;

  @override
  void initState() {
    super.initState();
    _authBloc = AuthBloc()..add(SortSessionState());
    _navbarBloc = NavbarBloc();
    _historyBloc = HistoryBloc();
    _supportBloc = SupportBloc();
  }

  @override
  void dispose() {
    _authBloc.close();
    _navbarBloc.close();
    _historyBloc.close();
    _supportBloc.close();
    sendPackageBloc.close();
    accountBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: _authBloc),
        BlocProvider<NavbarBloc>.value(value: _navbarBloc),
        BlocProvider<SendPackageBloc>.value(value: sendPackageBloc),
        BlocProvider<AccountBloc>.value(value: accountBloc),
        BlocProvider<HistoryBloc>.value(value: _historyBloc),
        BlocProvider<SupportBloc>.value(value: _supportBloc),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Circum',
            theme: ThemeData(
              scaffoldBackgroundColor: AppColors.secondary,
              fontFamily: 'Helvetica',
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.primary,
                brightness: Brightness.dark,
              ),
              useMaterial3: false,
            ),
            home: const _SessionGate(),
          );
        },
      ),
    );
  }
}

class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        switch (state.currentState) {
          case AppState.authenticated:
            return AppNavView();
          case AppState.unauthenticated:
            return const OnboardingView();
          case AppState.unknownSessionState:
          default:
            return const IndexPage();
        }
      },
    );
  }
}
