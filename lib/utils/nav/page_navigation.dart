import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import './nav_key.dart';

class PageNavigation {
  slideLeft(Widget page) {
    return NavKey.navKey.currentState?.push(
      PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          opaque: false,
          pageBuilder: (BuildContext context, _, __) {
            return page;
          },
          transitionsBuilder: (context, animation, anotherAnimation, child) {
            return SlideTransition(
              position:
                  Tween(begin: const Offset(1.0, 0.0), end: Offset(0.0, 0.0))
                      .animate(animation),
              child: child,
            );
          }),
    );
  }

  slideLeftAndReplace(Widget page) {
    return NavKey.navKey.currentState?.pushReplacement(
      PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          opaque: false,
          pageBuilder: (BuildContext context, _, __) {
            return page;
          },
          transitionsBuilder: (context, animation, anotherAnimation, child) {
            return SlideTransition(
              position: Tween(begin: Offset(1.0, 0.0), end: Offset(0.0, 0.0))
                  .animate(animation),
              child: child,
            );
          }),
    );
  }

  slideLeftAndRemoveUntil(Widget page) {
    return NavKey.navKey.currentState?.pushAndRemoveUntil(
        PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 200),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            opaque: false,
            pageBuilder: (BuildContext context, _, __) {
              // return EmptySchedule();
              return page;
            },
            transitionsBuilder: (context, animation, anotherAnimation, child) {
              return SlideTransition(
                position: Tween(
                        begin: const Offset(1.0, 0.0),
                        end: const Offset(0.0, 0.0))
                    .animate(animation),
                child: child,
              );
            }),
        (Route<dynamic> route) => false);
  }

  slideUp(Widget page) {
    return NavKey.navKey.currentState?.push(
      PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 100),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          opaque: false,
          pageBuilder: (BuildContext context, _, __) {
            return page;
          },
          transitionsBuilder: (context, animation, anotherAnimation, child) {
            return SlideTransition(
              position: Tween(
                      begin: const Offset(0.0, 1.0),
                      end: const Offset(0.0, 0.0))
                  .animate(animation),
              child: child,
            );
          }),
    );
  }
}
