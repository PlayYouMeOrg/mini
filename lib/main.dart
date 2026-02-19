import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session_domain.dart';

const _creme = Color(0xFFF5F4EF);
const _paper = Color(0xFFECEAE2);
const _ink = Color(0xFF070707);
const _gameViewportSize = Size(390, 844);

void main() {
  runApp(const MiniApp());
}

class MiniApp extends StatelessWidget {
  const MiniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Session Joiner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _ink,
          brightness: Brightness.light,
        ).copyWith(
          primary: _ink,
          surface: _paper,
        ),
        scaffoldBackgroundColor: _creme,
        textTheme: Typography.blackMountainView.apply(
          bodyColor: _ink,
          displayColor: _ink,
        ),
        inputDecorationTheme: InputDecorationTheme(
          fillColor: _paper,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _ink),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF1D1B1B)),
          ),
        ),
      ),
      home: const SessionFlowPage(),
    );
  }
}

enum Stage { signup, waiting, game, ended }

class SessionFlowPage extends StatefulWidget {
  const SessionFlowPage({super.key});

  @override
  State<SessionFlowPage> createState() => _SessionFlowPageState();
}

class _SessionFlowPageState extends State<SessionFlowPage> {
  final _service = RtdbService();
  final _firestoreService = FirestoreSignupService();
  final _promptCatalogService = PromptCatalogService();
  final _sessionStore = SessionStateStore();

  Stage _stage = Stage.signup;
  String? _sessionId;
  String? _playerId;
  PlayerRecord? _player;
  SessionRecord? _session;
  String? _error;
  Timer? _poller;
  String? _initialSessionStatus;
  PromptCatalog? _promptCatalog;
  List<PlayerRecord> _mutualSeeAgainPlayers = const <PlayerRecord>[];

  @override
  void initState() {
    super.initState();
    _sessionId = Uri.base.queryParameters['session'] ??
        Uri.base.queryParameters['sessionId'] ??
        Uri.base.queryParameters['code'];
    if (_sessionId != null && _sessionId!.trim().isEmpty) {
      _sessionId = null;
    }

    unawaited(_restoreSavedSession());
  }

  Future<void> _restoreSavedSession() async {
    final initialSessionId = _sessionId;

    final savedState = await _sessionStore.load();
    if (!mounted || savedState == null) return;

    if (initialSessionId != null && initialSessionId != savedState.sessionId) {
      await _sessionStore.clear();
      return;
    }

    try {
      final session = await _service.fetchSession(savedState.sessionId);
      final player = await _service.fetchPlayer(
        savedState.sessionId,
        savedState.playerId,
      );

      if (!mounted) return;

      setState(() {
        _sessionId = savedState.sessionId;
        _playerId = savedState.playerId;
        _session = session;
        _player = player;
        _error = null;
        _stage = _stageForStatus(session.status);
      });

      if (_isSessionEnded(session.status)) {
        await _loadMutualSeeAgainPlayers();
      }

      _startPolling();
    } catch (_) {
      await _sessionStore.clear();
    }
  }

  void _joinWithCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _error = 'Please enter a valid session code.';
      });
      return;
    }

    setState(() {
      _sessionId = trimmed;
      _error = null;
      _stage = Stage.signup;
    });

    unawaited(_sessionStore.clear());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _handleSignup(SignupPayload payload) async {
    if (_sessionId == null) return;

    setState(() {
      _error = null;
    });

    try {
      final session = await _service.fetchSession(_sessionId!);
      final playerId = _phoneAuthPlayerId(payload.phone);
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

      _initialSessionStatus = session.status;
      setState(() {
        _session = session;
        _player = player;
        _playerId = playerId;
        _stage = Stage.waiting;
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

        if (roundChanged && _stage == Stage.game) {
          final previousPartnerId = previousPlayer?.pairedWith;
          await _service.clearPairing(_sessionId!, _playerId!);
          player.pairedWith = null;
          player.pairedRound = null;
          player.partnerCode = null;

          if (previousPartnerId != null) {
            unawaited(_showRoundEndedDialog(previousPartnerId));
          } else {
            unawaited(_showRoundEndedDialog(null));
          }
        }

        final nextStage = _stageForStatus(session.status);
        setState(() {
          _session = session;
          _player = player;
          _error = null;
          _stage = _stage == Stage.signup ? _stage : nextStage;
        });

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
    if (_sessionId == null || _player == null || _session == null) return;

    try {
      final players = await _service.fetchPlayers(_sessionId!);
      final normalized = code.trim().toUpperCase();

      final partner = players.values.firstWhere(
        (p) => p.id != _player!.id && p.inviteCode.toUpperCase() == normalized,
      );

      final alreadyMatched =
          _player!.matchedPlayerIds.contains(partner.id) ||
          partner.matchedPlayerIds.contains(_player!.id);
      if (alreadyMatched) {
        setState(() {
          _error = 'You have already matched with this player in a previous round.';
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

  bool _isSessionLive(String? status) =>
      status?.trim().toLowerCase() == 'started';

  bool _isSessionEnded(String? status) =>
      status?.trim().toLowerCase() == 'ended';

  Stage _stageForStatus(String? status) {
    if (_isSessionLive(status)) return Stage.game;
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
                if (_sessionId != null && _playerId != null && partnerId != null) {
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

    if (me.currentPromptRound == round && me.currentRoundPrompts.length == 3) {
      return;
    }

    final partnerRefreshed = await _service.fetchPlayer(_sessionId!, partner.id);

    List<PromptItem> prompts;
    if (partnerRefreshed.currentPromptRound == round &&
        partnerRefreshed.currentRoundPrompts.length == 3) {
      prompts = partnerRefreshed.currentRoundPromptItems;
    } else {
      final seenIds = {
        ...me.askedPromptIds,
        ...partnerRefreshed.askedPromptIds,
      };
      final pool1 = catalog.pickUnused('promptPool1', seenIds);
      final pool2 = catalog.pickUnused('promptPool2', seenIds);
      final finalPool =
          me.roundPreference == RoundPreference.openingUp &&
                  partnerRefreshed.roundPreference == RoundPreference.openingUp
              ? 'promptPool3'
              : 'promptPool4';
      final pool3Or4 = catalog.pickUnused(finalPool, seenIds);
      prompts = [pool1, pool2, pool3Or4];
    }

    final promptStorageValues = prompts.map((prompt) => prompt.toStorage()).toList();

    final mergedHistory = {
      ...me.askedPromptIds,
      ...partnerRefreshed.askedPromptIds,
      ...prompts.map((prompt) => prompt.id),
    }.toList();

    await _service.updateRoundPrompts(
      sessionId: _sessionId!,
      playerId: me.id,
      round: round,
      promptEntries: promptStorageValues,
      askedPromptIds: mergedHistory,
    );

    await _service.updateRoundPrompts(
      sessionId: _sessionId!,
      playerId: partnerRefreshed.id,
      round: round,
      promptEntries: promptStorageValues,
      askedPromptIds: mergedHistory,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, _) => Stack(
            children: [
              const Positioned.fill(child: FilmOverlay()),
              Positioned.fill(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: _gameViewportSize.width,
                      height: _gameViewportSize.height,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _buildBody(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_sessionId == null) {
      return JoinWithCodeView(
        error: _error,
        onJoin: _joinWithCode,
      );
    }

    switch (_stage) {
      case Stage.signup:
        return SignupForm(
          sessionId: _sessionId!,
          error: _error,
          onSubmit: _handleSignup,
        );
      case Stage.waiting:
        return WaitingView(
          player: _player,
          session: _session,
          error: _error,
        );
      case Stage.game:
        return GameView(
          player: _player,
          session: _session,
          error: _error,
          onSubmitCode: _submitPartnerCode,
          onDrawPrompt: _syncPromptDraw,
        );
      case Stage.ended:
        return EndedView(players: _mutualSeeAgainPlayers);
    }
  }

  Future<void> _syncPromptDraw({
    required int promptIndex,
    required String partnerId,
  }) async {
    if (_sessionId == null || _player == null) return;

    await _service.syncPromptIndexForPair(
      sessionId: _sessionId!,
      me: _player!,
      partnerId: partnerId,
      promptIndex: promptIndex,
    );

    final refreshed = await _service.fetchPlayer(_sessionId!, _player!.id);
    if (!mounted) return;
    setState(() {
      _player = refreshed;
    });
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Join with Code', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text('Enter your session code to join the signup flow.'),
              const SizedBox(height: 16),
              TextField(
                controller: _codeCtrl,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Session code',
                  hintText: 'e.g. spring-mixer',
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
                  child: const Text('Join session'),
                ),
              ),
            ],
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
  RoundPreference _roundPreference = RoundPreference.openingUp;
  bool _acceptedTermsAndGameTexts = false;
  bool _acceptedPromoTexts = false;
  bool _showTermsValidationError = false;
  bool _submitting = false;

  static final Uri _termsUri =
      Uri.parse('https://playyoume.com/termsandconditions');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final isFormValid = _formKey.currentState!.validate();
    if (!_acceptedTermsAndGameTexts) {
      setState(() {
        _showTermsValidationError = true;
      });
    }
    if (!isFormValid || !_acceptedTermsAndGameTexts) return;

    setState(() => _submitting = true);

    await widget.onSubmit(
      SignupPayload(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        acceptedTermsAndGameTexts: _acceptedTermsAndGameTexts,
        acceptedPromoTexts: _acceptedPromoTexts,
        roundPreference: _roundPreference,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Join session ${widget.sessionId}',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text('Sign up and authenticate to enter the game round queue.'),
            const SizedBox(height: 24),
            _input(_nameCtrl, 'Name'),
            const SizedBox(height: 12),
            _input(_phoneCtrl, 'Phone number (authentication)', phone: true),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Round style preference',
                border: OutlineInputBorder(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _roundPreference.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Switch(
                        value: _roundPreference == RoundPreference.playful,
                        onChanged: (isPlayful) {
                          setState(() {
                            _roundPreference = isPlayful
                                ? RoundPreference.playful
                                : RoundPreference.openingUp;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _roundPreference == RoundPreference.openingUp
                        ? 'Opening up asks deeper questions when both partners choose it.'
                        : 'Playful keeps the round light and fun with easier prompts.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _acceptedTermsAndGameTexts,
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
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('I confirm I read the '),
                        TextButton(
                          onPressed: _openTermsAndConditions,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Terms and Conditions'),
                        ),
                        const Text(
                          ' and agree to receive text messages related to the game.',
                        ),
                      ],
                    ),
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
            CheckboxListTile(
              value: _acceptedPromoTexts,
              onChanged: (value) {
                setState(() {
                  _acceptedPromoTexts = value ?? false;
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Optional: I agree to receive promotional text messages.',
              ),
            ),
            if (widget.error != null) ...[
              const SizedBox(height: 12),
              Text(widget.error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(
                  _submitting ? 'Signing up...' : 'Sign up and authenticate',
                ),
              ),
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
      keyboardType: phone ? TextInputType.phone : TextInputType.text,
      validator: (value) =>
          (value == null || value.trim().isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class WaitingView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Waiting room', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (player != null) ...[
          Text('Your code: ${player!.inviteCode}',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Share this code so other players can pair with you.'),
        ],
        const SizedBox(height: 24),
        Text('Session status: ${session?.status ?? 'unknown'}'),
        Text('Current round: ${session?.round?.toString() ?? '-'}'),
        const SizedBox(height: 20),
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        const Text('Waiting for session status to change...'),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: const TextStyle(color: Colors.red)),
        ]
      ],
    );
  }
}

class GameView extends StatefulWidget {
  const GameView({
    super.key,
    required this.player,
    required this.session,
    required this.onSubmitCode,
    required this.onDrawPrompt,
    this.error,
  });

  final PlayerRecord? player;
  final SessionRecord? session;
  final Future<void> Function(String code) onSubmitCode;
  final Future<void> Function({
    required int promptIndex,
    required String partnerId,
  }) onDrawPrompt;
  final String? error;

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> with TickerProviderStateMixin {
  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  int? _seenRound;
  int _animatedPromptIndex = 0;
  Timer? _nextCardTimer;
  int _nextCardCooldown = 0;

  late final AnimationController _flipController;
  late final Animation<double> _flipAnimation;
  late final AnimationController _dropController;
  late final Animation<double> _dropCurve;
  late final Animation<double> _dropYOffset;
  late final Animation<double> _dropXOffset;
  late final Animation<double> _dropRotation;
  late final Animation<double> _dropScale;

  @override
  void didUpdateWidget(covariant GameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final round = widget.session?.round;
    final currentRound = widget.session?.round;
    final oldRound = oldWidget.session?.round;
    final isPairedThisRound = widget.player?.pairedWith != null &&
        widget.player?.pairedRound != null &&
        widget.player!.pairedRound == currentRound;
    final wasPairedThisRound = oldWidget.player?.pairedWith != null &&
        oldWidget.player?.pairedRound != null &&
        oldWidget.player!.pairedRound == oldRound;
    final prompts = widget.player?.currentRoundPromptItems ?? const <PromptItem>[];
    final hadPrompts = (oldWidget.player?.currentRoundPromptItems ?? const <PromptItem>[]).isNotEmpty;

    if (round != _seenRound) {
      _seenRound = round;
      _animatedPromptIndex = 0;
      _restartNextCardCooldown();
      if (isPairedThisRound && prompts.isNotEmpty) {
        _playCardDropAnimation();
      }
    }

    final promptIndex = widget.player?.currentPromptIndex ?? 0;
    if (promptIndex != _animatedPromptIndex) {
      _animatedPromptIndex = promptIndex;
      _playCardDropAnimation();
      _restartNextCardCooldown();
    }

    if (isPairedThisRound && prompts.isNotEmpty && (!wasPairedThisRound || !hadPrompts)) {
      _playCardDropAnimation();
    }
  }

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
      value: 1,
    );
    _flipAnimation = CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeOutBack,
    );
    _dropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
      value: 1,
    );
    _dropCurve = CurvedAnimation(parent: _dropController, curve: Curves.easeOutQuart);
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
        tween: Tween(begin: -34.0, end: 9.0)
            .chain(CurveTween(curve: Curves.easeOutQuart)),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 9.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ]).animate(_dropCurve);
    _dropRotation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.22, end: -0.08)
            .chain(CurveTween(curve: Curves.easeOutQuart)),
        weight: 75,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.08, end: -0.03)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
    ]).animate(_dropCurve);
    _dropScale = Tween(begin: 0.94, end: 1.0)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_dropCurve);
    _restartNextCardCooldown();
  }

  void _playCardDropAnimation() {
    _flipController
      ..reset()
      ..forward();
    _dropController
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nextCardTimer?.cancel();
    _flipController.dispose();
    _dropController.dispose();
    super.dispose();
  }

  void _restartNextCardCooldown() {
    _nextCardTimer?.cancel();
    final player = widget.player;
    final prompts = player?.currentRoundPromptItems ?? const <PromptItem>[];
    final hasNextCard = player != null && player.currentPromptIndex < prompts.length - 1;

    if (!hasNextCard) {
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
    final prompts = player?.currentRoundPromptItems ?? const <PromptItem>[];
    final currentRound = widget.session?.round;
    if (player == null ||
        player.pairedWith == null ||
        currentRound == null ||
        prompts.isEmpty ||
        _nextCardCooldown > 0) {
      return;
    }

    final nextIndex = player.currentPromptIndex + 1;
    if (nextIndex >= prompts.length) return;

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

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final player = widget.player;
    final currentRound = widget.session?.round;
    final isPairedThisRound = player?.pairedWith != null &&
        player?.pairedRound != null &&
        player!.pairedRound == currentRound;
    final prompts = player?.currentRoundPromptItems ?? const <PromptItem>[];
    final promptIndex = prompts.isEmpty
        ? 0
        : (player?.currentPromptIndex ?? 0).clamp(0, prompts.length - 1);

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: keyboardInset + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Game Screen', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text('Round: ${currentRound?.toString() ?? '-'}'),
          Text('Status: ${widget.session?.status ?? '-'}'),
          const SizedBox(height: 20),
          if (player != null)
            Text('Your code: ${player.inviteCode}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          if (isPairedThisRound) ...[
            Text('Prompt ${prompts.isEmpty ? 0 : (promptIndex + 1)} of ${prompts.length}'),
            const SizedBox(height: 12),
            if (prompts.isNotEmpty) ...[
              Center(
                child: SizedBox(
                  width: 290,
                  height: 370,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < (promptIndex > 2 ? 2 : promptIndex); i++)
                        Positioned(
                          left: 26 + (i * 8),
                          top: 10 + (i * 10),
                          child: Transform.rotate(
                            angle: -0.045 + (i * 0.03),
                            child: _PaperCard(
                              width: 240,
                              height: 330,
                              prompt: prompts[promptIndex - i - 1].text,
                              seed:
                                  '${prompts[promptIndex - i - 1].id}-${promptIndex - i - 1}-${player?.id ?? ''}',
                            ),
                          ),
                        ),
                      AnimatedBuilder(
                        animation: Listenable.merge([_flipAnimation, _dropController]),
                        builder: (context, _) {
                          final tilt = pi * (1 - _flipAnimation.value);
                          return Positioned(
                            left: 25,
                            top: 0,
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.001)
                                ..translate(_dropXOffset.value, _dropYOffset.value)
                                ..rotateZ(_dropRotation.value)
                                ..scale(_dropScale.value)
                                ..rotateY(tilt),
                              child: _PaperCard(
                                width: 240,
                                height: 330,
                                prompt: prompts[promptIndex].text,
                                seed:
                                    '${prompts[promptIndex].id}-$promptIndex-${player?.id ?? ''}',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_nextCardCooldown > 0)
                Text(
                  'Next card available in $_nextCardCooldown seconds',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 10),
              if (promptIndex < prompts.length - 1)
                FilledButton(
                  onPressed: (_submitting || _nextCardCooldown > 0) ? null : _drawNextPrompt,
                  child: Text(
                    _submitting
                        ? 'Drawing...'
                        : _nextCardCooldown > 0
                            ? 'Draw next card (${_nextCardCooldown}s)'
                            : 'Draw next card',
                  ),
                )
              else
                const Text('Round complete. Wait for next round to pair with someone new.'),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Prompts are syncing. Ask your partner to submit your code too.'),
              ),
          ] else ...[
            const Text("Enter someone else's 4-character code to pair:"),
            const SizedBox(height: 8),
            TextField(
              controller: _codeCtrl,
              maxLength: 4,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'AB12',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _submitting ? null : _submitCode,
              child: Text(_submitting ? 'Submitting...' : 'Pair for round'),
            )
          ],
          if (widget.error != null) ...[
            const SizedBox(height: 12),
            Text(widget.error!, style: const TextStyle(color: Colors.red)),
          ]
        ],
      ),
    );
  }
}

class EndedView extends StatelessWidget {
  const EndedView({super.key, required this.players});

  final List<PlayerRecord> players;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Round Results', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text('Status: Ended'),
        const SizedBox(height: 20),
        if (players.isEmpty)
          const Text('Thanks for playing!')
        else ...[
          const Text('You both said you would like to see each other again:'),
          const SizedBox(height: 12),
          ...players.map(
            (player) => Card(
              child: ListTile(
                leading: const Text('👍', style: TextStyle(fontSize: 20)),
                title: Text(player.name.isEmpty ? 'Another player' : player.name),
              ),
            ),
          ),
        ],
      ],
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
      paint.color = (i.isEven ? _ink : const Color(0xFF5C513D)).withAlpha(alpha);
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

  int _seedToInt() {
    var value = 17;
    for (final codeUnit in seed.codeUnits) {
      value = (value * 37 + codeUnit) & 0x7fffffff;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final rng = Random(_seedToInt());
    final palettes = <List<Color>>[
      [const Color(0xFFB5472D), const Color(0xFF0E6B8C), const Color(0xFF2A1D2F)],
      [const Color(0xFFD18600), const Color(0xFF088D98), const Color(0xFF0D2439)],
      [const Color(0xFFC8A35F), const Color(0xFF7E0F1C), const Color(0xFF2B1E3A)],
      [const Color(0xFF007A7A), const Color(0xFFE08600), const Color(0xFF04243A)],
      [const Color(0xFF1E3A5F), const Color(0xFFCA4A2D), const Color(0xFF222D38)],
    ];
    final palette = palettes[rng.nextInt(palettes.length)];

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F3),
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
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(
                          -0.6 + rng.nextDouble() * 1.2,
                          -0.6 + rng.nextDouble() * 1.2,
                        ),
                        radius: 1.35,
                        colors: [palette[0], palette[1], palette[2]],
                        stops: const [0.1, 0.6, 1],
                      ),
                    ),
                  ),
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Positioned(
                            left: (rng.nextDouble() - 0.2) * width * 0.85,
                            top: (rng.nextDouble() - 0.15) * height * 0.75,
                            child: Container(
                              width: width * (0.45 + rng.nextDouble() * 0.4),
                              height: width * (0.45 + rng.nextDouble() * 0.4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    palette[rng.nextInt(palette.length)].withOpacity(0.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.16),
                                    blurRadius: 30,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xAAFFFFFF), width: 1.2),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        prompt,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: const Color(0xFFF8F8F8),
                              fontWeight: FontWeight.w700,
                              shadows: const [
                                Shadow(color: Color(0xCC000000), blurRadius: 8),
                              ],
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You Me',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFamily: 'cursive',
                  fontStyle: FontStyle.italic,
                  color: const Color(0xFF312824),
                ),
          ),
        ],
      ),
    );
  }
}

class _PaperBall extends StatelessWidget {
  const _PaperBall({required this.diameter, required this.rotation});

  final double diameter;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: CustomPaint(
        size: Size.square(diameter),
        painter: _PaperBallPainter(),
      ),
    );
  }
}

class _PaperBallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final circle = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2,
    );

    final paperPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFF8F1DF), Color(0xFFE4D5B5)],
        stops: [0.4, 1],
      ).createShader(circle)
      ..style = PaintingStyle.fill;

    canvas.drawOval(circle, paperPaint);

    final wrinkle = Paint()
      ..color = const Color(0xFF8A7C63).withOpacity(0.4)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    for (var i = 0; i < 9; i++) {
      final angle = (2 * pi * i) / 9;
      final p1 = center + Offset(cos(angle), sin(angle)) * (radius * 0.24);
      final p2 = center + Offset(cos(angle + 0.35), sin(angle + 0.35)) * (radius * 0.8);
      canvas.drawLine(p1, p2, wrinkle);
    }

    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center + const Offset(0, 3), radius * 0.85, shadow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
      duration: const Duration(milliseconds: 1400),
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
      ..color = _paper.withOpacity(flickerStrength);
    canvas.drawRect(Offset.zero & size, exposureFlicker);

    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          _ink.withOpacity(0.1),
        ],
        stops: const [0.5, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, vignette);

    final noise = Paint()..color = _ink.withOpacity(0.035);
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
      final phase = frame * pi * 2 + (i * pi / 2);
      final center = Offset(
        size.width * (0.2 + (i * 0.18)) + sin(phase * 0.9) * 20,
        size.height * (0.25 + (i.isEven ? 0.1 : 0.45)) + cos(phase * 1.1) * 18,
      );
      final bloomRadius = 56 + sin(phase * 1.3) * 10;
      final bloomPaint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26)
        ..color = bloomColors[i].withOpacity(0.12);
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
      dustPaint.color = _ink.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, dustPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FilmGrainPainter oldDelegate) {
    return oldDelegate.animation.value != animation.value;
  }
}
