import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session_domain.dart';
import 'session_flow_bootstrap.dart';
import 'story_prompt_demo.dart';

const _paper = Color(0xFFF3F3EF);
const _offWhite = Color(0xFFF5F3EB);
const _offWhiteBorder = Color(0xFFE6E2D6);
const _ink = Color(0xFF070707);
const _panelColor = Color(0xEAF5F3EB);
const _panelStroke = Color(0xFFD8CCBC);
const _primaryButton = Color(0xFF191512);
const _secondaryButtonText = Color(0xFF2E2822);
const _textBoxTextColor = Color(0xFF6B665E);
const _textBoxSubtleTextColor = Color(0xFF827B73);
const _backgroundImageAsset = 'assets/chat_gpt_texture.png';
const _gameViewportSize = Size(390, 844);
const _screenContentPadding = EdgeInsets.fromLTRB(20, 40, 20, 20);
const _demoSessionId = 'demo-public';
const _waitingQuoteCardWidth = 248.0;
const _waitingQuoteCardHeight = 322.0;
const _waitingQuoteCanvasWidth = 294.0;
const _waitingQuoteCanvasHeight = 360.0;
const _gamePromptCardWidth = 248.0;
const _gamePromptCardHeight = 322.0;
const _gamePromptCanvasWidth = 294.0;
const _gamePromptCanvasHeight = 360.0;
const _cardDropDuration = Duration(milliseconds: 3800);
const _initialInteractionRound = 1;
const _finalInteractionRound = 2;
const _continueVoteRound = 2;

const _chatGptTextureAssets = [
  'assets/Polaroid1.png',
  'assets/Polaroid2.png',
  'assets/Polaroid3.png',
  'assets/Polaroid4.png',
];

String _textureAssetForSeed(String seed) {
  final rng = Random(seed.hashCode & 0x7fffffff);
  return _chatGptTextureAssets[rng.nextInt(_chatGptTextureAssets.length)];
}

Color _toneColorForSeed(String seed) {
  final rng = Random(seed.hashCode & 0x7fffffff);
  return HSLColor.fromAHSL(1, rng.nextDouble() * 360, 0.46, 0.52).toColor();
}

int? _targetTextureDecodeWidth({
  required BoxConstraints constraints,
  required double devicePixelRatio,
  required double scale,
}) {
  final boundedWidth = constraints.hasBoundedWidth && constraints.maxWidth > 0;
  final boundedHeight =
      constraints.hasBoundedHeight && constraints.maxHeight > 0;
  if (!boundedWidth && !boundedHeight) return null;

  final logicalMaxDimension = max(
    boundedWidth ? constraints.maxWidth : 0,
    boundedHeight ? constraints.maxHeight : 0,
  );
  final sampledDimension = logicalMaxDimension / max(scale, 1);
  final paddedPhysicalDimension =
      (sampledDimension * devicePixelRatio * 1.35).ceil();
  return paddedPhysicalDimension.clamp(192, 768).toInt();
}

TextStyle? _scaledTextStyle(
  TextStyle? style, {
  double scaleFactor = 1.24,
  double? fontSize,
  FontWeight? fontWeight,
  Color color = _ink,
}) {
  if (style == null) return null;
  return style.copyWith(
    color: color,
    fontSize: fontSize ??
        (style.fontSize == null ? null : style.fontSize! * scaleFactor),
    fontWeight: fontWeight ?? style.fontWeight,
  );
}

TextTheme _buildAppTextTheme() {
  final baseTextTheme = Typography.material2021(
    platform: defaultTargetPlatform,
  ).black;
  return baseTextTheme.copyWith(
    displayLarge: _scaledTextStyle(baseTextTheme.displayLarge),
    displayMedium: _scaledTextStyle(baseTextTheme.displayMedium),
    displaySmall: _scaledTextStyle(baseTextTheme.displaySmall),
    headlineLarge: _scaledTextStyle(baseTextTheme.headlineLarge),
    headlineMedium: _scaledTextStyle(baseTextTheme.headlineMedium),
    headlineSmall: _scaledTextStyle(
      baseTextTheme.headlineSmall,
      fontSize: 30,
      fontWeight: FontWeight.w700,
    ),
    titleLarge: _scaledTextStyle(
      baseTextTheme.titleLarge,
      fontSize: 24,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: _scaledTextStyle(baseTextTheme.titleMedium),
    titleSmall: _scaledTextStyle(baseTextTheme.titleSmall),
    bodyLarge: _scaledTextStyle(baseTextTheme.bodyLarge, fontSize: 18),
    bodyMedium: _scaledTextStyle(baseTextTheme.bodyMedium, fontSize: 16),
    bodySmall: _scaledTextStyle(baseTextTheme.bodySmall),
    labelLarge: _scaledTextStyle(
      baseTextTheme.labelLarge,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
    labelMedium: _scaledTextStyle(baseTextTheme.labelMedium),
    labelSmall: _scaledTextStyle(baseTextTheme.labelSmall),
  );
}

const _backgroundTextShadows = [
  Shadow(
    color: Color(0xB3000000),
    blurRadius: 14,
    offset: Offset(0, 2),
  ),
];

TextStyle _textOnBackgroundStyle(
  TextStyle baseStyle, {
  FontWeight? fontWeight,
  double? fontSize,
  double? height,
}) {
  return baseStyle.copyWith(
    color: _offWhite,
    fontWeight: fontWeight ?? baseStyle.fontWeight ?? FontWeight.w600,
    fontSize: fontSize ?? baseStyle.fontSize,
    height: height ?? baseStyle.height,
    shadows: _backgroundTextShadows,
  );
}

TextStyle _backgroundHeadlineStyle(BuildContext context) {
  return _textOnBackgroundStyle(
    Theme.of(context).textTheme.headlineSmall ?? const TextStyle(fontSize: 30),
    fontWeight: FontWeight.w800,
    height: 1.08,
  );
}

TextStyle _backgroundBodyStyle(
  BuildContext context, {
  FontWeight fontWeight = FontWeight.w600,
  double height = 1.35,
}) {
  return _textOnBackgroundStyle(
    Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 16),
    fontWeight: fontWeight,
    height: height,
  );
}

double _largestFittingFontSize({
  required double maxWidth,
  required double maxHeight,
  required InlineSpan Function(double fontSize) textBuilder,
  double maxFont = 30,
  double minFont = 12,
  TextAlign textAlign = TextAlign.center,
}) {
  if (!maxWidth.isFinite ||
      !maxHeight.isFinite ||
      maxWidth <= 0 ||
      maxHeight <= 0) {
    return minFont;
  }

  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textAlign: textAlign,
  );

  for (var size = maxFont; size >= minFont; size -= 1) {
    painter.text = textBuilder(size);
    painter.layout(maxWidth: maxWidth);
    if (painter.size.height <= maxHeight && painter.size.width <= maxWidth) {
      return size;
    }
  }

  return minFont;
}

final ValueNotifier<_FatalAppError?> _fatalErrorNotifier =
    ValueNotifier<_FatalAppError?>(null);

void _logAppEvent(String message) {
  debugPrint('[You Me] $message');
}

class _FatalAppError {
  const _FatalAppError({
    required this.message,
    required this.stackTrace,
  });

  final String message;
  final StackTrace stackTrace;
}

void _recordFatalError(
  Object error,
  StackTrace stackTrace, {
  bool dumpToConsole = true,
}) {
  if (dumpToConsole) {
    final details = FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'you me',
    );
    FlutterError.dumpErrorToConsole(details, forceReport: true);
  }

  _logAppEvent('Fatal error: $error');
  debugPrintStack(stackTrace: stackTrace);

  _fatalErrorNotifier.value = _FatalAppError(
    message: error.toString(),
    stackTrace: stackTrace,
  );
}

void _clearFatalError([String reason = 'manual clear']) {
  if (_fatalErrorNotifier.value == null) return;
  _logAppEvent('Clearing fatal error state: $reason');
  _fatalErrorNotifier.value = null;
}

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _clearFatalError('app startup');
    _logAppEvent('main() start');

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _recordFatalError(
        details.exception,
        details.stack ?? StackTrace.current,
        dumpToConsole: false,
      );
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      _recordFatalError(error, stackTrace);
      return true;
    };

    ErrorWidget.builder = (details) {
      _recordFatalError(
        details.exception,
        details.stack ?? StackTrace.current,
      );
      return const _FatalErrorFallback();
    };

    await AppFirebase.initialize();
    _logAppEvent('Firebase configured: ${AppFirebase.isConfigured}');
    runApp(const MiniApp());
  }, (error, stackTrace) {
    _recordFatalError(error, stackTrace);
  });
}

class AppFirebase {
  static bool isConfigured = false;

  static Future<void> initialize() async {
    try {
      final hasDefault = Firebase.apps.isNotEmpty;
      if (!hasDefault) {
        final options = _webOptionsFromDefines();
        if (kIsWeb && options == null) {
          isConfigured = false;
          return;
        }
        await Firebase.initializeApp(options: options);
      }
      isConfigured = true;
    } catch (_) {
      isConfigured = false;
    }
  }

  static FirebaseOptions? _webOptionsFromDefines() {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

    if (apiKey.isEmpty ||
        appId.isEmpty ||
        senderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }

    const authDomain = String.fromEnvironment(
      'FIREBASE_AUTH_DOMAIN',
      defaultValue: 'youmedev-feab4.firebaseapp.com',
    );
    const storageBucket = String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
      defaultValue: 'youmedev-feab4.appspot.com',
    );

    return const FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      authDomain: authDomain,
      storageBucket: storageBucket,
    );
  }
}

class MiniApp extends StatelessWidget {
  const MiniApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appTextTheme = _buildAppTextTheme();
    return ValueListenableBuilder<_FatalAppError?>(
      valueListenable: _fatalErrorNotifier,
      builder: (context, fatalError, _) {
        return MaterialApp(
          title: 'You Me',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: _ink,
              brightness: Brightness.light,
            ).copyWith(
              primary: _ink,
              surface: _paper,
              onSurface: _ink,
              onPrimary: Colors.white,
            ),
            scaffoldBackgroundColor: Colors.transparent,
            textTheme: appTextTheme,
            primaryTextTheme: appTextTheme,
            cardTheme: CardThemeData(
              color: _offWhite,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: _panelStroke),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: _primaryButton,
                foregroundColor: _offWhite,
                minimumSize: const Size(0, 50),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: _secondaryButtonText,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: _secondaryButtonText,
                side: const BorderSide(color: _panelStroke),
                minimumSize: const Size(0, 46),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              fillColor: _offWhite,
              filled: true,
              labelStyle: const TextStyle(color: _ink),
              floatingLabelStyle: const TextStyle(color: _ink),
              hintStyle: const TextStyle(color: Color(0xFF5F564E)),
              counterStyle: const TextStyle(color: _textBoxSubtleTextColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _panelStroke),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _panelStroke),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _primaryButton, width: 1.5),
              ),
            ),
            iconTheme: const IconThemeData(color: _ink),
          ),
          home: fatalError == null
              ? const SessionFlowPage()
              : FatalErrorPage(error: fatalError),
        );
      },
    );
  }
}

class _FatalErrorFallback extends StatelessWidget {
  const _FatalErrorFallback();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: _FatalErrorShell(
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: _FatalErrorContent(),
        ),
      ),
    );
  }
}

class FatalErrorPage extends StatelessWidget {
  const FatalErrorPage({super.key, this.error});

  final _FatalAppError? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _FatalErrorShell(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _FatalErrorContent(error: error),
        ),
      ),
    );
  }
}

class _FatalErrorShell extends StatelessWidget {
  const _FatalErrorShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0E151D),
                  Color(0xFF1D2430),
                  Color(0xFF302322),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -80,
          left: -40,
          child: _ErrorGlow(
            diameter: 220,
            color: const Color(0xFFB46A4D).withValues(alpha: 0.28),
          ),
        ),
        Positioned(
          right: -70,
          bottom: -30,
          child: _ErrorGlow(
            diameter: 260,
            color: const Color(0xFF6C7C96).withValues(alpha: 0.22),
          ),
        ),
        Center(child: child),
      ],
    );
  }
}

class _ErrorGlow extends StatelessWidget {
  const _ErrorGlow({
    required this.diameter,
    required this.color,
  });

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class _FatalErrorContent extends StatelessWidget {
  const _FatalErrorContent({this.error, this.showDebugDetails = true});

  final _FatalAppError? error;
  final bool showDebugDetails;

  @override
  Widget build(BuildContext context) {
    final fatalError = error ?? _fatalErrorNotifier.value;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _offWhite,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: const Color(0xFF221C17),
            width: 1.4,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 26,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF201A17),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'You Me',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFF6EBD8),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Error',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1D1917),
                  fontSize: 26,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "This isn't working, it's not you, it's us.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6F5340),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Refresh the page and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF51453C),
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
              if (showDebugDetails && kDebugMode && fatalError != null) ...[
                const SizedBox(height: 18),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _paper,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD8C3AA)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      fatalError.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6A5A4E),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => _clearFatalError('retry button'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF201A17),
                  foregroundColor: const Color(0xFFF6EBD8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum Stage { signup, waiting, matching, game, story, ended }

class SessionFlowServices {
  SessionFlowServices({
    RtdbService? rtdbService,
    FirestoreSignupService? firestoreSignupService,
    PromptCatalogService? promptCatalogService,
    SessionStateStore? sessionStateStore,
  })  : rtdbService = rtdbService ?? RtdbService(),
        firestoreSignupService =
            firestoreSignupService ?? FirestoreSignupService(),
        promptCatalogService = promptCatalogService ?? PromptCatalogService(),
        sessionStateStore = sessionStateStore ?? SessionStateStore();

  final RtdbService rtdbService;
  final FirestoreSignupService firestoreSignupService;
  final PromptCatalogService promptCatalogService;
  final SessionStateStore sessionStateStore;
}

class _SessionValidationResult {
  const _SessionValidationResult.valid()
      : isValid = true,
        error = null;

  const _SessionValidationResult.invalid()
      : isValid = false,
        error = null;

  const _SessionValidationResult.error(this.error) : isValid = false;

  final bool isValid;
  final Object? error;
}

class SessionFlowPage extends StatefulWidget {
  const SessionFlowPage({
    super.key,
    this.initialUri,
    this.services,
  });

  final Uri? initialUri;
  final SessionFlowServices? services;

  @override
  State<SessionFlowPage> createState() => _SessionFlowPageState();
}

class _SessionFlowPageState extends State<SessionFlowPage> {
  late final RtdbService _service;
  late final FirestoreSignupService _firestoreService;
  late final PromptCatalogService _promptCatalogService;
  late final SessionStateStore _sessionStore;
  late final Uri _initialUri;
  late final LaunchIntent _launchIntent;
  late final StoryPromptCatalogService _databaseStoryPromptCatalogService;
  late final _PreviewStoryRtdbService _previewStoryRtdbService;

  Stage _stage = Stage.signup;
  ScreenState _screenState = ScreenState.booting;
  String? _sessionId;
  String? _playerId;
  PlayerRecord? _player;
  SessionRecord? _session;
  String? _error;
  Timer? _poller;
  Timer? _bootstrapWatchdog;
  PromptCatalog? _promptCatalog;
  List<PlayerRecord> _mutualSeeAgainPlayers = const <PlayerRecord>[];
  bool _previewErrorMode = false;
  String? _lastBodyLogKey;

  static const _previewPromptSet = [
    PromptItem(
        id: 'preview-1',
        text: 'What is one thing that made you smile this week?'),
    PromptItem(
        id: 'preview-2',
        text:
            'If you could teleport anywhere for dinner tonight, where would you go?'),
    PromptItem(
        id: 'preview-3',
        text: 'What kind of vibe helps you feel most yourself on a date?'),
  ];

  static const _previewRoundPromptSet = [
    ..._previewPromptSet,
    storyModePromptItem,
  ];

  static const _previewLevelTwoPromptSet = [
    PromptItem(
        id: 'preview-4',
        text: 'What usually makes you feel comfortable with someone quickly?'),
    PromptItem(
        id: 'preview-5',
        text: 'What kind of connection are you hoping to find here tonight?'),
    PromptItem(
        id: 'preview-6',
        text:
            'What is something playful or unexpected people learn about you later?'),
  ];

  @override
  void initState() {
    super.initState();
    final services = widget.services;
    _service = services?.rtdbService ?? RtdbService();
    _firestoreService =
        services?.firestoreSignupService ?? FirestoreSignupService();
    _promptCatalogService =
        services?.promptCatalogService ?? PromptCatalogService();
    _sessionStore = services?.sessionStateStore ?? SessionStateStore();
    _initialUri = widget.initialUri ?? Uri.base;
    _launchIntent = LaunchIntent.fromUri(_initialUri);
    _databaseStoryPromptCatalogService =
        DatabaseStoryPromptCatalogService(rtdbService: _service);
    _previewStoryRtdbService = _PreviewStoryRtdbService();
    _sessionId = _launchIntent.sessionId;

    _logAppEvent(
      'SessionFlow init: intent=${_launchIntent.type.name}, sessionId=${_sessionId ?? '(none)'}, query=${_initialUri.query}, fragment=${_initialUri.fragment}',
    );

    if (_launchIntent.requiresBackend) {
      _bootstrapWatchdog = Timer(const Duration(seconds: 12), () {
        if (!mounted || _screenState != ScreenState.booting) return;
        _logAppEvent('Bootstrap watchdog expired');
        _showErrorScreen(
          'We connected to the session, but startup took too long. Please refresh and try again.',
        );
      });
    }

    unawaited(_bootstrapFromLaunchIntent());
  }

  Future<void> _bootstrapFromLaunchIntent() async {
    _logAppEvent('Bootstrap start');
    try {
      switch (_launchIntent.type) {
        case LaunchIntentType.none:
          _logAppEvent('Bootstrap -> no URL params, showing join screen');
          _showJoinScreen();
          return;
        case LaunchIntentType.preview:
          _logAppEvent('Bootstrap -> preview mode');
          _enableUiPreview();
          return;
        case LaunchIntentType.demo:
          _logAppEvent('Bootstrap -> demo mode');
          await _enableDemoMode();
          return;
        case LaunchIntentType.session:
          _logAppEvent('Bootstrap -> session link ${_launchIntent.sessionId}');
          await _attemptSessionJoin(
            _launchIntent.sessionId!,
            fatalOnFailure: true,
          );
          return;
      }
    } finally {
      _logAppEvent('Bootstrap complete');
      _bootstrapWatchdog?.cancel();
      if (!mounted || _screenState != ScreenState.booting) return;

      _logAppEvent(
        'Bootstrap fallback reached for intent ${_launchIntent.type.name}',
      );
      if (_launchIntent.requiresBackend) {
        _showErrorScreen(
          _error ??
              'Unable to complete startup for this session. Please refresh and try again.',
        );
      } else {
        _showJoinScreen(error: _error);
      }
    }
  }

  void _enableUiPreview() {
    _logAppEvent('Preview mode enabled');
    final previewPlayer = PlayerRecord(
      id: 'preview-player',
      name: 'Avery',
      phone: '0000000000',
      gender: '',
      sexualPreference: '',
      acceptedTermsAndGameTexts: true,
      acceptedPromoTexts: false,
      roundPreference: RoundPreference.playful,
      inviteCode: 'AB12',
      pairedWith: 'preview-partner',
      pairedRound: 1,
      currentPromptRound: 1,
      currentPromptIndex: 0,
      activeTurnPlayerId: 'preview-player',
      currentRoundPrompts:
          _previewRoundPromptSet.map((item) => item.id).toList(),
      askedPromptIds: _previewRoundPromptSet.map((item) => item.id).toList(),
      seeAgainPlayerIds: const ['preview-match-1'],
    );

    setState(() {
      _sessionId = _sessionId ?? 'AB12';
      _playerId = previewPlayer.id;
      _player = previewPlayer;
      _session = SessionRecord(status: 'started', round: 1);
      _stage = Stage.matching;
      _screenState = ScreenState.preview;
      _previewErrorMode = false;
      _error = null;
      _mutualSeeAgainPlayers = [
        PlayerRecord(
          id: 'preview-match-1',
          name: 'Taylor',
          phone: '',
          gender: '',
          sexualPreference: '',
          acceptedTermsAndGameTexts: true,
          acceptedPromoTexts: false,
          roundPreference: RoundPreference.openingUp,
          inviteCode: 'TG88',
        ),
      ];
      _promptCatalog = PromptCatalog(
        sets: {
          'preview': _previewRoundPromptSet,
          'icebreakers_level2': _previewLevelTwoPromptSet,
        },
        itemsById: {
          for (final item in [
            ..._previewRoundPromptSet,
            ..._previewLevelTwoPromptSet
          ])
            item.id: item,
        },
      );
    });
  }

  Future<void> _enableDemoMode() async {
    _sessionId ??= _demoSessionId;
    _logAppEvent('Demo mode enabled for session $_sessionId');

    try {
      _promptCatalog ??= await _promptCatalogService.loadDatingCatalog();
    } catch (_) {
      _promptCatalog ??= _buildFallbackPromptCatalog();
    }

    try {
      await _ensureBackendAuth();
      final session = await _service.ensureSessionStarted(_sessionId!);
      _logAppEvent(
        'Demo session ready: status=${session.status ?? '(none)'} round=${session.round ?? '(none)'}',
      );

      final restored = await _restoreSavedSession(_sessionId!);
      if (restored || !mounted) {
        return;
      }

      setState(() {
        _session = session;
        _player = null;
        _playerId = null;
        _error = null;
        _screenState = ScreenState.demoName;
      });
    } catch (error) {
      _handleSessionJoinFailure(
        _backendErrorMessage(
          fallback: 'Unable to start demo mode.',
          error: error,
        ),
        fatalOnFailure: true,
      );
    }
  }

  PromptCatalog _buildFallbackPromptCatalog() {
    return PromptCatalog(
      sets: {
        'icebreakers_level1': [_previewPromptSet[0]],
        'activities_level1': [_previewPromptSet[1]],
        'dating_questions_level1': [_previewPromptSet[2]],
        'icebreakers_level2': _previewLevelTwoPromptSet,
      },
      itemsById: {
        for (final item in [..._previewPromptSet, ..._previewLevelTwoPromptSet])
          item.id: item,
      },
    );
  }

  bool get _isLocalSandboxMode => _launchIntent.isLocal;

  ScreenState _screenStateForStage(Stage stage) {
    switch (stage) {
      case Stage.signup:
        return ScreenState.signup;
      case Stage.waiting:
        return ScreenState.waiting;
      case Stage.matching:
        return ScreenState.matching;
      case Stage.game:
        return ScreenState.game;
      case Stage.story:
        return ScreenState.game;
      case Stage.ended:
        return ScreenState.ended;
    }
  }

  void _showJoinScreen({String? error}) {
    if (!mounted) return;
    setState(() {
      _screenState = ScreenState.join;
      _sessionId = null;
      _playerId = null;
      _player = null;
      _session = null;
      _previewErrorMode = false;
      _error = error;
    });
  }

  void _showErrorScreen(String message) {
    if (!mounted) return;
    setState(() {
      _screenState = ScreenState.error;
      _sessionId = null;
      _playerId = null;
      _player = null;
      _session = null;
      _previewErrorMode = false;
      _error = message;
    });
  }

  void _showStageScreen(Stage stage) {
    _stage = stage;
    _screenState = _screenStateForStage(stage);
  }

  void _showLocalStage(Stage stage) {
    _stage = stage;
    _screenState = _launchIntent.type == LaunchIntentType.preview
        ? ScreenState.preview
        : _screenStateForStage(stage);
  }

  String _backendErrorMessage({
    required String fallback,
    required Object error,
  }) {
    final message = error.toString();
    final permissionDenied =
        message.toLowerCase().contains('permission denied');
    if (permissionDenied && !AppFirebase.isConfigured) {
      return '$fallback Firebase web config is missing from this build, so the app cannot authenticate to the backend.';
    }
    return '$fallback $error';
  }

  Future<void> _ensureBackendAuth() async {
    if (!AppFirebase.isConfigured) return;

    final existingUser = FirebaseAuth.instance.currentUser;
    if (existingUser != null) {
      _logAppEvent('Firebase auth already available: ${existingUser.uid}');
      await existingUser.getIdToken();
      return;
    }

    _logAppEvent('Signing in anonymously to Firebase');
    await FirebaseAuth.instance.signInAnonymously();
    _logAppEvent(
      'Anonymous Firebase auth ready: ${FirebaseAuth.instance.currentUser?.uid ?? '(missing uid)'}',
    );
  }

  Future<_SessionValidationResult> _validateSessionCode(
    String sessionCode,
  ) async {
    final trimmed = sessionCode.trim();
    if (trimmed.isEmpty) {
      return const _SessionValidationResult.invalid();
    }

    try {
      final session = await _service.fetchSession(trimmed);
      final status = session.status?.trim();
      if (status == null || status.isEmpty) {
        return const _SessionValidationResult.invalid();
      }
      return const _SessionValidationResult.valid();
    } catch (error) {
      return _SessionValidationResult.error(error);
    }
  }

  void _logBody(String key, String message) {
    if (_lastBodyLogKey == key) return;
    _lastBodyLogKey = key;
    _logAppEvent(message);
  }

  void _setPreviewStage(Stage stage) {
    if (_launchIntent.type != LaunchIntentType.preview) return;
    setState(() {
      _previewErrorMode = false;
      _screenState = ScreenState.preview;
      _stage = stage;
      switch (stage) {
        case Stage.signup:
          _session = SessionRecord(status: 'pending', round: 1);
          _player = null;
          _error = null;
          break;
        case Stage.waiting:
          _session = SessionRecord(status: 'waiting', round: 1);
          _player ??= _buildPreviewPlayer();
          _player!
            ..pairedWith = null
            ..pairedRound = null
            ..interactionRound = _initialInteractionRound
            ..continueVoteRound = null
            ..activeTurnPlayerId = null
            ..skipNextTurn = false
            ..currentPromptIndex = 0
            ..currentPromptRound = 1
            ..currentRoundPrompts =
                _previewRoundPromptSet.map((item) => item.id).toList();
          _error = null;
          break;
        case Stage.matching:
          _session = SessionRecord(status: 'started', round: 1);
          _player ??= _buildPreviewPlayer();
          _player!
            ..pairedWith = null
            ..pairedRound = null
            ..interactionRound = _initialInteractionRound
            ..continueVoteRound = null
            ..activeTurnPlayerId = null
            ..skipNextTurn = false
            ..currentPromptRound = 1
            ..currentPromptIndex = 0
            ..currentRoundPrompts =
                _previewRoundPromptSet.map((item) => item.id).toList();
          _error = null;
          break;
        case Stage.game:
          _session = SessionRecord(status: 'started', round: 1);
          _player ??= _buildPreviewPlayer();
          _player!
            ..pairedWith = 'preview-partner'
            ..pairedRound = 1
            ..interactionRound = _initialInteractionRound
            ..continueVoteRound = null
            ..activeTurnPlayerId = _player!.id
            ..skipNextTurn = false
            ..currentPromptRound = 1
            ..currentPromptIndex = 0
            ..currentRoundPrompts =
                _previewRoundPromptSet.map((item) => item.id).toList();
          _error = null;
          break;
        case Stage.story:
          _session = SessionRecord(status: 'started', round: 1);
          _player ??= _buildPreviewPlayer();
          _player!
            ..pairedWith = 'preview-partner'
            ..pairedRound = 1
            ..interactionRound = _initialInteractionRound
            ..continueVoteRound = null
            ..activeTurnPlayerId = null
            ..skipNextTurn = false
            ..currentPromptRound = 1
            ..currentPromptIndex = _previewRoundPromptSet.length - 1
            ..currentRoundPrompts =
                _previewRoundPromptSet.map((item) => item.id).toList();
          _error = null;
          break;
        case Stage.ended:
          _session = SessionRecord(status: 'ended', round: 1);
          _error = null;
          break;
      }
    });
  }

  void _showPreviewError() {
    if (_launchIntent.type != LaunchIntentType.preview) return;
    _logAppEvent('Preview switched to error state');
    setState(() {
      _screenState = ScreenState.preview;
      _previewErrorMode = true;
      _error = null;
    });
  }

  PlayerRecord _buildPreviewPlayer() {
    return PlayerRecord(
      id: 'preview-player',
      name: 'Avery',
      phone: '0000000000',
      gender: '',
      sexualPreference: '',
      acceptedTermsAndGameTexts: true,
      acceptedPromoTexts: false,
      roundPreference: RoundPreference.playful,
      inviteCode: 'UI42',
      currentPromptRound: 1,
      activeTurnPlayerId: 'preview-player',
      currentRoundPrompts:
          _previewRoundPromptSet.map((item) => item.id).toList(),
      askedPromptIds: _previewRoundPromptSet.map((item) => item.id).toList(),
    );
  }

  Future<bool> _restoreSavedSession(String sessionId) async {
    _logAppEvent(
      'Attempting to restore saved session. initialSessionId=$sessionId',
    );

    final savedState = await _sessionStore.load();
    if (!mounted || savedState == null) {
      _logAppEvent('No saved session found');
      return false;
    }

    if (sessionId != savedState.sessionId) {
      _logAppEvent(
        'Saved session mismatch. clearing saved=${savedState.sessionId} requested=$sessionId',
      );
      await _sessionStore.clear();
      return false;
    }

    try {
      final session = await _service.fetchSession(savedState.sessionId);
      final player = await _service.fetchPlayer(
        savedState.sessionId,
        savedState.playerId,
      );

      if (!mounted) return false;

      setState(() {
        _sessionId = savedState.sessionId;
        _playerId = savedState.playerId;
        _session = session;
        _player = player;
        _error = null;
        _showStageScreen(_stageForSession(session, player: player));
      });

      if (_isSessionEnded(session.status)) {
        await _loadMutualSeeAgainPlayers();
      }

      _startPolling();
      return true;
    } catch (error) {
      _logAppEvent('Failed to restore saved session. Clearing store. $error');
      await _sessionStore.clear();
      return false;
    }
  }

  void _joinWithCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      _showJoinScreen(error: 'Please enter a valid session code.');
      return;
    }

    _logAppEvent('Manual join requested for session $trimmed');
    setState(() {
      _screenState = ScreenState.booting;
      _sessionId = trimmed;
      _error = null;
    });

    unawaited(_attemptSessionJoin(trimmed, fatalOnFailure: false));
  }

  Future<void> _attemptSessionJoin(
    String sessionId, {
    required bool fatalOnFailure,
  }) async {
    if (_isLocalSandboxMode) return;
    _logAppEvent(
      'Session join start for $sessionId (fatalOnFailure=$fatalOnFailure)',
    );

    if (mounted) {
      setState(() {
        _screenState = ScreenState.booting;
        _sessionId = sessionId;
        _error = null;
      });
    }

    try {
      await _ensureBackendAuth();
    } catch (e) {
      _logAppEvent('Session join auth failed: $e');
      _handleSessionJoinFailure(
        _backendErrorMessage(
          fallback: 'Unable to authenticate with Firebase.',
          error: e,
        ),
        fatalOnFailure: fatalOnFailure,
      );
      return;
    }

    final validation = await _validateSessionCode(sessionId);
    _logAppEvent(
      'Bootstrap session validation: sessionId=$sessionId valid=${validation.isValid} error=${validation.error}',
    );

    if (validation.error != null) {
      _handleSessionJoinFailure(
        'Unable to connect to the session server. ${validation.error}',
        fatalOnFailure: fatalOnFailure,
      );
      return;
    }

    if (!validation.isValid) {
      _handleSessionJoinFailure(
        'Session code not found. Open a valid invite link and try again.',
        fatalOnFailure: fatalOnFailure,
      );
      return;
    }

    final restored = await _restoreSavedSession(sessionId);
    if (restored) {
      _logAppEvent('Restore succeeded for $sessionId');
      return;
    }

    _logAppEvent('No reusable saved session. Joining as guest.');
    try {
      await _joinAsGuest(sessionId);
    } catch (e) {
      _logAppEvent('Guest join failed for session $sessionId: $e');
      _handleSessionJoinFailure(
        'Unable to join session: $e',
        fatalOnFailure: fatalOnFailure,
      );
    }
  }

  void _handleSessionJoinFailure(
    String message, {
    required bool fatalOnFailure,
  }) {
    if (_launchIntent.type == LaunchIntentType.demo && !fatalOnFailure) {
      if (!mounted) return;
      setState(() {
        _error = message;
        _screenState = ScreenState.demoName;
      });
      return;
    }

    if (fatalOnFailure) {
      _showErrorScreen(message);
      return;
    }

    _showJoinScreen(error: message);
  }

  Future<void> _joinAsGuest(
    String sessionId, {
    String? guestName,
  }) async {
    _logAppEvent('Joining as guest for session $sessionId');

    final guestId = generateId();
    final resolvedGuestName = guestName?.trim().isNotEmpty == true
        ? guestName!.trim()
        : 'Guest ${guestId.substring(guestId.length - 4).toUpperCase()}';
    final player = PlayerRecord(
      id: guestId,
      name: resolvedGuestName,
      phone: '',
      gender: '',
      sexualPreference: '',
      acceptedTermsAndGameTexts: true,
      acceptedPromoTexts: false,
      roundPreference: RoundPreference.playful,
      inviteCode: generateInviteCode(),
    );

    final session = await _service.fetchSession(sessionId);
    final sessionStatus = session.status?.trim();
    if (sessionStatus == null || sessionStatus.isEmpty) {
      throw StateError(
        'Session code not found. Open a valid invite link and try again.',
      );
    }

    await _service.savePlayer(sessionId, player);
    _logAppEvent('Guest join succeeded for session $sessionId as ${player.id}');

    if (!mounted) return;
    setState(() {
      _sessionId = sessionId;
      _player = player;
      _playerId = player.id;
      _session = session;
      _error = null;
      _showStageScreen(_stageForSession(session, player: player));
    });

    await _sessionStore.save(sessionId: sessionId, playerId: player.id);
    _startPolling();
  }

  Future<void> _submitDemoName(String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || _sessionId == null) return;

    setState(() {
      _screenState = ScreenState.booting;
      _error = null;
    });

    try {
      await _joinAsGuest(
        _sessionId!,
        guestName: normalizedName,
      );
    } catch (error) {
      _handleSessionJoinFailure(
        'Unable to join demo: $error',
        fatalOnFailure: false,
      );
    }
  }

  @override
  void dispose() {
    _bootstrapWatchdog?.cancel();
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _handleSignup(SignupPayload payload) async {
    if (_isLocalSandboxMode) {
      setState(() {
        final localPlayer = PlayerRecord(
          id: 'preview-player',
          name: payload.name,
          phone: payload.phone,
          gender: '',
          sexualPreference: '',
          acceptedTermsAndGameTexts: payload.acceptedTermsAndGameTexts,
          acceptedPromoTexts: payload.acceptedPromoTexts,
          roundPreference: payload.roundPreference,
          inviteCode: 'UI42',
        );
        _player = localPlayer;
        _playerId = localPlayer.id;
        _session = SessionRecord(status: 'waiting', round: 1);
        _showLocalStage(Stage.waiting);
      });
      return;
    }

    if (_sessionId == null) return;

    setState(() {
      _error = null;
    });

    try {
      final session = await _service.fetchSession(_sessionId!);
      final playerId = FirebaseAuth.instance.currentUser?.uid ??
          _phoneAuthPlayerId(payload.phone);
      final inviteCode = generateInviteCode();
      final signup = payload;
      final player = PlayerRecord(
        id: playerId,
        name: signup.name,
        phone: signup.phone,
        gender: '',
        sexualPreference: '',
        acceptedTermsAndGameTexts: signup.acceptedTermsAndGameTexts,
        acceptedPromoTexts: signup.acceptedPromoTexts,
        roundPreference: signup.roundPreference,
        inviteCode: inviteCode,
      );

      await _service.savePlayer(_sessionId!, player);
      await _firestoreService.saveSignup(
        sessionId: _sessionId!,
        player: player,
      );

      setState(() {
        _session = session;
        _player = player;
        _playerId = playerId;
        _showStageScreen(Stage.waiting);
      });

      await _sessionStore.save(
        sessionId: _sessionId!,
        playerId: playerId,
      );

      _startPolling();
    } catch (e) {
      setState(() {
        _error = 'Unable to sign up: $e';
      });
    }
  }

  String _phoneAuthPlayerId(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) return generateId();
    return 'phone_$digitsOnly';
  }

  void _startPolling() {
    if (_isLocalSandboxMode) return;
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_sessionId == null || _playerId == null || !mounted) return;
      try {
        final session = await _service.fetchSession(_sessionId!);
        final player = await _service.fetchPlayer(_sessionId!, _playerId!);

        if (!mounted) return;

        final roundChanged =
            (_session?.round != null && session.round != _session!.round);
        final previousPlayer = _player;

        if (roundChanged &&
            (_stage == Stage.game ||
                _stage == Stage.story ||
                _stage == Stage.matching)) {
          final previousPartnerId = previousPlayer?.pairedWith;
          await _service.clearPairing(_sessionId!, _playerId!);
          player.pairedWith = null;
          player.pairedRound = null;
          player.partnerCode = null;
          player.interactionRound = _initialInteractionRound;
          player.continueVoteRound = null;
          player.activeTurnPlayerId = null;
          player.skipNextTurn = false;

          if (previousPartnerId != null) {
            unawaited(_showRoundEndedDialog(previousPartnerId));
          } else {
            unawaited(_showRoundEndedDialog(null));
          }
        }

        var syncedPlayer = player;
        if (!roundChanged &&
            _isSessionLive(session.status) &&
            syncedPlayer.pairedWith != null &&
            syncedPlayer.pairedRound == session.round &&
            syncedPlayer.continueVoteRound == _continueVoteRound &&
            syncedPlayer.interactionRound < _finalInteractionRound &&
            session.round != null) {
          try {
            final partner = await _service.fetchPlayer(
              _sessionId!,
              syncedPlayer.pairedWith!,
            );
            final advanced = await _maybeAdvanceInteractionRound(
              me: syncedPlayer,
              partner: partner,
              sessionRound: session.round!,
            );
            if (advanced) {
              syncedPlayer =
                  await _service.fetchPlayer(_sessionId!, _playerId!);
            }
          } catch (_) {
            // Ignore transient partner lookup failures and keep polling.
          }
        }

        if (!roundChanged &&
            _isSessionLive(session.status) &&
            syncedPlayer.pairedWith != null &&
            syncedPlayer.pairedRound == session.round &&
            session.round != null) {
          try {
            final partner = await _service.fetchPlayer(
              _sessionId!,
              syncedPlayer.pairedWith!,
            );
            final skipped = await _maybeConsumeQueuedSkipTurn(
              me: syncedPlayer,
              partner: partner,
              sessionRound: session.round!,
            );
            if (skipped) {
              syncedPlayer =
                  await _service.fetchPlayer(_sessionId!, _playerId!);
            }
          } catch (_) {
            // Ignore transient partner lookup failures and keep polling.
          }
        }

        final shouldShowMeetSomeoneElseDialog =
            _shouldShowMeetSomeoneElseDialog(
          previousPlayer: previousPlayer,
          currentPlayer: syncedPlayer,
          session: session,
          roundChanged: roundChanged,
        );
        final nextStage = _stageForSession(session, player: syncedPlayer);
        setState(() {
          _session = session;
          _player = syncedPlayer;
          _error = null;
          if (_screenState != ScreenState.signup) {
            _showStageScreen(nextStage);
          }
        });

        if (shouldShowMeetSomeoneElseDialog) {
          unawaited(_showMeetSomeoneElseDialog());
        }

        if (_isSessionEnded(session.status)) {
          await _loadMutualSeeAgainPlayers();
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Realtime sync failed: $e';
        });
      }
    });
  }

  Future<void> _submitPartnerCode(String code) async {
    if (_isLocalSandboxMode) {
      final normalized = code.trim().toUpperCase();
      if (normalized.length < 4) {
        setState(() {
          _error = 'Enter a 4-character code to start.';
        });
        return;
      }

      final prompts = await _pickLocalRoundPrompts();
      setState(() {
        _player
          ?..pairedWith = 'preview-partner'
          ..pairedRound = _session?.round ?? 1
          ..partnerCode = normalized
          ..interactionRound = _initialInteractionRound
          ..continueVoteRound = null
          ..activeTurnPlayerId = _player!.id
          ..skipNextTurn = false
          ..currentPromptRound = _session?.round ?? 1
          ..currentPromptIndex = 0
          ..currentRoundPrompts = prompts.map((item) => item.id).toList()
          ..askedPromptIds = {
            ..._player!.askedPromptIds,
            ...prompts.map((item) => item.id),
          }.toList();
        _showLocalStage(Stage.game);
        _error = null;
      });
      return;
    }

    if (_sessionId == null || _player == null || _session == null) return;

    try {
      final players = await _service.fetchPlayers(_sessionId!);
      final normalized = code.trim().toUpperCase();

      final partner = players.values.firstWhere(
        (p) => p.id != _player!.id && p.inviteCode.toUpperCase() == normalized,
      );

      final alreadyMatched = _player!.matchedPlayerIds.contains(partner.id) ||
          partner.matchedPlayerIds.contains(_player!.id);
      if (alreadyMatched) {
        setState(() {
          _error =
              'You have already matched with this player in a previous round.';
        });
        return;
      }

      await _service.setPairing(
        sessionId: _sessionId!,
        me: _player!,
        partner: partner,
        round: _session?.round,
        enteredCode: normalized,
      );

      await _assignRoundPromptsIfNeeded(partner);

      final refreshed = await _service.fetchPlayer(_sessionId!, _player!.id);
      setState(() {
        _player = refreshed;
      });
    } on StateError {
      setState(() {
        _error = 'No player exists with that code yet.';
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to pair: $e';
      });
    }
  }

  Future<List<PromptItem>> _pickLocalRoundPrompts() async {
    _promptCatalog ??= await _promptCatalogService.loadDatingCatalog();
    final catalog = _promptCatalog!;
    final seenIds = _player?.askedPromptIds.toSet() ?? <String>{};
    final prompts = <PromptItem>[];

    PromptItem pickFromSet(String setId) {
      final prompt = catalog.pickUnused(
        setId,
        {
          ...seenIds,
          ...prompts.map((item) => item.id),
        },
      );
      seenIds.add(prompt.id);
      return prompt;
    }

    prompts
      ..add(pickFromSet('icebreakers_level1'))
      ..add(pickFromSet('activities_level1'))
      ..add(pickFromSet('dating_questions_level1'))
      ..add(storyModePromptItem);
    return prompts;
  }

  List<PromptItem> _pickPromptBatch({
    required PromptCatalog catalog,
    required String setId,
    required Set<String> usedIds,
    int count = 3,
  }) {
    final options = List<PromptItem>.from(catalog.sets[setId] ?? const []);
    if (options.isEmpty) {
      throw StateError('Prompt set $setId is empty.');
    }

    final unused = options.where((item) => !usedIds.contains(item.id)).toList();
    final primaryPool = unused.isNotEmpty ? unused : options;
    primaryPool.shuffle(Random.secure());

    final selected = <PromptItem>[];
    for (final item in primaryPool) {
      if (selected.any((existing) => existing.id == item.id)) continue;
      selected.add(item);
      if (selected.length == count) return selected;
    }

    final remaining = options
        .where((item) => !selected.any((existing) => existing.id == item.id))
        .toList()
      ..shuffle(Random.secure());

    for (final item in remaining) {
      selected.add(item);
      if (selected.length == count) return selected;
    }

    while (selected.length < count) {
      selected.add(options[Random.secure().nextInt(options.length)]);
    }

    return selected;
  }

  bool _hasStoryModePrompt(PlayerRecord player) {
    return player.currentRoundPrompts.isNotEmpty &&
        player.currentRoundPrompts.last == storyModePromptId;
  }

  int _normalPromptCount(PlayerRecord player) {
    return _hasStoryModePrompt(player)
        ? max(0, player.currentRoundPrompts.length - 1)
        : player.currentRoundPrompts.length;
  }

  bool _hasRemainingNormalPrompt(PlayerRecord player) {
    return player.currentPromptIndex < _normalPromptCount(player);
  }

  bool _isSharedStoryReady(PlayerRecord me, PlayerRecord partner) {
    return _hasStoryModePrompt(me) &&
        _hasStoryModePrompt(partner) &&
        me.currentPromptIndex >= _normalPromptCount(me) &&
        partner.currentPromptIndex >= _normalPromptCount(partner);
  }

  String _starterForInteraction({
    required PlayerRecord me,
    required PlayerRecord partner,
    required int interactionRound,
  }) {
    final orderedIds = [me.id, partner.id]..sort();
    return orderedIds[(interactionRound - 1) % orderedIds.length];
  }

  void _advanceOwnPromptIndex(PlayerRecord player) {
    player.currentPromptIndex = min(
      player.currentPromptIndex + 1,
      player.currentRoundPrompts.length,
    );
  }

  String? _resolveNextActiveTurnPlayerId({
    required PlayerRecord active,
    required PlayerRecord partner,
  }) {
    if (_isSharedStoryReady(active, partner)) {
      return null;
    }

    PlayerRecord candidate = partner;
    for (var i = 0; i < 4; i += 1) {
      if (!_hasRemainingNormalPrompt(active) &&
          !_hasRemainingNormalPrompt(partner)) {
        return null;
      }

      if (_hasRemainingNormalPrompt(candidate)) {
        if (candidate.skipNextTurn) {
          candidate.skipNextTurn = false;
          _advanceOwnPromptIndex(candidate);
          if (_isSharedStoryReady(active, partner)) {
            return null;
          }
          candidate = identical(candidate, active) ? partner : active;
          continue;
        }
        return candidate.id;
      }

      candidate = identical(candidate, active) ? partner : active;
    }

    return null;
  }

  void _applyPromptDeck({
    required PlayerRecord player,
    required int round,
    required int interactionRound,
    required List<String> promptIds,
    required List<String> askedPromptIds,
    required String? activeTurnPlayerId,
  }) {
    player
      ..interactionRound = interactionRound
      ..continueVoteRound = null
      ..currentPromptRound = round
      ..currentPromptIndex = 0
      ..activeTurnPlayerId = activeTurnPlayerId
      ..skipNextTurn = false
      ..currentRoundPrompts = List<String>.from(promptIds)
      ..askedPromptIds = List<String>.from(askedPromptIds);
  }

  Future<void> _persistPairState({
    required PlayerRecord me,
    required PlayerRecord partner,
  }) async {
    if (_sessionId == null) return;
    await _service.savePlayer(_sessionId!, me);
    await _service.savePlayer(_sessionId!, partner);
  }

  Future<bool> _advancePromptTurnForPair({
    required PlayerRecord active,
    required PlayerRecord partner,
  }) async {
    if (_sessionId == null) return false;

    active.skipNextTurn = false;
    _advanceOwnPromptIndex(active);
    final nextActiveTurnPlayerId = _resolveNextActiveTurnPlayerId(
      active: active,
      partner: partner,
    );

    active.activeTurnPlayerId = nextActiveTurnPlayerId;
    partner.activeTurnPlayerId = nextActiveTurnPlayerId;

    if (nextActiveTurnPlayerId == null) {
      active.skipNextTurn = false;
      partner.skipNextTurn = false;
    }

    await _persistPairState(me: active, partner: partner);
    return true;
  }

  Future<bool> _maybeConsumeQueuedSkipTurn({
    required PlayerRecord me,
    required PlayerRecord partner,
    required int sessionRound,
  }) async {
    if (_sessionId == null ||
        me.pairedWith != partner.id ||
        partner.pairedWith != me.id ||
        me.pairedRound != sessionRound ||
        partner.pairedRound != sessionRound ||
        me.activeTurnPlayerId != me.id ||
        !me.skipNextTurn ||
        !_hasRemainingNormalPrompt(me)) {
      return false;
    }

    return _advancePromptTurnForPair(active: me, partner: partner);
  }

  Future<bool> _maybeAdvanceInteractionRound({
    required PlayerRecord me,
    required PlayerRecord partner,
    required int sessionRound,
  }) async {
    if (_sessionId == null ||
        me.pairedWith != partner.id ||
        partner.pairedWith != me.id ||
        me.interactionRound >= _finalInteractionRound ||
        partner.interactionRound >= _finalInteractionRound ||
        me.continueVoteRound != _continueVoteRound ||
        partner.continueVoteRound != _continueVoteRound) {
      return false;
    }

    _promptCatalog ??= await _promptCatalogService.loadDatingCatalog();
    final catalog = _promptCatalog!;
    final usedIds = {
      ...me.askedPromptIds,
      ...partner.askedPromptIds,
    };
    final mePrompts = _pickPromptBatch(
      catalog: catalog,
      setId: 'icebreakers_level2',
      usedIds: usedIds,
    );
    usedIds.addAll(mePrompts.map((item) => item.id));
    final partnerPrompts = _pickPromptBatch(
      catalog: catalog,
      setId: 'icebreakers_level2',
      usedIds: usedIds,
    );

    final mePromptIds = mePrompts.map((item) => item.id).toList();
    final partnerPromptIds = partnerPrompts.map((item) => item.id).toList();
    final mergedHistory = {
      ...me.askedPromptIds,
      ...partner.askedPromptIds,
      ...mePromptIds,
      ...partnerPromptIds,
    }.toList();
    final activeTurnPlayerId = _starterForInteraction(
      me: me,
      partner: partner,
      interactionRound: _finalInteractionRound,
    );

    _applyPromptDeck(
      player: me,
      round: sessionRound,
      interactionRound: _finalInteractionRound,
      promptIds: mePromptIds,
      askedPromptIds: mergedHistory,
      activeTurnPlayerId: activeTurnPlayerId,
    );
    _applyPromptDeck(
      player: partner,
      round: sessionRound,
      interactionRound: _finalInteractionRound,
      promptIds: partnerPromptIds,
      askedPromptIds: mergedHistory,
      activeTurnPlayerId: activeTurnPlayerId,
    );

    await _persistPairState(me: me, partner: partner);

    return true;
  }

  Future<void> _continueInteractionWithLevelTwoPrompts() async {
    _promptCatalog ??= await _promptCatalogService.loadDatingCatalog();
    final catalog = _promptCatalog!;

    if (_isLocalSandboxMode) {
      final me = _player;
      if (me == null || me.interactionRound >= _finalInteractionRound) return;

      final prompts = _pickPromptBatch(
        catalog: catalog,
        setId: 'icebreakers_level2',
        usedIds: me.askedPromptIds.toSet(),
      );

      if (!mounted) return;
      setState(() {
        final promptIds = prompts.map((item) => item.id).toList();
        _player!
          ..interactionRound = _finalInteractionRound
          ..continueVoteRound = null
          ..activeTurnPlayerId = _player!.id
          ..skipNextTurn = false
          ..currentPromptRound = _session?.round ?? 1
          ..currentPromptIndex = 0
          ..currentRoundPrompts = promptIds
          ..askedPromptIds = {
            ..._player!.askedPromptIds,
            ...promptIds,
          }.toList();
        _error = null;
      });
      return;
    }

    if (_sessionId == null ||
        _player == null ||
        _player!.pairedWith == null ||
        _session?.round == null) {
      return;
    }

    final me = _player!;
    if (me.interactionRound >= _finalInteractionRound) return;

    await _service.setContinueVote(
      sessionId: _sessionId!,
      playerId: me.id,
      continueVoteRound: _continueVoteRound,
    );

    var refreshed = await _service.fetchPlayer(_sessionId!, me.id);
    final partnerId = refreshed.pairedWith ?? me.pairedWith;
    if (partnerId != null) {
      final partner = await _service.fetchPlayer(_sessionId!, partnerId);
      await _maybeAdvanceInteractionRound(
        me: refreshed,
        partner: partner,
        sessionRound: _session!.round!,
      );
      refreshed = await _service.fetchPlayer(_sessionId!, me.id);
    }

    if (!mounted) return;
    setState(() {
      _player = refreshed;
      _error = null;
    });
  }

  Future<void> _endCurrentInteraction() async {
    if (_isLocalSandboxMode) {
      _completeLocalRound();
      return;
    }

    if (_sessionId == null || _player == null) return;

    final me = _player!;
    final partnerId = me.pairedWith;
    if (partnerId == null) return;

    await _service.clearPairing(_sessionId!, me.id);
    await _service.clearPairing(_sessionId!, partnerId);

    final refreshed = await _service.fetchPlayer(_sessionId!, me.id);
    if (!mounted) return;

    setState(() {
      _player = refreshed;
      _error = null;
      _showStageScreen(_stageForSession(_session, player: refreshed));
    });
  }

  bool _isSessionLive(String? status) =>
      status?.trim().toLowerCase() == 'started';

  bool _isSessionEnded(String? status) =>
      status?.trim().toLowerCase() == 'ended';

  bool _shouldShowMeetSomeoneElseDialog({
    required PlayerRecord? previousPlayer,
    required PlayerRecord currentPlayer,
    required SessionRecord session,
    required bool roundChanged,
  }) {
    final sessionRound = session.round;
    return !roundChanged &&
        sessionRound != null &&
        previousPlayer != null &&
        previousPlayer.pairedWith != null &&
        previousPlayer.pairedRound == sessionRound &&
        previousPlayer.interactionRound < _finalInteractionRound &&
        previousPlayer.continueVoteRound == _continueVoteRound &&
        currentPlayer.pairedWith == null;
  }

  Stage _stageForSession(SessionRecord? session, {PlayerRecord? player}) {
    final status = session?.status;
    if (_isSessionLive(status)) {
      final isPairedThisRound = player?.pairedWith != null &&
          player?.pairedRound != null &&
          player!.pairedRound == session?.round;
      return isPairedThisRound ? Stage.game : Stage.matching;
    }
    if (_isSessionEnded(status)) return Stage.ended;
    return Stage.waiting;
  }

  Future<void> _showRoundEndedDialog(String? partnerId) async {
    if (!mounted) return;

    String? partnerName;
    if (partnerId != null && _sessionId != null) {
      try {
        final partner = await _service.fetchPlayer(_sessionId!, partnerId);
        partnerName = partner.name.trim().isEmpty ? null : partner.name.trim();
      } catch (_) {
        partnerName = null;
      }
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('The round has ended'),
          content: Text(
            partnerName != null
                ? 'Would you like to see $partnerName again?'
                : 'Would you like to see your last partner again?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('No thanks'),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (_sessionId != null &&
                    _playerId != null &&
                    partnerId != null) {
                  await _service.setSeeAgainPreference(
                    sessionId: _sessionId!,
                    playerId: _playerId!,
                    partnerId: partnerId,
                  );
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Text('👍'),
              label: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMeetSomeoneElseDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: const Text('Lets meet someone else'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadMutualSeeAgainPlayers() async {
    if (_sessionId == null || _playerId == null) return;
    final players = await _service.fetchPlayers(_sessionId!);
    final me = players[_playerId!];
    if (me == null) return;

    final matches = me.seeAgainPlayerIds
        .map((partnerId) => players[partnerId])
        .whereType<PlayerRecord>()
        .where((partner) => partner.seeAgainPlayerIds.contains(me.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (!mounted) return;
    setState(() {
      _mutualSeeAgainPlayers = matches;
    });
  }

  Future<void> _assignRoundPromptsIfNeeded(PlayerRecord partner) async {
    if (_sessionId == null || _player == null) return;
    final round = _session?.round;
    if (round == null) return;

    _promptCatalog ??= await _promptCatalogService.loadDatingCatalog();
    final catalog = _promptCatalog!;
    final me = _player!;
    final partnerRefreshed =
        await _service.fetchPlayer(_sessionId!, partner.id);
    if (me.currentPromptRound == round &&
        me.currentRoundPrompts.isNotEmpty &&
        partnerRefreshed.currentPromptRound == round &&
        partnerRefreshed.currentRoundPrompts.isNotEmpty) {
      return;
    }

    final seenIds = {
      ...me.askedPromptIds,
      ...partnerRefreshed.askedPromptIds,
    };
    final finalSet = me.roundPreference == RoundPreference.openingUp &&
            partnerRefreshed.roundPreference == RoundPreference.openingUp
        ? 'dating_questions_level1'
        : 'icebreakers_level2';

    List<PromptItem> buildDeck() {
      final icebreaker = catalog.pickUnused('icebreakers_level1', seenIds);
      seenIds.add(icebreaker.id);
      final activity = catalog.pickUnused('activities_level1', seenIds);
      seenIds.add(activity.id);
      final finalPrompt = catalog.pickUnused(finalSet, seenIds);
      seenIds.add(finalPrompt.id);
      return [icebreaker, activity, finalPrompt, storyModePromptItem];
    }

    final mePrompts = buildDeck();
    final partnerPrompts = buildDeck();
    final mePromptIds = mePrompts.map((prompt) => prompt.id).toList();
    final partnerPromptIds = partnerPrompts.map((prompt) => prompt.id).toList();

    final mergedHistory = {
      ...me.askedPromptIds,
      ...partnerRefreshed.askedPromptIds,
      ...mePromptIds,
      ...partnerPromptIds,
    }.toList();
    final activeTurnPlayerId = _starterForInteraction(
      me: me,
      partner: partnerRefreshed,
      interactionRound: _initialInteractionRound,
    );

    _applyPromptDeck(
      player: me,
      round: round,
      interactionRound: _initialInteractionRound,
      promptIds: mePromptIds,
      askedPromptIds: mergedHistory,
      activeTurnPlayerId: activeTurnPlayerId,
    );
    _applyPromptDeck(
      player: partnerRefreshed,
      round: round,
      interactionRound: _initialInteractionRound,
      promptIds: partnerPromptIds,
      askedPromptIds: mergedHistory,
      activeTurnPlayerId: activeTurnPlayerId,
    );

    await _persistPairState(me: me, partner: partnerRefreshed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth =
                constraints.hasBoundedWidth && constraints.maxWidth > 0
                    ? constraints.maxWidth
                    : _gameViewportSize.width;
            final availableHeight =
                constraints.hasBoundedHeight && constraints.maxHeight > 0
                    ? constraints.maxHeight
                    : _gameViewportSize.height;
            final viewportAspect =
                _gameViewportSize.width / _gameViewportSize.height;

            var contentWidth = availableWidth;
            var contentHeight = contentWidth / viewportAspect;
            if (contentHeight > availableHeight) {
              contentHeight = availableHeight;
              contentWidth = contentHeight * viewportAspect;
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                const Positioned.fill(
                  child: _ChatGptTextureBackdrop(
                    seed: 'main-theme-background',
                    textureAsset: _backgroundImageAsset,
                    minScale: 3.4,
                    maxScale: 4.6,
                    gradientOpacity: 0.42,
                  ),
                ),
                const Positioned.fill(child: FilmOverlay()),
                Positioned.fill(
                  child: Center(
                    child: SizedBox(
                      width: contentWidth,
                      height: contentHeight,
                      child: Padding(
                        padding: _screenContentPadding,
                        child: _buildBody(),
                      ),
                    ),
                  ),
                ),
                _buildPreviewToolbar(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_screenState) {
      case ScreenState.booting:
        _logBody('bootstrapping', 'Rendering bootstrap loading view');
        return const _BootstrapLoadingView();
      case ScreenState.error:
        _logBody('session-error', 'Rendering session error view');
        return _SessionFlowFatalErrorBody(
          message: _error,
        );
      case ScreenState.join:
        _logBody('join', 'Rendering join session code view');
        return _ContentPanel(
          child: JoinWithCodeView(
            error: _error,
            onJoin: _joinWithCode,
          ),
        );
      case ScreenState.preview:
        return _buildPreviewBody();
      case ScreenState.demoName:
        _logBody(
            'demo-name', 'Rendering demo name entry for session $_sessionId');
        return _ContentPanel(
          child: DemoNameForm(
            onSubmit: _submitDemoName,
            error: _error,
          ),
        );
      case ScreenState.signup:
        _logBody('signup', 'Rendering signup view for session $_sessionId');
        return _ContentPanel(
          child: SignupForm(
            sessionId: _sessionId!,
            onSubmit: _handleSignup,
            error: _error,
          ),
        );
      case ScreenState.waiting:
        _logBody('waiting', 'Rendering waiting view for session $_sessionId');
        return WaitingView(
          player: _player,
          session: _session,
          error: _error,
        );
      case ScreenState.matching:
        _logBody('matching', 'Rendering matching view for session $_sessionId');
        return GameView(
          sessionId: _sessionId,
          player: _player,
          session: _session,
          error: _error,
          onSubmitCode: _submitPartnerCode,
          onDrawPrompt: _syncPromptDraw,
          onAskSameQuestion: _askSameQuestionAndSkipNextTurn,
          onContinueInteraction: _continueInteractionWithLevelTwoPrompts,
          onEndInteraction: _isLocalSandboxMode ? null : _endCurrentInteraction,
          promptCatalog: _promptCatalog,
          storyPromptCatalogService: _databaseStoryPromptCatalogService,
          storyCardDealer: StoryPromptCardDealer(),
          storyRtdbService: _service,
          forceMatchingMode: true,
          unpairedInstructions:
              'Share your code, then enter someone else\'s 4-character code to start talking.',
          codeEntryPrompt: 'Enter another person\'s 4-character code:',
          showInviteCodeCard: true,
          onRoundComplete: _isLocalSandboxMode ? _completeLocalRound : null,
        );
      case ScreenState.game:
        _logBody('game', 'Rendering game view for session $_sessionId');
        return GameView(
          sessionId: _sessionId,
          player: _player,
          session: _session,
          error: _error,
          onSubmitCode: _submitPartnerCode,
          onDrawPrompt: _syncPromptDraw,
          onAskSameQuestion: _askSameQuestionAndSkipNextTurn,
          onContinueInteraction: _continueInteractionWithLevelTwoPrompts,
          onEndInteraction: _isLocalSandboxMode ? null : _endCurrentInteraction,
          promptCatalog: _promptCatalog,
          storyPromptCatalogService: _databaseStoryPromptCatalogService,
          storyCardDealer: StoryPromptCardDealer(),
          storyRtdbService: _service,
          unpairedInstructions:
              'Share your code, then enter someone else\'s 4-character code to start talking.',
          codeEntryPrompt: 'Enter another person\'s 4-character code:',
          showInviteCodeCard: true,
          onRoundComplete: _isLocalSandboxMode ? _completeLocalRound : null,
        );
      case ScreenState.ended:
        _logBody('ended', 'Rendering ended view for session $_sessionId');
        return _ContentPanel(child: EndedView(players: _mutualSeeAgainPlayers));
    }
  }

  Widget _buildPreviewBody() {
    if (_previewErrorMode) {
      _logBody('preview-error', 'Rendering preview error view');
      return const _PreviewFatalErrorBody();
    }

    switch (_stage) {
      case Stage.signup:
        _logBody('preview-signup', 'Rendering preview signup view');
        return _ContentPanel(
          child: SignupForm(
            sessionId: _sessionId ?? 'AB12',
            onSubmit: _handleSignup,
            error: _error,
          ),
        );
      case Stage.waiting:
        _logBody('preview-waiting', 'Rendering preview waiting view');
        return WaitingView(
          player: _player,
          session: _session,
          error: _error,
        );
      case Stage.matching:
        _logBody('preview-matching', 'Rendering preview matching view');
        return GameView(
          sessionId: _sessionId,
          player: _player,
          session: _session,
          error: _error,
          onSubmitCode: _submitPartnerCode,
          onDrawPrompt: _syncPromptDraw,
          onAskSameQuestion: _askSameQuestionAndSkipNextTurn,
          onContinueInteraction: _continueInteractionWithLevelTwoPrompts,
          promptCatalog: _promptCatalog,
          storyPromptCatalogService: _databaseStoryPromptCatalogService,
          storyCardDealer: StoryPromptCardDealer(),
          storyRtdbService: _previewStoryRtdbService,
          forceMatchingMode: true,
          unpairedInstructions:
              'Enter a 4-character code to open a conversation.',
          codeEntryPrompt: 'Enter a 4-character code:',
          showInviteCodeCard: true,
          onRoundComplete: _completeLocalRound,
        );
      case Stage.game:
        _logBody('preview-game', 'Rendering preview game view');
        return GameView(
          sessionId: _sessionId,
          player: _player,
          session: _session,
          error: _error,
          onSubmitCode: _submitPartnerCode,
          onDrawPrompt: _syncPromptDraw,
          onAskSameQuestion: _askSameQuestionAndSkipNextTurn,
          onContinueInteraction: _continueInteractionWithLevelTwoPrompts,
          promptCatalog: _promptCatalog,
          storyPromptCatalogService: _databaseStoryPromptCatalogService,
          storyCardDealer: StoryPromptCardDealer(),
          storyRtdbService: _previewStoryRtdbService,
          unpairedInstructions:
              'Enter a 4-character code to open a conversation.',
          codeEntryPrompt: 'Enter a 4-character code:',
          showInviteCodeCard: true,
          onRoundComplete: _completeLocalRound,
        );
      case Stage.story:
        _logBody('preview-story', 'Rendering preview story view');
        return GameView(
          sessionId: _sessionId,
          player: _player,
          session: _session,
          error: _error,
          onSubmitCode: _submitPartnerCode,
          onDrawPrompt: _syncPromptDraw,
          onAskSameQuestion: _askSameQuestionAndSkipNextTurn,
          onContinueInteraction: _continueInteractionWithLevelTwoPrompts,
          promptCatalog: _promptCatalog,
          storyPromptCatalogService: _databaseStoryPromptCatalogService,
          storyCardDealer: StoryPromptCardDealer(),
          storyRtdbService: _previewStoryRtdbService,
          unpairedInstructions:
              'Enter a 4-character code to open a conversation.',
          codeEntryPrompt: 'Enter a 4-character code:',
          showInviteCodeCard: true,
          onRoundComplete: _completeLocalRound,
        );
      case Stage.ended:
        _logBody('preview-ended', 'Rendering preview ended view');
        return _ContentPanel(child: EndedView(players: _mutualSeeAgainPlayers));
    }
  }

  Future<void> _syncPromptDraw({
    required int promptIndex,
    required String partnerId,
  }) async {
    if (_isLocalSandboxMode) {
      if (_player == null) return;
      final hasStoryMode = _player!.currentRoundPrompts.isNotEmpty &&
          _player!.currentRoundPrompts.last == storyModePromptId;
      final storyIndex = max(0, _player!.currentRoundPrompts.length - 1);
      setState(() {
        _player!.currentPromptIndex = promptIndex;
        _player!.activeTurnPlayerId =
            (hasStoryMode && promptIndex >= storyIndex) ||
                    promptIndex >= _player!.currentRoundPrompts.length
                ? null
                : _player!.id;
      });
      return;
    }

    if (_sessionId == null || _player == null) return;
    final me = await _service.fetchPlayer(_sessionId!, _player!.id);
    if (me.pairedWith != partnerId ||
        (me.activeTurnPlayerId != null && me.activeTurnPlayerId != me.id)) {
      return;
    }
    final partner = await _service.fetchPlayer(_sessionId!, partnerId);
    await _advancePromptTurnForPair(active: me, partner: partner);

    final refreshed = await _service.fetchPlayer(_sessionId!, _player!.id);
    if (!mounted) return;
    setState(() {
      _player = refreshed;
    });
  }

  Future<void> _askSameQuestionAndSkipNextTurn() async {
    if (_player == null || _player!.skipNextTurn) return;

    if (_isLocalSandboxMode) {
      setState(() {
        _player!.skipNextTurn = true;
      });
      return;
    }

    if (_sessionId == null || _playerId == null) return;

    await _service.setSkipNextTurn(
      sessionId: _sessionId!,
      playerId: _playerId!,
      skipNextTurn: true,
    );

    final refreshed = await _service.fetchPlayer(_sessionId!, _playerId!);
    if (!mounted) return;
    setState(() {
      _player = refreshed;
      _error = null;
    });
  }

  void _completeLocalRound() {
    if (!_isLocalSandboxMode || _player == null) return;
    setState(() {
      _player!
        ..pairedWith = null
        ..pairedRound = null
        ..partnerCode = null
        ..interactionRound = _initialInteractionRound
        ..continueVoteRound = null
        ..activeTurnPlayerId = null
        ..skipNextTurn = false
        ..currentPromptIndex = 0
        ..currentPromptRound = _session?.round ?? 1
        ..currentRoundPrompts = const <String>[];
      _showLocalStage(Stage.matching);
      _error = null;
    });
  }

  Widget _buildPreviewToolbar() {
    if (_launchIntent.type != LaunchIntentType.preview) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: SafeArea(
        minimum: const EdgeInsets.only(bottom: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PreviewStageButton(
                    label: 'Signup',
                    onTap: () => _setPreviewStage(Stage.signup)),
                const SizedBox(width: 6),
                _PreviewStageButton(
                    label: 'Waiting',
                    onTap: () => _setPreviewStage(Stage.waiting)),
                const SizedBox(width: 6),
                _PreviewStageButton(
                    label: 'Matching',
                    onTap: () => _setPreviewStage(Stage.matching)),
                const SizedBox(width: 6),
                _PreviewStageButton(label: 'Error', onTap: _showPreviewError),
                const SizedBox(width: 6),
                _PreviewStageButton(
                    label: 'Game', onTap: () => _setPreviewStage(Stage.game)),
                const SizedBox(width: 6),
                _PreviewStageButton(
                    label: 'Story', onTap: () => _setPreviewStage(Stage.story)),
                const SizedBox(width: 6),
                _PreviewStageButton(
                    label: 'Ended', onTap: () => _setPreviewStage(Stage.ended)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapLoadingView extends StatelessWidget {
  const _BootstrapLoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DefaultTextStyle.merge(
        style: _backgroundBodyStyle(context),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeartTimerLoader(),
            SizedBox(height: 12),
            Text('Connecting to session...'),
          ],
        ),
      ),
    );
  }
}

class _PreviewFatalErrorBody extends StatelessWidget {
  const _PreviewFatalErrorBody();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Center(
        child: _FatalErrorContent(showDebugDetails: false),
      ),
    );
  }
}

class _SessionFlowFatalErrorBody extends StatelessWidget {
  const _SessionFlowFatalErrorBody({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final trimmedMessage = message?.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Center(
        child: _FatalErrorContent(
          error: _FatalAppError(
            message: trimmedMessage == null || trimmedMessage.isEmpty
                ? 'Session link is missing or invalid.'
                : trimmedMessage,
            stackTrace: StackTrace.empty,
          ),
        ),
      ),
    );
  }
}

class _PreviewStageButton extends StatelessWidget {
  const _PreviewStageButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white30),
      ),
      child: Text(label),
    );
  }
}

class _PreviewStoryRtdbService extends RtdbService {
  final Map<String, Map<String, StoryPairPlayerRecord>> _storyPairPlayers =
      <String, Map<String, StoryPairPlayerRecord>>{};

  void reset() {
    _storyPairPlayers.clear();
  }

  @override
  Future<StoryPairPlayerRecord?> fetchStoryPairPlayer({
    required String pairId,
    required String playerId,
  }) async {
    final player = _storyPairPlayers[pairId]?[playerId];
    if (player == null) return null;
    return StoryPairPlayerRecord.fromJson(player.toJson());
  }

  @override
  Future<StoryPairResultRecord?> fetchStoryPairResult(String pairId) async {
    return null;
  }

  @override
  Future<void> saveStoryPairPlayer({
    required String pairId,
    required StoryPairPlayerRecord player,
  }) async {
    _storyPairPlayers.putIfAbsent(
      pairId,
      () => <String, StoryPairPlayerRecord>{},
    )[player.playerId] = StoryPairPlayerRecord.fromJson(player.toJson());
  }
}

class JoinWithCodeView extends StatefulWidget {
  const JoinWithCodeView({
    super.key,
    required this.onJoin,
    this.error,
  });

  final void Function(String code) onJoin;
  final String? error;

  @override
  State<JoinWithCodeView> createState() => _JoinWithCodeViewState();
}

class _JoinWithCodeViewState extends State<JoinWithCodeView> {
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onJoin(_codeCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: keyboardInset + 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Find Your Match',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: _ink,
                    ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Enter your session code to join the room.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeCtrl,
                style: const TextStyle(color: _ink),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Session code',
                  hintText: 'AB12',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.error != null) ...[
                const SizedBox(height: 12),
                Text(widget.error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DemoNameForm extends StatefulWidget {
  const DemoNameForm({
    super.key,
    required this.onSubmit,
    this.error,
  });

  final Future<void> Function(String name) onSubmit;
  final String? error;

  @override
  State<DemoNameForm> createState() => _DemoNameFormState();
}

class _DemoNameFormState extends State<DemoNameForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_nameCtrl.text.trim());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: keyboardInset + 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Enter your name',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: _ink,
                      ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'We save it to the demo session so the story action can use the right name.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _ink),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: _ink),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Enter your name';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Avery',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (widget.error != null) ...[
                  const SizedBox(height: 12),
                  Text(widget.error!,
                      style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(_submitting ? 'Joining demo...' : 'Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SignupForm extends StatefulWidget {
  const SignupForm({
    super.key,
    required this.sessionId,
    required this.onSubmit,
    this.error,
  });

  final String sessionId;
  final Future<void> Function(SignupPayload payload) onSubmit;
  final String? error;

  @override
  State<SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends State<SignupForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  late final TapGestureRecognizer _termsRecognizer;
  bool _acceptedTermsAndGameTexts = false;
  bool _acceptedPromoTexts = false;
  bool _showTermsValidationError = false;
  bool _submitting = false;
  bool _verifyingPhone = false;
  bool _phoneVerified = false;

  static final Uri _termsUri =
      Uri.parse('https://playyoume.com/termsandconditions');

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()..onTap = _openTermsAndConditions;
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyPhoneWithGoogle() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your phone number first.')),
      );
      return;
    }

    if (!AppFirebase.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Phone verification is not configured yet.')),
      );
      return;
    }

    setState(() => _verifyingPhone = true);
    try {
      if (kIsWeb) {
        final confirmation =
            await FirebaseAuth.instance.signInWithPhoneNumber(phone);
        final codeCtrl = TextEditingController();
        final smsCode = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Enter verification code'),
            content: TextField(
              controller: codeCtrl,
              style: const TextStyle(color: _textBoxTextColor),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'SMS code'),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, codeCtrl.text.trim()),
                  child: const Text('Verify')),
            ],
          ),
        );
        if (smsCode == null || smsCode.isEmpty) return;
        await confirmation.confirm(smsCode);
      } else {
        throw UnimplementedError(
            'Phone verification is currently available on web in this build.');
      }
      if (!mounted) return;
      setState(() => _phoneVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number verified.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Phone verification failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _verifyingPhone = false);
    }
  }

  Future<void> _submit() async {
    final isFormValid = _formKey.currentState!.validate();
    if (!_acceptedTermsAndGameTexts) {
      setState(() {
        _showTermsValidationError = true;
      });
    }
    if (!_phoneVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please verify your phone number first.')),
      );
    }
    if (!isFormValid || !_acceptedTermsAndGameTexts || !_phoneVerified) return;

    setState(() => _submitting = true);

    await widget.onSubmit(
      SignupPayload(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        acceptedTermsAndGameTexts: _acceptedTermsAndGameTexts,
        acceptedPromoTexts: _acceptedPromoTexts,
        roundPreference: RoundPreference.openingUp,
      ),
    );

    if (mounted) {
      setState(() => _submitting = false);
    }
  }

  Future<void> _openTermsAndConditions() async {
    final launched = await launchUrl(
      _termsUri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open Terms and Conditions right now.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: keyboardInset + 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Join YouMe',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _ink,
                  ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Add your details so we can place you in the next round.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _ink),
            ),
            const SizedBox(height: 24),
            _input(_nameCtrl, 'Name'),
            const SizedBox(height: 12),
            _input(_phoneCtrl, 'Phone number', phone: true),
            const SizedBox(height: 10),
            _BlurMixButton(
              onPressed: _verifyingPhone ? null : _verifyPhoneWithGoogle,
              seed: 'verify-phone-number',
              width: double.infinity,
              label: _phoneVerified ? 'Phone verified' : 'Verify phone',
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _acceptedTermsAndGameTexts,
                  fillColor: WidgetStateProperty.all(Colors.white),
                  checkColor: Colors.black,
                  onChanged: (value) {
                    setState(() {
                      _acceptedTermsAndGameTexts = value ?? false;
                      if (_acceptedTermsAndGameTexts) {
                        _showTermsValidationError = false;
                      }
                    });
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 14,
                            height: 1.2,
                          ),
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms and Conditions',
                              recognizer: _termsRecognizer,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 14,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_showTermsValidationError && !_acceptedTermsAndGameTexts)
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text(
                  'Required',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _acceptedPromoTexts,
                  fillColor: WidgetStateProperty.all(Colors.white),
                  checkColor: Colors.black,
                  onChanged: (value) {
                    setState(() {
                      _acceptedPromoTexts = value ?? false;
                    });
                  },
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'I agree to receive promotional text messages.',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.error != null) ...[
              const SizedBox(height: 12),
              Text(widget.error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 18),
            _BlurMixButton(
              onPressed: _submitting ? null : _submit,
              seed: 'signup-and-authenticate',
              width: double.infinity,
              label: _submitting ? 'Joining...' : 'Join the session',
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController controller, String label,
      {bool phone = false}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: _ink),
      keyboardType: phone ? TextInputType.phone : TextInputType.text,
      validator: (value) =>
          (value == null || value.trim().isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(color: _ink),
        floatingLabelStyle: const TextStyle(color: _ink),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class LoveQuote {
  const LoveQuote({required this.quote, required this.author});

  final String quote;
  final String author;

  factory LoveQuote.fromJson(Map<String, dynamic> json) {
    return LoveQuote(
      quote: (json['quote'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
    );
  }
}

class LoveQuotesRepository {
  static List<LoveQuote>? _cachedQuotes;

  static Future<LoveQuote> pickRandomQuote() async {
    _cachedQuotes ??= await _loadQuotes();
    if (_cachedQuotes!.isEmpty) {
      return const LoveQuote(
        quote: 'Love looks not with the eyes, but with the mind.',
        author: 'Billy S. (William Shakespeare)',
      );
    }
    return _cachedQuotes![Random().nextInt(_cachedQuotes!.length)];
  }

  static Future<List<LoveQuote>> _loadQuotes() async {
    final raw = await rootBundle.loadString('assets/love_quotes.json');
    final parsed = jsonDecode(raw);
    if (parsed is! List) return const <LoveQuote>[];
    return parsed
        .whereType<Map>()
        .map((item) => LoveQuote.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}

class WaitingView extends StatefulWidget {
  const WaitingView({
    super.key,
    required this.player,
    required this.session,
    this.error,
  });

  final PlayerRecord? player;
  final SessionRecord? session;
  final String? error;

  @override
  State<WaitingView> createState() => _WaitingViewState();
}

class _WaitingViewState extends State<WaitingView>
    with TickerProviderStateMixin {
  late final AnimationController _dropController;
  late final Animation<double> _dropCurve;
  late final Animation<double> _dropYOffset;
  late final Animation<double> _dropXOffset;
  late final Animation<double> _dropRotation;
  late final Animation<double> _dropScale;

  @override
  void initState() {
    super.initState();
    _dropController = AnimationController(
      vsync: this,
      duration: _cardDropDuration,
      value: 1,
    );
    _dropCurve =
        CurvedAnimation(parent: _dropController, curve: Curves.easeOutQuart);
    _dropYOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: -220.0, end: -8.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 72,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -8.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 28,
      ),
    ]).animate(_dropCurve);
    _dropXOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: -38.0, end: 16.0)
            .chain(CurveTween(curve: Curves.easeOutQuart)),
        weight: 58,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 16.0, end: -11.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 24,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -11.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
    ]).animate(_dropCurve);
    _dropRotation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.28, end: -0.16)
            .chain(CurveTween(curve: Curves.easeOutQuart)),
        weight: 56,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.16, end: 0.07)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 24,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.07, end: -0.03)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
    ]).animate(_dropCurve);
    _dropScale = Tween(begin: 0.94, end: 1.0)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_dropCurve);
    _dropController
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _dropController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundBodyStyle = _backgroundBodyStyle(context);
    return DefaultTextStyle.merge(
      style: backgroundBodyStyle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Waiting Room',
            textAlign: TextAlign.center,
            style: _backgroundHeadlineStyle(context),
          ),
          const SizedBox(height: 16),
          FutureBuilder<LoveQuote>(
            future: LoveQuotesRepository.pickRandomQuote(),
            builder: (context, snapshot) {
              final hasQuote = snapshot.hasData;
              final quote = snapshot.data;
              final quoteCard = _QuotePromptCard(
                width: _waitingQuoteCardWidth,
                height: _waitingQuoteCardHeight,
                quote: hasQuote
                    ? '“${quote!.quote}”'
                    : 'Finding a quote for the room...',
                author: hasQuote ? '- ${quote!.author}' : '',
                seed: hasQuote ? quote!.quote : 'loading-quote',
              );
              return Center(
                child: SizedBox(
                  width: _waitingQuoteCanvasWidth,
                  height: _waitingQuoteCanvasHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..translateByDouble(-14, 8, 0, 1)
                            ..rotateZ(-0.12),
                          child: Opacity(
                            opacity: 0.9,
                            child: _QuotePromptCard(
                              width: _waitingQuoteCardWidth,
                              height: _waitingQuoteCardHeight,
                              quote: '',
                              author: '',
                              seed: 'waiting-stack-back-left',
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..translateByDouble(10, 12, 0, 1)
                            ..rotateZ(0.08),
                          child: Opacity(
                            opacity: 0.86,
                            child: _QuotePromptCard(
                              width: _waitingQuoteCardWidth,
                              height: _waitingQuoteCardHeight,
                              quote: '',
                              author: '',
                              seed: 'waiting-stack-back-right',
                            ),
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _dropController,
                        child: quoteCard,
                        builder: (context, child) {
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.001)
                              ..translateByDouble(
                                _dropXOffset.value,
                                _dropYOffset.value,
                                0,
                                1,
                              )
                              ..rotateZ(_dropRotation.value)
                              ..scaleByDouble(
                                  _dropScale.value, _dropScale.value, 1, 1),
                            child: child,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 28),
          const Center(child: _HeartTimerLoader()),
          const SizedBox(height: 12),
          const Center(
            child: Text('We are getting the next round ready.'),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 12),
            Text(widget.error!, style: const TextStyle(color: Colors.red)),
          ]
        ],
      ),
    );
  }
}

class GameView extends StatefulWidget {
  const GameView({
    super.key,
    required this.sessionId,
    required this.player,
    required this.session,
    required this.onSubmitCode,
    required this.onDrawPrompt,
    required this.onAskSameQuestion,
    required this.onContinueInteraction,
    required this.promptCatalog,
    this.storyPromptCatalogService,
    this.storyCardDealer,
    this.storyRtdbService,
    required this.unpairedInstructions,
    required this.codeEntryPrompt,
    this.onEndInteraction,
    this.error,
    this.forceMatchingMode = false,
    this.showInviteCodeCard = false,
    this.onRoundComplete,
  });

  final String? sessionId;
  final PlayerRecord? player;
  final SessionRecord? session;
  final Future<void> Function(String code) onSubmitCode;
  final Future<void> Function({
    required int promptIndex,
    required String partnerId,
  }) onDrawPrompt;
  final Future<void> Function() onAskSameQuestion;
  final Future<void> Function() onContinueInteraction;
  final Future<void> Function()? onEndInteraction;
  final PromptCatalog? promptCatalog;
  final StoryPromptCatalogService? storyPromptCatalogService;
  final StoryPromptCardDealer? storyCardDealer;
  final RtdbService? storyRtdbService;
  final String unpairedInstructions;
  final String codeEntryPrompt;
  final String? error;
  final bool forceMatchingMode;
  final bool showInviteCodeCard;
  final VoidCallback? onRoundComplete;

  @override
  State<GameView> createState() => _GameViewState();
}

enum _InteractionDecision { keepGoing, endInteraction }

class _GameViewState extends State<GameView> with TickerProviderStateMixin {
  final _codeCtrl = TextEditingController();
  final Set<String> _readyStoryPairIds = <String>{};
  final Set<String> _dismissedStoryPairIds = <String>{};
  static const List<
      ({
        double dx,
        double dy,
        double rotation,
        double opacity,
      })> _promptStackTransforms = [
    (dx: -18, dy: 18, rotation: -0.13, opacity: 0.74),
    (dx: 13, dy: 13, rotation: 0.1, opacity: 0.82),
    (dx: -8, dy: 9, rotation: -0.06, opacity: 0.9),
    (dx: 5, dy: 5, rotation: 0.04, opacity: 0.96),
  ];
  bool _submitting = false;
  bool _interactionEnded = false;
  int? _seenRound;
  int _animatedPromptIndex = 0;
  bool _hasStartedPromptDrop = false;
  String? _activeStoryRoutePairId;
  Route<void>? _storyRoute;
  String? _shownInstructionsKey;
  Timer? _nextCardTimer;
  int _nextCardCooldown = 0;

  late final AnimationController _dropController;
  late final Animation<double> _dropCurve;
  late final Animation<double> _dropYOffset;
  late final Animation<double> _dropXOffset;
  late final Animation<double> _dropRotation;
  late final Animation<double> _dropScale;

  Widget _buildPromptStackScene({
    required List<PromptItem> prompts,
    required PlayerRecord? player,
    required Widget topCard,
    required bool animateTopCard,
  }) {
    final completedCardCount =
        min(max(player?.currentPromptIndex ?? 0, 0), prompts.length);

    Widget buildCompletedStackCard(int stackIndex) {
      final transform = _promptStackTransforms[
          min(stackIndex, _promptStackTransforms.length - 1)];
      final promptId = prompts[stackIndex].id;
      return Center(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(transform.dx, transform.dy, 0, 1)
            ..rotateZ(transform.rotation),
          child: Opacity(
            opacity: transform.opacity,
            child: KeyedSubtree(
              key: ValueKey('prompt-stack-card-$stackIndex'),
              child: _PaperCard(
                width: _gamePromptCardWidth,
                height: _gamePromptCardHeight,
                prompt: '',
                seed:
                    '$promptId-stack-$stackIndex-${player?.id ?? 'prompt-stack'}',
              ),
            ),
          ),
        ),
      );
    }

    Widget buildTopCard() {
      if (!animateTopCard) {
        return Center(child: topCard);
      }

      return AnimatedBuilder(
        animation: _dropController,
        child: topCard,
        builder: (context, child) {
          return Center(
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..translateByDouble(
                  _dropXOffset.value,
                  _dropYOffset.value,
                  0,
                  1,
                )
                ..rotateZ(_dropRotation.value)
                ..scaleByDouble(
                  _dropScale.value,
                  _dropScale.value,
                  1,
                  1,
                ),
              child: child,
            ),
          );
        },
      );
    }

    return Center(
      child: SizedBox(
        width: _gamePromptCanvasWidth,
        height: _gamePromptCanvasHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var index = 0; index < completedCardCount; index += 1)
              buildCompletedStackCard(index),
            if (_hasStartedPromptDrop) buildTopCard(),
          ],
        ),
      ),
    );
  }

  String? _storyPairIdFor(PlayerRecord? player, int? sessionRound) {
    if (widget.sessionId == null ||
        player == null ||
        player.pairedWith == null ||
        sessionRound == null ||
        !_isSharedStoryStage(player)) {
      return null;
    }

    return buildStoryPairId(
      sessionId: widget.sessionId!,
      playerId: player.id,
      partnerId: player.pairedWith!,
      pairRound: player.pairedRound ?? sessionRound,
    );
  }

  void _markStoryReady(String pairId) {
    if (!mounted) return;
    setState(() {
      _readyStoryPairIds.add(pairId);
    });
  }

  void _openStoryPage({
    bool force = false,
  }) {
    final player = widget.player;
    final sessionRound = widget.session?.round;
    final pairId = _storyPairIdFor(player, sessionRound);
    if (pairId == null ||
        player == null ||
        player.pairedWith == null ||
        widget.sessionId == null) {
      return;
    }
    if (!force && _dismissedStoryPairIds.contains(pairId)) {
      return;
    }
    if (_activeStoryRoutePairId == pairId) {
      return;
    }

    final pairRound = player.pairedRound ?? sessionRound!;
    final storyRtdbService = widget.storyRtdbService ?? RtdbService();
    final storyPromptCatalogService = widget.storyPromptCatalogService ??
        DatabaseStoryPromptCatalogService(rtdbService: storyRtdbService);
    final storyCardDealer = widget.storyCardDealer ?? StoryPromptCardDealer();

    _dismissedStoryPairIds.remove(pairId);
    _activeStoryRoutePairId = pairId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final currentPairId =
          _storyPairIdFor(widget.player, widget.session?.round);
      if (currentPairId != pairId) {
        if (_activeStoryRoutePairId == pairId) {
          setState(() {
            _activeStoryRoutePairId = null;
          });
        }
        return;
      }

      final route = MaterialPageRoute<void>(
        builder: (context) => StoryPairSessionPage(
          sessionId: widget.sessionId!,
          player: player,
          partnerId: player.pairedWith!,
          sessionRound: pairRound,
          promptCatalogService: storyPromptCatalogService,
          cardDealer: storyCardDealer,
          rtdbService: storyRtdbService,
          onStoryComplete: () => _markStoryReady(pairId),
        ),
      );
      _storyRoute = route;

      unawaited(
        Navigator.of(context).push(route).whenComplete(() {
          if (!mounted) return;
          setState(() {
            if (_activeStoryRoutePairId == pairId) {
              _activeStoryRoutePairId = null;
            }
            if (_storyRoute == route) {
              _storyRoute = null;
            }
            _dismissedStoryPairIds.add(pairId);
          });
        }),
      );
    });
  }

  void _maybeOpenStoryPage() {
    if (_storyPairIdFor(widget.player, widget.session?.round) == null) {
      return;
    }
    _openStoryPage();
  }

  void _maybeCloseStoryPage() {
    if (_storyRoute == null ||
        _storyPairIdFor(widget.player, widget.session?.round) != null) {
      return;
    }

    final route = _storyRoute!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (!route.isActive) return;
      navigator.removeRoute(route);
      if (!mounted) return;
      setState(() {
        if (_storyRoute == route) {
          _storyRoute = null;
        }
        _activeStoryRoutePairId = null;
      });
    });
  }

  @override
  void didUpdateWidget(covariant GameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final round = widget.session?.round;
    final currentRound = widget.session?.round;
    final oldRound = oldWidget.session?.round;
    final player = widget.player;
    final oldPlayer = oldWidget.player;
    final isPairedThisRound = widget.player?.pairedWith != null &&
        widget.player?.pairedRound != null &&
        widget.player!.pairedRound == currentRound;
    final wasPairedThisRound = oldWidget.player?.pairedWith != null &&
        oldWidget.player?.pairedRound != null &&
        oldWidget.player!.pairedRound == oldRound;
    final prompts = widget.promptCatalog?.resolveIds(
            widget.player?.currentRoundPrompts ?? const <String>[]) ??
        const <PromptItem>[];
    final hadPrompts = (oldWidget.promptCatalog?.resolveIds(
                oldWidget.player?.currentRoundPrompts ?? const <String>[]) ??
            const <PromptItem>[])
        .isNotEmpty;
    final isPlayerTurn = player != null && _isPlayerTurn(player);
    final wasPlayerTurn = oldPlayer != null && _isPlayerTurn(oldPlayer);
    final isSharedStoryStage = player != null && _isSharedStoryStage(player);
    final wasSharedStoryStage =
        oldPlayer != null && _isSharedStoryStage(oldPlayer);

    if (round != _seenRound) {
      _seenRound = round;
      _animatedPromptIndex = 0;
      _hasStartedPromptDrop = false;
      _interactionEnded = false;
      _restartNextCardCooldown();
      if (isPairedThisRound && prompts.isNotEmpty) {
        _playCardDropAnimation();
      }
    }

    final promptIndex = player?.currentPromptIndex ?? 0;
    if (promptIndex != _animatedPromptIndex && isPairedThisRound) {
      _animatedPromptIndex = promptIndex;
      _interactionEnded = false;
      _playCardDropAnimation();
      _restartNextCardCooldown();
    }

    if (isPairedThisRound &&
        prompts.isNotEmpty &&
        (!wasPairedThisRound ||
            !hadPrompts ||
            (!wasPlayerTurn && isPlayerTurn) ||
            (!wasSharedStoryStage && isSharedStoryStage) ||
            (wasPlayerTurn != isPlayerTurn))) {
      _interactionEnded = false;
      _playCardDropAnimation();
      _restartNextCardCooldown();
    }

    _scheduleRoundInstructionsIfNeeded();
    _maybeCloseStoryPage();
    _maybeOpenStoryPage();
  }

  @override
  void initState() {
    super.initState();
    _dropController = AnimationController(
      vsync: this,
      duration: _cardDropDuration,
      value: 1,
    );
    _dropCurve =
        CurvedAnimation(parent: _dropController, curve: Curves.easeOutQuart);
    _dropYOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: -220.0, end: -8.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 72,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -8.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 28,
      ),
    ]).animate(_dropCurve);
    _dropXOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: -38.0, end: 16.0)
            .chain(CurveTween(curve: Curves.easeOutQuart)),
        weight: 58,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 16.0, end: -11.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 24,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -11.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
    ]).animate(_dropCurve);
    _dropRotation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.28, end: -0.16)
            .chain(CurveTween(curve: Curves.easeOutQuart)),
        weight: 56,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.16, end: 0.07)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 24,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.07, end: -0.03)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
    ]).animate(_dropCurve);
    _dropScale = Tween(begin: 0.94, end: 1.0)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_dropCurve);

    final player = widget.player;
    final sessionRound = widget.session?.round;
    final isPairedThisRound = player?.pairedWith != null &&
        player?.pairedRound != null &&
        player!.pairedRound == sessionRound;
    final prompts = widget.promptCatalog
            ?.resolveIds(player?.currentRoundPrompts ?? const <String>[]) ??
        const <PromptItem>[];
    if (isPairedThisRound && prompts.isNotEmpty) {
      _playCardDropAnimation();
    }

    _restartNextCardCooldown();
    _scheduleRoundInstructionsIfNeeded();
    _maybeCloseStoryPage();
    _maybeOpenStoryPage();
  }

  bool _hasStoryModePrompt(PlayerRecord player) {
    return player.currentRoundPrompts.isNotEmpty &&
        player.currentRoundPrompts.last == storyModePromptId;
  }

  int _normalPromptCount(PlayerRecord player) {
    return _hasStoryModePrompt(player)
        ? max(0, player.currentRoundPrompts.length - 1)
        : player.currentRoundPrompts.length;
  }

  bool _hasRemainingNormalPrompt(PlayerRecord player) {
    return player.currentPromptIndex < _normalPromptCount(player);
  }

  bool _isSharedStoryStage(PlayerRecord player) {
    return _hasStoryModePrompt(player) &&
        player.activeTurnPlayerId == null &&
        player.currentPromptIndex >= _normalPromptCount(player);
  }

  bool _isPlayerTurn(PlayerRecord player) {
    return player.activeTurnPlayerId == player.id ||
        (player.activeTurnPlayerId == null &&
            !_isSharedStoryStage(player) &&
            _hasRemainingNormalPrompt(player));
  }

  bool _isWaitingForPartnerTurn(PlayerRecord player) {
    return player.activeTurnPlayerId != null &&
        player.activeTurnPlayerId != player.id &&
        !_isSharedStoryStage(player);
  }

  bool _isInteractionReadyToFinish(PlayerRecord player) {
    return player.activeTurnPlayerId == null &&
        !_isSharedStoryStage(player) &&
        !_hasRemainingNormalPrompt(player);
  }

  String? _instructionKeyForCurrentRound() {
    if (widget.forceMatchingMode) return null;

    final player = widget.player;
    final round = widget.session?.round;
    if (player == null ||
        round == null ||
        player.pairedWith == null ||
        player.pairedRound == null ||
        player.pairedRound != round) {
      return null;
    }

    return '${player.id}:${player.pairedWith}:$round';
  }

  bool _shouldShowFirstMatchInstructions() {
    final player = widget.player;
    if (player == null || player.pairedWith == null) return false;

    // The current partner is added to matchedPlayerIds when a pairing is saved.
    // A length of 0 is kept for local preview flows, so both 0 and 1 mean
    // "this is effectively the first match".
    return player.matchedPlayerIds.length <= 1;
  }

  void _scheduleRoundInstructionsIfNeeded() {
    final instructionKey = _instructionKeyForCurrentRound();
    if (instructionKey == null ||
        !_shouldShowFirstMatchInstructions() ||
        _shownInstructionsKey == instructionKey ||
        !mounted) {
      return;
    }

    _shownInstructionsKey = instructionKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_showRoundInstructionsDialog());
    });
  }

  Future<void> _showRoundInstructionsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 360,
              maxHeight: mediaQuery.size.height * 0.78,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _offWhite,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _panelStroke),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This round',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: SingleChildScrollView(
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cards alternate between the two of you. Finish the active card before passing the turn.',
                              style: TextStyle(color: _ink, height: 1.35),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Only the active player sees their next card. Read it out loud and answer before moving on.',
                              style: TextStyle(color: _ink, height: 1.35),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'When it is not your turn, you can ask the same question, but your next turn will be skipped.',
                              style: TextStyle(color: _ink, height: 1.35),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'If the cards do not load right away, ask the other person to enter your code too.',
                              style: TextStyle(color: _ink, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Got it'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _playCardDropAnimation() {
    _hasStartedPromptDrop = true;
    _dropController
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nextCardTimer?.cancel();
    _dropController.dispose();
    super.dispose();
  }

  void _restartNextCardCooldown() {
    _nextCardTimer?.cancel();
    final player = widget.player;
    final hasPromptAction = player != null &&
        (_isPlayerTurn(player) ||
            _isSharedStoryStage(player) ||
            _isInteractionReadyToFinish(player));

    if (!hasPromptAction) {
      if (_nextCardCooldown != 0 && mounted) {
        setState(() => _nextCardCooldown = 0);
      }
      return;
    }

    setState(() => _nextCardCooldown = 15);
    _nextCardTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_nextCardCooldown <= 1) {
        timer.cancel();
        setState(() => _nextCardCooldown = 0);
      } else {
        setState(() => _nextCardCooldown -= 1);
      }
    });
  }

  Future<void> _submitCode() async {
    if (_codeCtrl.text.trim().length < 4) return;
    setState(() => _submitting = true);
    await widget.onSubmitCode(_codeCtrl.text);
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _drawNextPrompt() async {
    final player = widget.player;
    final prompts = widget.promptCatalog
            ?.resolveIds(player?.currentRoundPrompts ?? const <String>[]) ??
        const <PromptItem>[];
    final currentRound = widget.session?.round;
    if (player == null ||
        player.pairedWith == null ||
        currentRound == null ||
        prompts.isEmpty ||
        !_isPlayerTurn(player) ||
        !_hasRemainingNormalPrompt(player) ||
        _nextCardCooldown > 0) {
      return;
    }

    final nextIndex = player.currentPromptIndex + 1;
    if (nextIndex > prompts.length) return;

    setState(() => _submitting = true);
    _restartNextCardCooldown();
    await widget.onDrawPrompt(
      promptIndex: nextIndex,
      partnerId: player.pairedWith!,
    );
    if (mounted) {
      setState(() => _submitting = false);
    }
  }

  Future<void> _askSameQuestion() async {
    if (_submitting) return;

    setState(() => _submitting = true);
    try {
      await widget.onAskSameQuestion();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  bool _isWaitingForPartnerDecision() {
    final player = widget.player;
    final currentRound = widget.session?.round;
    return !widget.forceMatchingMode &&
        player != null &&
        player.pairedWith != null &&
        player.pairedRound == currentRound &&
        player.interactionRound < _finalInteractionRound &&
        player.continueVoteRound == _continueVoteRound;
  }

  Future<void> _handleEndInteraction() async {
    if (_isWaitingForPartnerDecision()) return;

    final canContinue =
        (widget.player?.interactionRound ?? _initialInteractionRound) <
            _finalInteractionRound;
    final decision = await showDialog<_InteractionDecision>(
      context: context,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 360,
              maxHeight: mediaQuery.size.height * 0.72,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _offWhite,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _panelStroke),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      canContinue ? 'End interaction?' : 'This was round 2',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Text(
                          canContinue
                              ? 'If you both tap keep going, round 2 will unlock.'
                              : 'Round 2 is the last round. Finish when you are ready.',
                          style: const TextStyle(color: _ink, height: 1.35),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (canContinue) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(_InteractionDecision.keepGoing),
                          child: const Text('Keep going'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: canContinue
                          ? OutlinedButton(
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(_InteractionDecision.endInteraction),
                              child: const Text('End interaction'),
                            )
                          : FilledButton(
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(_InteractionDecision.endInteraction),
                              child: const Text('Finish interaction'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || decision == null) return;

    switch (decision) {
      case _InteractionDecision.keepGoing:
        setState(() => _submitting = true);
        try {
          await widget.onContinueInteraction();
        } finally {
          if (mounted) {
            setState(() => _submitting = false);
          }
        }
        return;
      case _InteractionDecision.endInteraction:
        if (widget.onEndInteraction != null) {
          setState(() => _submitting = true);
          try {
            await widget.onEndInteraction!();
          } finally {
            if (mounted) {
              setState(() => _submitting = false);
            }
          }
        } else if (widget.onRoundComplete != null) {
          widget.onRoundComplete!();
        } else if (mounted) {
          setState(() {
            _interactionEnded = true;
          });
        }
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final player = widget.player;
    final backgroundBodyStyle = _backgroundBodyStyle(context);
    final currentRound = widget.session?.round;
    final isPairedThisRound = !widget.forceMatchingMode &&
        player?.pairedWith != null &&
        player?.pairedRound != null &&
        player!.pairedRound == currentRound;
    final prompts = widget.promptCatalog
            ?.resolveIds(player?.currentRoundPrompts ?? const <String>[]) ??
        const <PromptItem>[];
    final pairedPlayer = isPairedThisRound ? player : null;
    final isPlayerTurn = pairedPlayer != null && _isPlayerTurn(pairedPlayer);
    final isWaitingForPartnerTurn =
        pairedPlayer != null && _isWaitingForPartnerTurn(pairedPlayer);
    final isSharedStoryStage =
        pairedPlayer != null && _isSharedStoryStage(pairedPlayer);
    final isInteractionReadyToFinish =
        pairedPlayer != null && _isInteractionReadyToFinish(pairedPlayer);
    final promptIndex = prompts.isEmpty
        ? 0
        : isSharedStoryStage
            ? prompts.length - 1
            : (pairedPlayer?.currentPromptIndex ?? 0).clamp(
                0,
                prompts.length - 1,
              );
    final interactionRound =
        player?.interactionRound ?? _initialInteractionRound;
    final isFinalInteractionRound = interactionRound >= _finalInteractionRound;
    final waitingForPartnerDecision =
        isPairedThisRound && _isWaitingForPartnerDecision();
    final endInteractionLabel = waitingForPartnerDecision
        ? 'Waiting for them...'
        : isFinalInteractionRound
            ? 'Finish interaction'
            : 'End interaction';
    final storyCompletedFooter = !_interactionEnded
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _BlurMixButton(
                onPressed: (_submitting ||
                        _nextCardCooldown > 0 ||
                        waitingForPartnerDecision)
                    ? null
                    : _handleEndInteraction,
                seed: 'end-interaction',
                width: 220,
                height: 52,
                fillColor: _nextCardCooldown > 0
                    ? const Color(0xFFD6D0C5)
                    : _primaryButton,
                borderColor: _nextCardCooldown > 0
                    ? const Color(0xFFC2B7A7)
                    : _primaryButton,
                textColor:
                    _nextCardCooldown > 0 ? const Color(0xFF6F655B) : _offWhite,
                textSize: 18,
                textWeight: FontWeight.w800,
                leadingIcon: _nextCardCooldown > 0 ? Icons.lock_outline : null,
                disabledOpacity: _nextCardCooldown > 0 ? 1 : 0.55,
                label: _submitting
                    ? 'Loading...'
                    : waitingForPartnerDecision
                        ? 'Waiting for them...'
                        : _nextCardCooldown > 0
                            ? 'Locked ${_nextCardCooldown}s'
                            : endInteractionLabel,
              ),
            ],
          )
        : null;
    final activePromptCard = prompts.isEmpty ||
            (!isPlayerTurn && !isSharedStoryStage)
        ? null
        : _PaperCard(
            width: _gamePromptCardWidth,
            height: _gamePromptCardHeight,
            prompt: prompts[promptIndex].text,
            seed: '${prompts[promptIndex].id}-$promptIndex-${pairedPlayer.id}',
          );
    final showEmbeddedStoryPanel =
        isSharedStoryStage && widget.sessionId != null;
    final storyPairId = _storyPairIdFor(player, currentRound);
    final hasReadyStory =
        storyPairId != null && _readyStoryPairIds.contains(storyPairId);
    final isOpeningStoryPage =
        storyPairId != null && _activeStoryRoutePairId == storyPairId;

    return DefaultTextStyle.merge(
      style: backgroundBodyStyle,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: keyboardInset + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              isPairedThisRound ? 'YouMe' : 'Find Your Match',
              textAlign: TextAlign.center,
              style: _backgroundHeadlineStyle(context),
            ),
            const SizedBox(height: 12),
            if (!isPairedThisRound)
              Text(
                widget.unpairedInstructions,
                textAlign: TextAlign.center,
                style: backgroundBodyStyle,
              ),
            const SizedBox(height: 20),
            if (isPairedThisRound) ...[
              if (prompts.isNotEmpty) ...[
                if (showEmbeddedStoryPanel) ...[
                  Center(
                    child: _PaperCard(
                      width: _gamePromptCardWidth,
                      height: _gamePromptCardHeight,
                      prompt: hasReadyStory
                          ? 'Your story is ready.\n\nRead it again or end the interaction when you are ready.'
                          : isOpeningStoryPage
                              ? 'Opening your story page now.\n\nStay here if the transition takes a moment.'
                              : 'Your story opens on its own page.\n\nIf it does not appear, open it below.',
                      seed:
                          'story-stage-${player.id}-${player.pairedWith}-${player.pairedRound ?? currentRound ?? 1}',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!hasReadyStory)
                    _BlurMixButton(
                      onPressed: isOpeningStoryPage
                          ? null
                          : () => _openStoryPage(force: true),
                      seed: 'open-story-page',
                      width: 220,
                      height: 52,
                      fillColor: _primaryButton,
                      borderColor: _primaryButton,
                      textColor: _offWhite,
                      textSize: 18,
                      textWeight: FontWeight.w800,
                      disabledOpacity: 0.55,
                      label: isOpeningStoryPage
                          ? 'Opening story...'
                          : 'Open story page',
                    ),
                  if (hasReadyStory && storyCompletedFooter != null) ...[
                    storyCompletedFooter,
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: isOpeningStoryPage
                          ? null
                          : () => _openStoryPage(force: true),
                      child: Text(
                        isOpeningStoryPage
                            ? 'Opening story...'
                            : 'Open story page again',
                      ),
                    ),
                  ],
                  if (waitingForPartnerDecision) ...[
                    const SizedBox(height: 10),
                    Text(
                      'You picked keep going. Round 2 starts only if they do too.',
                      textAlign: TextAlign.center,
                      style: backgroundBodyStyle,
                    ),
                  ],
                ] else if (isPlayerTurn) ...[
                  if (activePromptCard != null)
                    _buildPromptStackScene(
                      prompts: prompts,
                      player: player,
                      topCard: activePromptCard,
                      animateTopCard: true,
                    ),
                  const SizedBox(height: 10),
                  if (!_interactionEnded)
                    _BlurMixButton(
                      onPressed: (_submitting || _nextCardCooldown > 0)
                          ? null
                          : _drawNextPrompt,
                      seed: 'draw-next-card',
                      width: 220,
                      height: 52,
                      fillColor: _nextCardCooldown > 0
                          ? const Color(0xFFD6D0C5)
                          : _primaryButton,
                      borderColor: _nextCardCooldown > 0
                          ? const Color(0xFFC2B7A7)
                          : _primaryButton,
                      textColor: _nextCardCooldown > 0
                          ? const Color(0xFF6F655B)
                          : _offWhite,
                      textSize: 18,
                      textWeight: FontWeight.w800,
                      leadingIcon:
                          _nextCardCooldown > 0 ? Icons.lock_outline : null,
                      disabledOpacity: _nextCardCooldown > 0 ? 1 : 0.55,
                      label: _submitting
                          ? 'Passing turn...'
                          : _nextCardCooldown > 0
                              ? 'Locked ${_nextCardCooldown}s'
                              : 'Pass turn',
                    ),
                ] else if (isWaitingForPartnerTurn) ...[
                  _buildPromptStackScene(
                    prompts: prompts,
                    player: player,
                    topCard: _PaperCard(
                      width: _gamePromptCardWidth,
                      height: _gamePromptCardHeight,
                      prompt: player.skipNextTurn
                          ? 'It is their turn.\n\nAsk the same question if you want to stay on it.\n\nYour next turn will be skipped.'
                          : 'It is their turn.\n\nYou can ask the same question, but your next turn will be skipped.',
                      seed: 'waiting-${player.id}-${player.currentPromptIndex}',
                    ),
                    animateTopCard: false,
                  ),
                  const SizedBox(height: 10),
                  _BlurMixButton(
                    onPressed: (_submitting || player.skipNextTurn)
                        ? null
                        : _askSameQuestion,
                    seed: 'ask-same-question',
                    width: 260,
                    height: 52,
                    fillColor: player.skipNextTurn
                        ? const Color(0xFFD6D0C5)
                        : _primaryButton,
                    borderColor: player.skipNextTurn
                        ? const Color(0xFFC2B7A7)
                        : _primaryButton,
                    textColor: player.skipNextTurn
                        ? const Color(0xFF6F655B)
                        : _offWhite,
                    textSize: 18,
                    textWeight: FontWeight.w800,
                    disabledOpacity: player.skipNextTurn ? 1 : 0.55,
                    label: _submitting
                        ? 'Saving...'
                        : player.skipNextTurn
                            ? 'Next turn skipped'
                            : 'Ask same question',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    player.skipNextTurn
                        ? 'You chose to mirror this question. Your next card will be skipped.'
                        : 'If you want to stay on the same topic, ask the same question and give up your next turn.',
                    textAlign: TextAlign.center,
                    style: backgroundBodyStyle,
                  ),
                ] else if (isInteractionReadyToFinish) ...[
                  _buildPromptStackScene(
                    prompts: prompts,
                    player: player,
                    topCard: _PaperCard(
                      width: _gamePromptCardWidth,
                      height: _gamePromptCardHeight,
                      prompt:
                          'All cards are done.\n\nWrap up the conversation when you are ready.',
                      seed: 'finish-${player.id}-${player.currentPromptIndex}',
                    ),
                    animateTopCard: false,
                  ),
                  const SizedBox(height: 10),
                  if (!_interactionEnded) ...[
                    _BlurMixButton(
                      onPressed: (_submitting ||
                              _nextCardCooldown > 0 ||
                              waitingForPartnerDecision)
                          ? null
                          : _handleEndInteraction,
                      seed: 'end-interaction',
                      width: 220,
                      height: 52,
                      fillColor: _nextCardCooldown > 0
                          ? const Color(0xFFD6D0C5)
                          : _primaryButton,
                      borderColor: _nextCardCooldown > 0
                          ? const Color(0xFFC2B7A7)
                          : _primaryButton,
                      textColor: _nextCardCooldown > 0
                          ? const Color(0xFF6F655B)
                          : _offWhite,
                      textSize: 18,
                      textWeight: FontWeight.w800,
                      leadingIcon:
                          _nextCardCooldown > 0 ? Icons.lock_outline : null,
                      disabledOpacity: _nextCardCooldown > 0 ? 1 : 0.55,
                      label: _submitting
                          ? 'Loading...'
                          : waitingForPartnerDecision
                              ? 'Waiting for them...'
                              : _nextCardCooldown > 0
                                  ? 'Locked ${_nextCardCooldown}s'
                                  : endInteractionLabel,
                    ),
                    if (waitingForPartnerDecision) ...[
                      const SizedBox(height: 10),
                      Text(
                        'You picked keep going. Round 2 starts only if they do too.',
                        textAlign: TextAlign.center,
                        style: backgroundBodyStyle,
                      ),
                    ],
                  ],
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Waiting for the next card...',
                      textAlign: TextAlign.center,
                      style: backgroundBodyStyle,
                    ),
                  ),
                ],
              ] else
                Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Your prompts are still loading. Ask the other person to enter your code too.',
                    textAlign: TextAlign.center,
                    style: backgroundBodyStyle,
                  ),
                ),
            ] else ...[
              if (widget.showInviteCodeCard &&
                  player != null &&
                  player.inviteCode.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: _primaryButton,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _primaryButton),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 14,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Text(
                    player.inviteCode.toUpperCase(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          letterSpacing: 6,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                widget.codeEntryPrompt,
                style: backgroundBodyStyle,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _codeCtrl,
                maxLength: 4,
                style: const TextStyle(color: _ink),
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'AB12',
                ),
              ),
              const SizedBox(height: 8),
              _BlurMixButton(
                onPressed: _submitting ? null : _submitCode,
                seed: 'pair-for-round',
                width: double.infinity,
                label: _submitting ? 'Joining...' : 'Start',
              )
            ],
            if (widget.error != null) ...[
              const SizedBox(height: 12),
              Text(widget.error!, style: const TextStyle(color: Colors.red)),
            ]
          ],
        ),
      ),
    );
  }
}

class EndedView extends StatelessWidget {
  const EndedView({super.key, required this.players});

  final List<PlayerRecord> players;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: _ink) ??
        const TextStyle(color: _ink);

    return DefaultTextStyle.merge(
      style: bodyStyle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Round Results',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _ink,
                ),
          ),
          const SizedBox(height: 12),
          const Text('This round is complete.'),
          const SizedBox(height: 20),
          if (players.isEmpty)
            const Text(
                'Thanks for being here. Take a breath, reset, and enjoy the rest of the event.')
          else ...[
            const Text('These are the people who also want to keep talking:'),
            const SizedBox(height: 8),
            const Text('Follow up while the conversation is still fresh.'),
            const SizedBox(height: 12),
            ...players.map(
              (player) => Card(
                color: _offWhite,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: _panelStroke),
                ),
                child: ListTile(
                  leading: const Text('👍', style: TextStyle(fontSize: 20)),
                  title: Text(
                    player.name.isEmpty ? 'Another player' : player.name,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: _ink),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(message, style: const TextStyle(color: Colors.red)),
        ),
      ),
    );
  }
}

class _ContentPanel extends StatelessWidget {
  const _ContentPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 356),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _panelColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _panelStroke),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 28,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: child,
          ),
        ),
      ),
    );
  }
}

class ParticleSplashPainter extends CustomPainter {
  const ParticleSplashPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;
    final particles = 20;

    for (var i = 0; i < particles; i++) {
      final angle = (2 * pi * i) / particles;
      final distance = 18 + (progress * 105);
      final wobble = sin(progress * 8 + i) * 6;
      final offset = Offset(
        cos(angle) * (distance + wobble),
        sin(angle) * (distance + wobble),
      );
      final alpha = ((1 - progress) * 255).toInt().clamp(0, 255);
      paint.color =
          (i.isEven ? _ink : const Color(0xFF5C513D)).withAlpha(alpha);
      canvas.drawCircle(center + offset, 2 + (1 - progress) * 4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticleSplashPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _PaperCard extends StatelessWidget {
  const _PaperCard({
    required this.width,
    required this.height,
    required this.prompt,
    required this.seed,
  });

  final double width;
  final double height;
  final String prompt;
  final String seed;
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: width / height,
          child: Container(
            decoration: BoxDecoration(
              color: _offWhite,
              borderRadius: BorderRadius.circular(9),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 18,
                  offset: Offset(0, 10),
                  color: Color(0x33000000),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _ChatGptTextureBackdrop(
                          seed: seed,
                          minScale: 1,
                          maxScale: 1.2,
                          applyTintOverlay: false,
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment.center,
                                radius: 0.9,
                                colors: [
                                  Color(0xD12A2A2A),
                                  Color(0xA61A1A1A),
                                  Color(0x4D0D0D0D),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color(0xAAFFFFFF), width: 1.2),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                          child: Center(
                            child: _FitPromptText(prompt: prompt),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'YouMe',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'cursive',
                        fontStyle: FontStyle.italic,
                        color: _ink,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuotePromptCard extends StatelessWidget {
  const _QuotePromptCard({
    required this.width,
    required this.height,
    required this.quote,
    required this.author,
    required this.seed,
  });

  final double width;
  final double height;
  final String quote;
  final String author;
  final String seed;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: width / height,
          child: Container(
            decoration: BoxDecoration(
              color: _offWhite,
              borderRadius: BorderRadius.circular(9),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 18,
                  offset: Offset(0, 10),
                  color: Color(0x33000000),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _ChatGptTextureBackdrop(
                          seed: seed,
                          minScale: 1,
                          maxScale: 1.2,
                          applyTintOverlay: false,
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment.center,
                                radius: 0.9,
                                colors: [
                                  Color(0xD12A2A2A),
                                  Color(0xA61A1A1A),
                                  Color(0x4D0D0D0D),
                                ],
                              ),
                            ),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: const Color(0xAAFFFFFF), width: 1.2),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                          child: _FitQuoteText(
                            quote: quote,
                            author: author,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'YouMe',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'cursive',
                        fontStyle: FontStyle.italic,
                        color: _ink,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeartTimerLoader extends StatefulWidget {
  const _HeartTimerLoader();

  @override
  State<_HeartTimerLoader> createState() => _HeartTimerLoaderState();
}

class _HeartTimerLoaderState extends State<_HeartTimerLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Color _toneColor;

  @override
  void initState() {
    super.initState();
    final seed =
        'heart-rate-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
    _toneColor = _toneColorForSeed('$seed-tone');
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 72,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _HeartRateBarPainter(
              progress: _controller.value,
              toneColor: _toneColor,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _HeartRateBarPainter extends CustomPainter {
  const _HeartRateBarPainter({
    required this.progress,
    required this.toneColor,
  });

  final double progress;
  final Color toneColor;

  @override
  void paint(Canvas canvas, Size size) {
    final baselineY = size.height * 0.65;
    final replacementGap = size.width * (0.16 / 3);
    final sweepX = (size.width + replacementGap) * progress;
    final newWaveEndX =
        (sweepX - replacementGap).clamp(0.0, size.width).toDouble();
    final oldWaveStartX = sweepX.clamp(0.0, size.width).toDouble();
    final path = Path()..moveTo(0, baselineY);

    const pulseCount = 2;
    final leadingSegment = size.width * 0.10;
    final trailingSegment = size.width * 0.10;
    final pulseWidth = size.width * 0.20;
    final baseGapWidth = (size.width -
            leadingSegment -
            trailingSegment -
            (pulseWidth * pulseCount)) /
        (pulseCount + 1);
    final gapWidth = baseGapWidth * 0.3;

    double x = leadingSegment + gapWidth;
    path.lineTo(x, baselineY);
    for (var i = 0; i < pulseCount; i++) {
      path
        ..lineTo(x + pulseWidth * 0.30, baselineY)
        ..lineTo(x + pulseWidth * 0.42, baselineY - size.height * 0.30)
        ..lineTo(x + pulseWidth * 0.55, baselineY + size.height * 0.12)
        ..lineTo(x + pulseWidth * 0.70, baselineY - size.height * 0.18)
        ..lineTo(x + pulseWidth, baselineY);

      x += pulseWidth;
      if (i < pulseCount - 1) {
        x += gapWidth;
        path.lineTo(x, baselineY);
      }
    }
    path.lineTo(size.width - trailingSegment, baselineY);
    path.lineTo(size.width, baselineY);

    final waveGlowPaint = Paint()
      ..color = toneColor.withValues(alpha: 0.45)
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

    final wavePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void drawWave({required Rect clipRect}) {
      if (clipRect.width <= 0) return;
      canvas.save();
      canvas.clipRect(clipRect);
      canvas.drawPath(path, waveGlowPaint);
      canvas.drawPath(path, wavePaint);
      canvas.restore();
    }

    drawWave(
      clipRect: Rect.fromLTWH(
          oldWaveStartX, 0, size.width - oldWaveStartX, size.height),
    );

    drawWave(
      clipRect: Rect.fromLTWH(0, 0, newWaveEndX, size.height),
    );
  }

  @override
  bool shouldRepaint(covariant _HeartRateBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.toneColor != toneColor;
  }
}

class _BlurMixButton extends StatelessWidget {
  const _BlurMixButton({
    required this.onPressed,
    required this.label,
    this.seed,
    this.width = _buttonWidth,
    this.height = _buttonHeight,
    this.fillColor = _offWhite,
    this.borderColor = _offWhiteBorder,
    this.textColor = Colors.black,
    this.textSize = 20,
    this.textWeight = FontWeight.w700,
    this.leadingIcon,
    this.disabledOpacity = 0.55,
  });

  static const double _buttonWidth = 230;
  static const double _buttonHeight = 46;

  final VoidCallback? onPressed;
  final String label;
  final String? seed;
  final double width;
  final double height;
  final Color fillColor;
  final Color borderColor;
  final Color textColor;
  final double textSize;
  final FontWeight textWeight;
  final IconData? leadingIcon;
  final double disabledOpacity;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? disabledOpacity : 1,
      child: SizedBox(
        width: width,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: Ink(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (leadingIcon != null) ...[
                        Icon(leadingIcon,
                            size: textSize * 0.9, color: textColor),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: textColor,
                                    fontWeight: textWeight,
                                    fontSize: textSize,
                                    height: 1.1,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FitPromptText extends StatelessWidget {
  const _FitPromptText({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final baseStyle = _textOnBackgroundStyle(
      Theme.of(context).textTheme.titleLarge ?? const TextStyle(fontSize: 24),
      fontWeight: FontWeight.w800,
      height: 1.12,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final selectedSize = _largestFittingFontSize(
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          maxFont: 24,
          minFont: 12,
          textBuilder: (fontSize) => TextSpan(
            text: prompt,
            style: baseStyle.copyWith(fontSize: fontSize),
          ),
        );
        return Text(
          prompt,
          textAlign: TextAlign.center,
          softWrap: true,
          style: baseStyle.copyWith(fontSize: selectedSize),
        );
      },
    );
  }
}

class _FitQuoteText extends StatelessWidget {
  const _FitQuoteText({
    required this.quote,
    required this.author,
  });

  final String quote;
  final String author;

  @override
  Widget build(BuildContext context) {
    final quoteStyle = _textOnBackgroundStyle(
      Theme.of(context).textTheme.titleLarge ?? const TextStyle(fontSize: 24),
      fontWeight: FontWeight.w800,
      height: 1.12,
    );
    final authorStyle = _textOnBackgroundStyle(
      Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12),
      fontWeight: FontWeight.w700,
      height: 1.25,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final selectedQuoteSize = _largestFittingFontSize(
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          maxFont: 24,
          minFont: 12,
          textBuilder: (quoteFontSize) => _buildSpan(
            quoteStyle: quoteStyle,
            authorStyle: authorStyle,
            quoteFontSize: quoteFontSize,
          ),
        );

        return Text.rich(
          _buildSpan(
            quoteStyle: quoteStyle,
            authorStyle: authorStyle,
            quoteFontSize: selectedQuoteSize,
          ),
          textAlign: TextAlign.center,
          softWrap: true,
        );
      },
    );
  }

  TextSpan _buildSpan({
    required TextStyle quoteStyle,
    required TextStyle authorStyle,
    required double quoteFontSize,
  }) {
    final authorFontSize = max(10.0, quoteFontSize * 0.48);
    return TextSpan(
      children: [
        TextSpan(
          text: quote,
          style: quoteStyle.copyWith(fontSize: quoteFontSize),
        ),
        if (author.isNotEmpty)
          TextSpan(
            text: '\n\n$author',
            style: authorStyle.copyWith(fontSize: authorFontSize),
          ),
      ],
    );
  }
}

class _BlurMixBackdrop extends StatefulWidget {
  const _BlurMixBackdrop({required this.seed});

  final String seed;

  @override
  State<_BlurMixBackdrop> createState() => _BlurMixBackdropState();
}

class _BlurMixBackdropState extends State<_BlurMixBackdrop> {
  late final String _instanceSeed;

  @override
  void initState() {
    super.initState();
    final instanceSalt =
        DateTime.now().microsecondsSinceEpoch + Random().nextInt(1 << 20);
    _instanceSeed = '${widget.seed}-$instanceSalt';
  }

  @override
  Widget build(BuildContext context) {
    return _ChatGptTextureBackdrop(seed: _instanceSeed);
  }
}

class _ChatGptTextureBackdrop extends StatelessWidget {
  const _ChatGptTextureBackdrop({
    required this.seed,
    this.textureAsset,
    this.minScale = 5.2,
    this.maxScale = 7.6,
    this.gradientOpacity = 1,
    this.applyTintOverlay = true,
  });

  final String seed;
  final String? textureAsset;
  final double minScale;
  final double maxScale;
  final double gradientOpacity;
  final bool applyTintOverlay;

  @override
  Widget build(BuildContext context) {
    final rng = Random(seed.hashCode & 0x7fffffff);
    final resolvedTextureAsset = textureAsset ?? _textureAssetForSeed(seed);
    final toneColor = _toneColorForSeed('$seed-tone');
    final alignment = Alignment(
      -1 + (rng.nextDouble() * 2),
      -1 + (rng.nextDouble() * 2),
    );
    final rotation = (rng.nextDouble() * 2 - 1) * (pi / 24);
    final scale = minScale + (rng.nextDouble() * (maxScale - minScale));
    final blurSigma = 1.4 + (rng.nextDouble() * 1.4);
    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ??
            View.of(context).devicePixelRatio;
        final targetDecodeWidth = _targetTextureDecodeWidth(
          constraints: constraints,
          devicePixelRatio: devicePixelRatio,
          scale: scale,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: ImageFiltered(
                imageFilter:
                    ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: Transform.rotate(
                  angle: rotation,
                  child: Transform.scale(
                    scale: scale,
                    child: Image.asset(
                      resolvedTextureAsset,
                      fit: BoxFit.cover,
                      alignment: alignment,
                      cacheWidth: targetDecodeWidth,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
                ),
              ),
            ),
            if (applyTintOverlay)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.alphaBlend(
                        toneColor.withValues(alpha: 0.24 * gradientOpacity),
                        Colors.black.withValues(alpha: 0.36),
                      ),
                      Color.alphaBlend(
                        toneColor.withValues(alpha: 0.34 * gradientOpacity),
                        Colors.black.withValues(alpha: 0.62),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class RippedPaperClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(0, 8);
    final rng = Random(7);

    for (double x = 0; x <= size.width; x += 16) {
      path.lineTo(x, rng.nextDouble() * 7);
    }
    for (double y = 0; y <= size.height; y += 14) {
      path.lineTo(size.width - (rng.nextDouble() * 8), y);
    }
    for (double x = size.width; x >= 0; x -= 16) {
      path.lineTo(x, size.height - (rng.nextDouble() * 8));
    }
    for (double y = size.height; y >= 0; y -= 14) {
      path.lineTo(rng.nextDouble() * 8, y);
    }

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class FilmOverlay extends StatefulWidget {
  const FilmOverlay({super.key});

  @override
  State<FilmOverlay> createState() => _FilmOverlayState();
}

class _FilmOverlayState extends State<FilmOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flickerController;

  @override
  void initState() {
    super.initState();
    _flickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() {
    _flickerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: FilmGrainPainter(animation: _flickerController),
      ),
    );
  }
}

class FilmGrainPainter extends CustomPainter {
  FilmGrainPainter({required this.animation}) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = animation.value;
    final flickerStrength = 0.025 + (sin(frame * pi * 4) + 1) * 0.008;

    final exposureFlicker = Paint()
      ..color = _paper.withValues(alpha: flickerStrength);
    canvas.drawRect(Offset.zero & size, exposureFlicker);

    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          _ink.withValues(alpha: 0.1),
        ],
        stops: const [0.5, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, vignette);

    final noise = Paint()..color = _ink.withValues(alpha: 0.035);
    for (double y = 0; y < size.height; y += 6) {
      final start = (sin(y * 0.2) + 1) * 8;
      canvas.drawLine(Offset(start, y), Offset(size.width - start, y), noise);
    }

    final bloomColors = <Color>[
      const Color(0xFFEAC5FF),
      const Color(0xFF9BD7FF),
      const Color(0xFFFFC6A8),
      const Color(0xFFC0F4C8),
    ];

    for (var i = 0; i < bloomColors.length; i++) {
      final phase = frame * pi * 2;
      final bloomPhaseOffset = i * pi / 2;
      final center = Offset(
        size.width * (0.2 + (i * 0.18)) + sin(phase + bloomPhaseOffset) * 20,
        size.height * (0.25 + (i.isEven ? 0.1 : 0.45)) +
            cos((phase * 2) + bloomPhaseOffset) * 18,
      );
      final bloomRadius = 56 + sin((phase * 3) + bloomPhaseOffset) * 10;
      final bloomPaint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26)
        ..color = bloomColors[i].withValues(alpha: 0.12);
      canvas.drawCircle(center, bloomRadius, bloomPaint);
    }

    final dustPaint = Paint()..style = PaintingStyle.fill;
    final dustSeed = (frame * 1000).floor();
    final random = Random(dustSeed);
    for (var i = 0; i < 18; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = 0.4 + random.nextDouble() * 1.2;
      final opacity = 0.04 + random.nextDouble() * 0.06;
      dustPaint.color = _ink.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, dustPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FilmGrainPainter oldDelegate) {
    return oldDelegate.animation.value != animation.value;
  }
}
