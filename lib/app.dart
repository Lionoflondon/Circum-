import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'app/account/bloc/account_bloc.dart';
import 'app/authentication/bloc/auth_bloc.dart';
import 'app/authentication/view/index_page.dart';
import 'app/authentication/view/add_details.dart';
import 'app/history/bloc/history_bloc.dart';
import 'app/onboarding/view/onboarding.dart';
import 'app/sender_mobile/sender_mobile_home.dart';
import 'app/sender_mobile/sender_profile_authority.dart';
import 'app/send_package/bloc/send_package_bloc.dart';
import 'app/support/bloc/support_bloc.dart';
import 'utils/app_state/app_state.dart';
import 'utils/theme/theme.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final AuthBloc _authBloc;
  late final SendPackageBloc _sendPackageBloc;
  late final AccountBloc _accountBloc;
  late final HistoryBloc _historyBloc;
  late final SupportBloc _supportBloc;

  @override
  void initState() {
    super.initState();
    _authBloc = AuthBloc()..add(SortSessionState());
    _sendPackageBloc = SendPackageBloc();
    _accountBloc = AccountBloc();
    _historyBloc = HistoryBloc();
    _supportBloc = SupportBloc();
  }

  @override
  void dispose() {
    _authBloc.close();
    _historyBloc.close();
    _supportBloc.close();
    _sendPackageBloc.close();
    _accountBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: _authBloc),
        BlocProvider<SendPackageBloc>.value(value: _sendPackageBloc),
        BlocProvider<AccountBloc>.value(value: _accountBloc),
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
            routes: {
              '/sender/mobile': (_) => const SenderMobileHome(),
            },
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
            return const _SenderRestorationGate();
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

class _SenderRestorationGate extends StatefulWidget {
  const _SenderRestorationGate();

  @override
  State<_SenderRestorationGate> createState() => _SenderRestorationGateState();
}

class _SenderRestorationGateState extends State<_SenderRestorationGate> {
  late Future<SenderProfileAuthoritySnapshot> _profile;

  @override
  void initState() {
    super.initState();
    _profile = SenderProfileAuthority().load('session.restore');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SenderProfileAuthoritySnapshot>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const IndexPage();
        }
        if (snapshot.hasError) {
          return const IndexPage();
        }
        final data = snapshot.data?.data ?? const <String, dynamic>{};
        final name = '${data['displayName'] ?? data['fullName'] ?? data['name'] ?? ''}'.trim();
        if (name.isEmpty) return const AddDetailsView();
        return const SenderMobileHome(previewAuthEnabled: true);
      },
    );
  }
}
