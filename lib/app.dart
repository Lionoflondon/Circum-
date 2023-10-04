import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../app/authentication/bloc/auth_bloc.dart';
import '../app/onboarding/onboarding.dart';
import 'utils/nav/nav_key.dart';

import '../app/authentication/view/index.dart';
import '../app/bottom_nav/view/app_nav.dart';
import 'utils/app_state/index.dart';

class App extends StatelessWidget {
  const App({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Navigator(
        key: NavKey.navKey,
        pages: [
          // Unknown app state
          if (state.currentState == AppState.unknownSessionState)
            const MaterialPage(child: IndexPage()),

          // Unauthenticated app state
          if (state.currentState == AppState.unauthenticated) ...[
            const MaterialPage(
              child: OnboardingView(),
            ),
          ],

          // Authenticated app state
          if (state.currentState == AppState.authenticated)
            MaterialPage(child: AppNavView()),
        ],
        onPopPage: (route, result) {
          // route.didPop(result);

          if (!route.didPop(result)) return false;
          return true;
        },
      );
    });
  }
}
