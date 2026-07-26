import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'design_system/sender_design_system.dart';

enum SenderTextSize { small, standard, large, extraLarge }

enum SenderDeliveryAlertLevel { normal, persistent, extraLoud }

enum SenderColourVisionMode { off, protanopia, deuteranopia, tritanopia }

@immutable
class SenderAccessibilitySettings {
  final SenderTextSize textSize;
  final bool highContrast;
  final bool reduceMotion;
  final bool largerTouchTargets;
  final bool hapticFeedback;
  final bool confirmBeforePayment;
  final bool voiceGuidance;
  final bool readNotifications;
  final SenderDeliveryAlertLevel deliveryAlerts;
  final bool announceRiderArrival;
  final bool announceDeliveryComplete;
  final SenderColourVisionMode colourVisionMode;
  final bool flashDeliveryAlerts;
  final bool leftHandedMode;

  const SenderAccessibilitySettings({
    this.textSize = SenderTextSize.standard,
    this.highContrast = false,
    this.reduceMotion = false,
    this.largerTouchTargets = false,
    this.hapticFeedback = true,
    this.confirmBeforePayment = false,
    this.voiceGuidance = false,
    this.readNotifications = false,
    this.deliveryAlerts = SenderDeliveryAlertLevel.normal,
    this.announceRiderArrival = true,
    this.announceDeliveryComplete = true,
    this.colourVisionMode = SenderColourVisionMode.off,
    this.flashDeliveryAlerts = false,
    this.leftHandedMode = false,
  });

  double get textScale => switch (textSize) {
        SenderTextSize.small => .9,
        SenderTextSize.standard => 1,
        SenderTextSize.large => 1.15,
        SenderTextSize.extraLarge => 1.3,
      };

  factory SenderAccessibilitySettings.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    T enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
      final value = '${raw ?? ''}';
      return values.where((item) => item.name == value).firstOrNull ?? fallback;
    }

    return SenderAccessibilitySettings(
      textSize: enumValue(
          SenderTextSize.values, data['textSize'], SenderTextSize.standard),
      highContrast: data['highContrast'] == true,
      reduceMotion: data['reduceMotion'] == true,
      largerTouchTargets: data['largerTouchTargets'] == true,
      hapticFeedback: data['hapticFeedback'] != false,
      confirmBeforePayment: data['confirmBeforePayment'] == true,
      voiceGuidance: data['voiceGuidance'] == true,
      readNotifications: data['readNotifications'] == true,
      deliveryAlerts: enumValue(SenderDeliveryAlertLevel.values,
          data['deliveryAlerts'], SenderDeliveryAlertLevel.normal),
      announceRiderArrival: data['announceRiderArrival'] != false,
      announceDeliveryComplete: data['announceDeliveryComplete'] != false,
      colourVisionMode: enumValue(SenderColourVisionMode.values,
          data['colourVisionMode'], SenderColourVisionMode.off),
      flashDeliveryAlerts: data['flashDeliveryAlerts'] == true,
      leftHandedMode: data['leftHandedMode'] == true,
    );
  }

  Map<String, Object> toMap() => {
        'textSize': textSize.name,
        'highContrast': highContrast,
        'reduceMotion': reduceMotion,
        'largerTouchTargets': largerTouchTargets,
        'hapticFeedback': hapticFeedback,
        'confirmBeforePayment': confirmBeforePayment,
        'voiceGuidance': voiceGuidance,
        'readNotifications': readNotifications,
        'deliveryAlerts': deliveryAlerts.name,
        'announceRiderArrival': announceRiderArrival,
        'announceDeliveryComplete': announceDeliveryComplete,
        'colourVisionMode': colourVisionMode.name,
        'flashDeliveryAlerts': flashDeliveryAlerts,
        'leftHandedMode': leftHandedMode,
      };

  SenderAccessibilitySettings copyWith({
    SenderTextSize? textSize,
    bool? highContrast,
    bool? reduceMotion,
    bool? largerTouchTargets,
    bool? hapticFeedback,
    bool? confirmBeforePayment,
    bool? voiceGuidance,
    bool? readNotifications,
    SenderDeliveryAlertLevel? deliveryAlerts,
    bool? announceRiderArrival,
    bool? announceDeliveryComplete,
    SenderColourVisionMode? colourVisionMode,
    bool? flashDeliveryAlerts,
    bool? leftHandedMode,
  }) =>
      SenderAccessibilitySettings(
        textSize: textSize ?? this.textSize,
        highContrast: highContrast ?? this.highContrast,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        largerTouchTargets: largerTouchTargets ?? this.largerTouchTargets,
        hapticFeedback: hapticFeedback ?? this.hapticFeedback,
        confirmBeforePayment: confirmBeforePayment ?? this.confirmBeforePayment,
        voiceGuidance: voiceGuidance ?? this.voiceGuidance,
        readNotifications: readNotifications ?? this.readNotifications,
        deliveryAlerts: deliveryAlerts ?? this.deliveryAlerts,
        announceRiderArrival: announceRiderArrival ?? this.announceRiderArrival,
        announceDeliveryComplete:
            announceDeliveryComplete ?? this.announceDeliveryComplete,
        colourVisionMode: colourVisionMode ?? this.colourVisionMode,
        flashDeliveryAlerts: flashDeliveryAlerts ?? this.flashDeliveryAlerts,
        leftHandedMode: leftHandedMode ?? this.leftHandedMode,
      );
}

abstract class SenderAccessibilityRepository {
  Stream<SenderAccessibilitySettings> watch();
  Future<void> save(SenderAccessibilitySettings settings);
}

class FirebaseSenderAccessibilityRepository
    implements SenderAccessibilityRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  FirebaseSenderAccessibilityRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _profile {
    final user = auth.currentUser;
    if (user == null) throw StateError('Sign in to manage accessibility.');
    return firestore.collection('users').doc(user.uid);
  }

  @override
  Stream<SenderAccessibilitySettings> watch() {
    return Stream<SenderAccessibilitySettings>.multi((output) {
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? profile;
      final authChanges = auth.authStateChanges().listen((user) {
        unawaited(profile?.cancel());
        if (user == null) {
          output.add(const SenderAccessibilitySettings());
          return;
        }
        profile =
            firestore.collection('users').doc(user.uid).snapshots().listen(
          (snapshot) {
            final data = snapshot.data();
            output.add(SenderAccessibilitySettings.fromMap(
              data?['accessibilitySettings'] as Map<String, dynamic>?,
            ));
          },
          onError: output.addError,
        );
      }, onError: output.addError);
      output.onCancel = () async {
        await authChanges.cancel();
        await profile?.cancel();
      };
    });
  }

  @override
  Future<void> save(SenderAccessibilitySettings settings) => _profile.set({
        'accessibilitySettings': settings.toMap(),
        'accessibilityUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

class SenderAccessibilityController extends ChangeNotifier {
  final SenderAccessibilityRepository repository;
  final FlutterTts tts;
  StreamSubscription<SenderAccessibilitySettings>? _subscription;
  Timer? _flashTimer;
  SenderAccessibilitySettings settings;
  bool loading = true;
  bool saving = false;
  String? error;
  bool flashVisible = false;
  String? persistentAlert;

  SenderAccessibilityController({
    required this.repository,
    FlutterTts? tts,
    this.settings = const SenderAccessibilitySettings(),
  }) : tts = tts ?? FlutterTts();

  void start() {
    _subscription ??= repository.watch().listen((value) {
      settings = value;
      loading = false;
      error = null;
      notifyListeners();
    }, onError: (Object failure) {
      loading = false;
      error = 'Accessibility settings could not be loaded.';
      notifyListeners();
    });
  }

  Future<void> update(SenderAccessibilitySettings next) async {
    final previous = settings;
    settings = next;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await repository.save(next);
    } catch (_) {
      settings = previous;
      error = 'Your accessibility change could not be saved.';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> reset() => update(const SenderAccessibilitySettings());

  Future<void> haptic(SenderFeedbackEvent event) async {
    if (!settings.hapticFeedback) return;
    switch (event) {
      case SenderFeedbackEvent.error:
        await HapticFeedback.vibrate();
      case SenderFeedbackEvent.riderArrived:
      case SenderFeedbackEvent.deliveryCompleted:
        await HapticFeedback.heavyImpact();
      case SenderFeedbackEvent.bookingCompleted:
      case SenderFeedbackEvent.paymentCompleted:
      case SenderFeedbackEvent.riderAccepted:
        await HapticFeedback.mediumImpact();
    }
  }

  Future<void> announceDelivery(SenderDeliveryAnnouncement event) async {
    if (!settings.voiceGuidance) return;
    if (event == SenderDeliveryAnnouncement.riderArrived &&
        !settings.announceRiderArrival) {
      return;
    }
    if (event == SenderDeliveryAnnouncement.deliveryCompleted &&
        !settings.announceDeliveryComplete) {
      return;
    }
    final message = event.message;
    await _speak(message);
    _signalVisualAlert(message);
  }

  Future<void> announceNotification(String message) async {
    if (!settings.readNotifications || message.trim().isEmpty) return;
    await _speak(message);
    _signalVisualAlert(message);
  }

  Future<void> _speak(String message) async {
    try {
      await tts.setVolume(1);
      await tts.setSpeechRate(
        settings.deliveryAlerts == SenderDeliveryAlertLevel.extraLoud
            ? .42
            : .5,
      );
      await tts.speak(message);
    } on MissingPluginException {
      // Unsupported preview platforms retain visual and haptic alerts.
    } on PlatformException {
      // A device speech-service failure must not interrupt delivery tracking.
    }
  }

  void _signalVisualAlert(String message) {
    if (settings.flashDeliveryAlerts) {
      flashVisible = true;
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 220), () {
        flashVisible = false;
        notifyListeners();
      });
    }
    if (settings.deliveryAlerts == SenderDeliveryAlertLevel.persistent) {
      persistentAlert = message;
    }
    notifyListeners();
  }

  void acknowledgeAlert() {
    persistentAlert = null;
    unawaited(_stopSpeech());
    notifyListeners();
  }

  Future<void> _stopSpeech() async {
    try {
      await tts.stop();
    } on MissingPluginException {
      // Speech is unavailable only on unsupported preview/test platforms.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _flashTimer?.cancel();
    unawaited(_stopSpeech());
    super.dispose();
  }
}

enum SenderFeedbackEvent {
  bookingCompleted,
  paymentCompleted,
  riderAccepted,
  riderArrived,
  deliveryCompleted,
  error,
}

enum SenderDeliveryAnnouncement {
  riderAccepted('Circum Rider accepted your delivery.'),
  riderArrived('Your Circum Rider has arrived.'),
  pickupComplete('Pickup complete.'),
  deliveryCompleted('Your delivery has been completed.'),
  giftDelivered('Gift delivered.'),
  healthDelivered('Health+ delivery completed.');

  final String message;
  const SenderDeliveryAnnouncement(this.message);
}

class SenderAccessibilityScope
    extends InheritedNotifier<SenderAccessibilityController> {
  const SenderAccessibilityScope({
    super.key,
    required SenderAccessibilityController controller,
    required super.child,
  }) : super(notifier: controller);

  static SenderAccessibilityController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SenderAccessibilityScope>()
      ?.notifier;

  static SenderAccessibilityController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'SenderAccessibilityScope is missing.');
    return controller!;
  }
}

class SenderAccessibilityHost extends StatefulWidget {
  final Widget child;
  final SenderAccessibilityRepository? repository;
  final SenderAccessibilityController? controller;

  const SenderAccessibilityHost({
    super.key,
    required this.child,
    this.repository,
    this.controller,
  });

  @override
  State<SenderAccessibilityHost> createState() =>
      _SenderAccessibilityHostState();
}

class _SenderAccessibilityHostState extends State<SenderAccessibilityHost> {
  late final SenderAccessibilityController _controller = widget.controller ??
      SenderAccessibilityController(
        repository:
            widget.repository ?? FirebaseSenderAccessibilityRepository(),
      );
  late final bool _ownsController = widget.controller == null;

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SenderAccessibilityScope(
      controller: _controller,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final settings = _controller.settings;
          final media = MediaQuery.of(context);
          Widget result = MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(settings.textScale),
              disableAnimations: settings.reduceMotion,
              boldText: settings.highContrast || media.boldText,
            ),
            child: Theme(
              data: _accessibleTheme(Theme.of(context), settings),
              child: child!,
            ),
          );
          final matrix = _colourMatrix(settings);
          if (matrix != null) {
            result = ColorFiltered(
              colorFilter: ColorFilter.matrix(matrix),
              child: result,
            );
          }
          return Stack(
            children: [
              result,
              if (_controller.flashVisible)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: Color(0x55FFFFFF)),
                  ),
                ),
              if (_controller.persistentAlert case final message?)
                Positioned(
                  left: 16,
                  right: 16,
                  top: media.padding.top + 12,
                  child: Material(
                    color: const Color(0xFF10284F),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      title: Text(message),
                      trailing: TextButton(
                        onPressed: _controller.acknowledgeAlert,
                        child: const Text('Acknowledge'),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

ThemeData _accessibleTheme(
  ThemeData base,
  SenderAccessibilitySettings settings,
) {
  if (!settings.highContrast) {
    return base.copyWith(
      visualDensity: settings.largerTouchTargets
          ? const VisualDensity(horizontal: 1, vertical: 1)
          : base.visualDensity,
      materialTapTargetSize: settings.largerTouchTargets
          ? MaterialTapTargetSize.padded
          : base.materialTapTargetSize,
      pageTransitionsTheme: settings.reduceMotion
          ? const PageTransitionsTheme(builders: {
              TargetPlatform.android: _NoPageTransitionBuilder(),
              TargetPlatform.iOS: _NoPageTransitionBuilder(),
              TargetPlatform.macOS: _NoPageTransitionBuilder(),
              TargetPlatform.windows: _NoPageTransitionBuilder(),
              TargetPlatform.linux: _NoPageTransitionBuilder(),
            })
          : base.pageTransitionsTheme,
    );
  }

  const primary = Color(0xFF168BFF);
  const primaryText = Color(0xFFFFFFFF);
  const secondaryText = Color(0xFFE5E7EB);
  const disabledText = Color(0xFF9CA3AF);
  const cardBackground = Color(0xFA0C121C);
  const cardBorder = Color(0x2EFFFFFF);
  final scheme = base.colorScheme.copyWith(
    primary: primary,
    onPrimary: primaryText,
    surface: cardBackground,
    onSurface: primaryText,
    outline: const Color(0xFFBFD8FF),
    outlineVariant: cardBorder,
    secondary: const Color(0xFF60A5FA),
    onSecondary: primaryText,
  );
  return base.copyWith(
    colorScheme: scheme,
    textTheme: _highContrastTextTheme(base.textTheme),
    primaryTextTheme: _highContrastTextTheme(base.primaryTextTheme),
    iconTheme: base.iconTheme.copyWith(color: primaryText, size: 25),
    primaryIconTheme: base.primaryIconTheme.copyWith(color: primaryText),
    disabledColor: disabledText,
    focusColor: primary.withValues(alpha: .34),
    hoverColor: primary.withValues(alpha: .18),
    visualDensity: settings.largerTouchTargets
        ? const VisualDensity(horizontal: 1, vertical: 1)
        : base.visualDensity,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    dividerTheme: base.dividerTheme.copyWith(
      color: const Color(0xFFBFD8FF),
      thickness: 1.5,
    ),
    cardTheme: CardThemeData(
      color: cardBackground,
      shadowColor: Colors.black.withValues(alpha: .6),
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: cardBorder),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: primaryText,
        disabledBackgroundColor: const Color(0xFF273243),
        disabledForegroundColor: disabledText,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: primaryText,
        disabledBackgroundColor: const Color(0xFF273243),
        disabledForegroundColor: disabledText,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryText,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: Color(0xFFBFD8FF), width: 1.6),
        textStyle: const TextStyle(
          inherit: false,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFBFD8FF),
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(
          inherit: false,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : const Color(0xFFF8FAFC),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? primary
            : const Color(0xFF374151),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Color(0xFFBFD8FF)),
      trackOutlineWidth: const WidgetStatePropertyAll(1.4),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: cardBackground,
      labelStyle: const TextStyle(color: secondaryText),
      hintStyle: const TextStyle(color: disabledText),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: cardBorder, width: 1.3),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: primary, width: 2),
      ),
    ),
    pageTransitionsTheme: settings.reduceMotion
        ? const PageTransitionsTheme(builders: {
            TargetPlatform.android: _NoPageTransitionBuilder(),
            TargetPlatform.iOS: _NoPageTransitionBuilder(),
            TargetPlatform.macOS: _NoPageTransitionBuilder(),
            TargetPlatform.windows: _NoPageTransitionBuilder(),
            TargetPlatform.linux: _NoPageTransitionBuilder(),
          })
        : base.pageTransitionsTheme,
  );
}

TextTheme _highContrastTextTheme(TextTheme theme) => theme.copyWith(
      displayLarge: _highContrastTextStyle(theme.displayLarge, Colors.white),
      displayMedium: _highContrastTextStyle(theme.displayMedium, Colors.white),
      displaySmall: _highContrastTextStyle(theme.displaySmall, Colors.white),
      headlineLarge: _highContrastTextStyle(theme.headlineLarge, Colors.white),
      headlineMedium:
          _highContrastTextStyle(theme.headlineMedium, Colors.white),
      headlineSmall: _highContrastTextStyle(theme.headlineSmall, Colors.white),
      titleLarge: _highContrastTextStyle(theme.titleLarge, Colors.white),
      titleMedium: _highContrastTextStyle(theme.titleMedium, Colors.white),
      titleSmall: _highContrastTextStyle(theme.titleSmall, Colors.white),
      bodyLarge:
          _highContrastTextStyle(theme.bodyLarge, const Color(0xFFE5E7EB)),
      bodyMedium:
          _highContrastTextStyle(theme.bodyMedium, const Color(0xFFE5E7EB)),
      bodySmall:
          _highContrastTextStyle(theme.bodySmall, const Color(0xFFE5E7EB)),
      labelLarge:
          _highContrastTextStyle(theme.labelLarge, const Color(0xFFE5E7EB)),
      labelMedium:
          _highContrastTextStyle(theme.labelMedium, const Color(0xFFE5E7EB)),
      labelSmall:
          _highContrastTextStyle(theme.labelSmall, const Color(0xFF9CA3AF)),
    );

TextStyle? _highContrastTextStyle(TextStyle? style, Color color) {
  if (style == null) return null;
  return style.copyWith(
    color: color,
    fontWeight: _nextFontWeight(style.fontWeight),
    height: (style.height ?? 1.2) * 1.1,
  );
}

FontWeight _nextFontWeight(FontWeight? weight) {
  return switch (weight) {
    FontWeight.w100 => FontWeight.w200,
    FontWeight.w200 => FontWeight.w300,
    FontWeight.w300 => FontWeight.w400,
    FontWeight.w400 || null => FontWeight.w500,
    FontWeight.w500 => FontWeight.w600,
    FontWeight.w600 => FontWeight.w700,
    FontWeight.w700 => FontWeight.w800,
    FontWeight.w800 || FontWeight.w900 => FontWeight.w900,
    _ => FontWeight.w500,
  };
}

class _NoPageTransitionBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

List<double>? _colourMatrix(SenderAccessibilitySettings settings) {
  return switch (settings.colourVisionMode) {
    SenderColourVisionMode.off => null,
    SenderColourVisionMode.protanopia => const [
        .567,
        .433,
        0,
        0,
        0,
        .558,
        .442,
        0,
        0,
        0,
        0,
        .242,
        .758,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ],
    SenderColourVisionMode.deuteranopia => const [
        .625,
        .375,
        0,
        0,
        0,
        .7,
        .3,
        0,
        0,
        0,
        0,
        .3,
        .7,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ],
    SenderColourVisionMode.tritanopia => const [
        .95,
        .05,
        0,
        0,
        0,
        0,
        .433,
        .567,
        0,
        0,
        0,
        .475,
        .525,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ],
  };
}

Future<bool> confirmSenderPaymentIfRequired(
  BuildContext context, {
  required String paymentMethod,
  String? amount,
}) async {
  final controller = SenderAccessibilityScope.maybeOf(context);
  if (controller?.settings.confirmBeforePayment != true) return true;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm payment'),
          content: Text(
            amount == null
                ? 'Continue with $paymentMethod?'
                : 'Charge $amount using $paymentMethod?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm payment'),
            ),
          ],
        ),
      ) ??
      false;
}

class SenderAccessibilityView extends StatelessWidget {
  final VoidCallback? onOpenLanguage;

  const SenderAccessibilityView({super.key, this.onOpenLanguage});

  @override
  Widget build(BuildContext context) {
    final controller = SenderAccessibilityScope.of(context);
    final settings = controller.settings;
    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Accessibility', style: GoogleFonts.dmSerifDisplay()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          if (controller.error case final error?)
            _AccessibilityNotice(message: error),
          _Section(
            title: 'Display',
            children: [
              _ChoiceTile<SenderTextSize>(
                title: 'Text size',
                value: settings.textSize,
                labels: const {
                  SenderTextSize.small: 'Small',
                  SenderTextSize.standard: 'Default',
                  SenderTextSize.large: 'Large',
                  SenderTextSize.extraLarge: 'Extra Large',
                },
                onChanged: (value) =>
                    controller.update(settings.copyWith(textSize: value)),
              ),
              _SwitchTile(
                title: 'High contrast',
                subtitle: 'Strengthen text, controls, maps and timelines.',
                value: settings.highContrast,
                onChanged: (value) =>
                    controller.update(settings.copyWith(highContrast: value)),
              ),
              _SwitchTile(
                title: 'Reduce motion',
                subtitle: 'Reduce decorative movement and page transitions.',
                value: settings.reduceMotion,
                onChanged: (value) =>
                    controller.update(settings.copyWith(reduceMotion: value)),
              ),
            ],
          ),
          _Section(
            title: 'Interaction',
            children: [
              _SwitchTile(
                title: 'Larger touch targets',
                value: settings.largerTouchTargets,
                onChanged: (value) => controller
                    .update(settings.copyWith(largerTouchTargets: value)),
              ),
              _SwitchTile(
                title: 'Haptic feedback',
                value: settings.hapticFeedback,
                onChanged: (value) {
                  controller.update(settings.copyWith(hapticFeedback: value));
                  if (value) {
                    controller.haptic(SenderFeedbackEvent.paymentCompleted);
                  }
                },
              ),
              _SwitchTile(
                title: 'Confirm before payment',
                subtitle: 'Ask before charging any payment method.',
                value: settings.confirmBeforePayment,
                onChanged: (value) => controller
                    .update(settings.copyWith(confirmBeforePayment: value)),
              ),
            ],
          ),
          _Section(
            title: 'Voice & delivery',
            children: [
              _SwitchTile(
                title: 'Voice guidance',
                value: settings.voiceGuidance,
                onChanged: (value) =>
                    controller.update(settings.copyWith(voiceGuidance: value)),
              ),
              _SwitchTile(
                title: 'Read notifications',
                value: settings.readNotifications,
                onChanged: (value) => controller
                    .update(settings.copyWith(readNotifications: value)),
              ),
              _ChoiceTile<SenderDeliveryAlertLevel>(
                title: 'Delivery alerts',
                value: settings.deliveryAlerts,
                labels: const {
                  SenderDeliveryAlertLevel.normal: 'Normal',
                  SenderDeliveryAlertLevel.persistent: 'Persistent',
                  SenderDeliveryAlertLevel.extraLoud: 'Extra Loud',
                },
                onChanged: (value) =>
                    controller.update(settings.copyWith(deliveryAlerts: value)),
              ),
              _SwitchTile(
                title: 'Announce Circum Rider arrival',
                value: settings.announceRiderArrival,
                onChanged: (value) => controller
                    .update(settings.copyWith(announceRiderArrival: value)),
              ),
              _SwitchTile(
                title: 'Announce delivery complete',
                value: settings.announceDeliveryComplete,
                onChanged: (value) => controller
                    .update(settings.copyWith(announceDeliveryComplete: value)),
              ),
            ],
          ),
          _Section(
            title: 'Visual support',
            children: [
              _ChoiceTile<SenderColourVisionMode>(
                title: 'Colour blind support',
                value: settings.colourVisionMode,
                labels: const {
                  SenderColourVisionMode.off: 'Off',
                  SenderColourVisionMode.protanopia: 'Protanopia',
                  SenderColourVisionMode.deuteranopia: 'Deuteranopia',
                  SenderColourVisionMode.tritanopia: 'Tritanopia',
                },
                onChanged: (value) => controller
                    .update(settings.copyWith(colourVisionMode: value)),
              ),
              _SwitchTile(
                title: 'Flash screen for delivery alerts',
                value: settings.flashDeliveryAlerts,
                onChanged: (value) => controller
                    .update(settings.copyWith(flashDeliveryAlerts: value)),
              ),
            ],
          ),
          _Section(
            title: 'Navigation',
            children: [
              _SwitchTile(
                title: 'Left-handed mode',
                subtitle:
                    'Move one-handed controls to the left where supported.',
                value: settings.leftHandedMode,
                onChanged: (value) =>
                    controller.update(settings.copyWith(leftHandedMode: value)),
              ),
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: const Text('Language'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onOpenLanguage ?? () => _openLanguage(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reset accessibility settings?'),
                  content: const Text(
                      'All Circum accessibility preferences will return to their defaults.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await controller.reset();
            },
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset accessibility settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _openLanguage(BuildContext context) async {
    if (!kIsWeb && await openAppSettings()) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Language'),
        content: const Text(
          'Circum follows your device language. Change it in your device language settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(title,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
            ),
            AppGlassContainer(
              radius: AppTokens.radius16,
              padding: EdgeInsets.zero,
              surfaceColor: Colors.white.withValues(alpha: .06),
              borderColor: Colors.white.withValues(alpha: .12),
              child: Column(children: children),
            ),
          ],
        ),
      );
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => AppToggle(
        label: title,
        detail: subtitle,
        value: value,
        onChanged: onChanged,
      );
}

class _ChoiceTile<T> extends StatelessWidget {
  final String title;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;
  const _ChoiceTile({
    required this.title,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        subtitle: Text(labels[value] ?? ''),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: const Color(0xFF101A2D),
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in labels.entries)
                  ListTile(
                    title: Text(entry.value),
                    leading: Icon(
                      entry.key == value
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                    ),
                    onTap: () {
                      onChanged(entry.key);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
        ),
      );
}

class _AccessibilityNotice extends StatelessWidget {
  final String message;
  const _AccessibilityNotice({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: const Color(0xFF3D1D22),
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            leading: const Icon(Icons.error_outline_rounded),
            title: Text(message),
          ),
        ),
      );
}
