import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _databaseBaseUrl =
    'https://youmedev-feab4-default-rtdb.firebaseio.com';
const _firestoreProjectId = 'youmedev-feab4';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const SessionFlowPage(),
    );
  }
}

enum Stage { signup, waiting, game, ended }

enum RoundPreference { openingUp, playful }

extension RoundPreferenceLabel on RoundPreference {
  String get label => this == RoundPreference.openingUp ? 'Opening up' : 'Playful';
}

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
      final playerId = _generateId();
      final inviteCode = _generateInviteCode();
      final signup = payload;
      final player = PlayerRecord(
        id: playerId,
        name: signup.name,
        phone: signup.phone,
        gender: signup.gender,
        sexualPreference: signup.sexualPreference,
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
      body: Center(
        child: Container(
          color: const Color(0xFFF4F6FC),
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 390,
              height: 844,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _buildBody(),
                ),
              ),
            ),
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
    return Center(
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
  static const _genderOptions = ['Woman', 'Man', 'Non-binary', 'Other'];
  static const _preferenceOptions = [
    'Women',
    'Men',
    'Everyone',
    'Prefer not to say',
  ];

  String? _selectedGender;
  String? _selectedPreference;
  RoundPreference _roundPreference = RoundPreference.openingUp;
  bool _acceptedTermsAndGameTexts = false;
  bool _acceptedPromoTexts = false;
  bool _showTermsValidationError = false;
  bool _submitting = false;

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
        gender: _selectedGender!.trim(),
        sexualPreference: _selectedPreference!.trim(),
        acceptedTermsAndGameTexts: _acceptedTermsAndGameTexts,
        acceptedPromoTexts: _acceptedPromoTexts,
        roundPreference: _roundPreference,
      ),
    );

    if (mounted) {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
            _input(_phoneCtrl, 'Phone number', phone: true),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedGender,
              items: _genderOptions
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(option),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedGender = value;
                });
              },
              validator: (value) => value == null ? 'Required' : null,
              decoration: const InputDecoration(
                labelText: 'Gender',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedPreference,
              items: _preferenceOptions
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(option),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedPreference = value;
                });
              },
              validator: (value) => value == null ? 'Required' : null,
              decoration: const InputDecoration(
                labelText: 'Sexual preference',
                border: OutlineInputBorder(),
              ),
            ),
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
            CheckboxListTile(
              value: _acceptedTermsAndGameTexts,
              onChanged: (value) {
                setState(() {
                  _acceptedTermsAndGameTexts = value ?? false;
                  if (_acceptedTermsAndGameTexts) {
                    _showTermsValidationError = false;
                  }
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I confirm I read the Terms and Conditions '
                '(Playyoume.com/termsandconditions) and agree to receive '
                'text messages related to the game.',
              ),
              subtitle: _showTermsValidationError && !_acceptedTermsAndGameTexts
                  ? const Text(
                      'Required',
                      style: TextStyle(color: Colors.red),
                    )
                  : null,
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

  late final AnimationController _flipController;
  late final Animation<double> _flipAnimation;
  late final AnimationController _splashController;

  @override
  void didUpdateWidget(covariant GameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final round = widget.session?.round;
    if (round != _seenRound) {
      _seenRound = round;
      _animatedPromptIndex = 0;
    }

    final promptIndex = widget.player?.currentPromptIndex ?? 0;
    if (promptIndex != _animatedPromptIndex) {
      _animatedPromptIndex = promptIndex;
      _flipController
        ..reset()
        ..forward();
      _splashController
        ..reset()
        ..forward();
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
    _splashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _flipController.dispose();
    _splashController.dispose();
    super.dispose();
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
        prompts.isEmpty) {
      return;
    }

    final nextIndex = player.currentPromptIndex + 1;
    if (nextIndex >= prompts.length) return;

    setState(() => _submitting = true);
    await widget.onDrawPrompt(
      promptIndex: nextIndex,
      partnerId: player.pairedWith!,
    );
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Paired for this round'),
                    const SizedBox(height: 6),
                    Text('Partner player id: ${player?.pairedWith ?? '-'}'),
                    const SizedBox(height: 6),
                    Text('Prompt ${prompts.isEmpty ? 0 : (promptIndex + 1)} of ${prompts.length}'),
                  ],
                ),
              ),
            ),
            if (prompts.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var i = 0; i < max(0, prompts.length - promptIndex - 1).clamp(0, 3); i++)
                      Transform.translate(
                        offset: Offset(0, 10.0 + (i * 8)),
                        child: Transform.rotate(
                          angle: (i + 1) * 0.03,
                          child: Container(
                            width: 280,
                            height: 180,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.indigo.shade100),
                            ),
                          ),
                        ),
                      ),
                    AnimatedBuilder(
                      animation: Listenable.merge([_flipAnimation, _splashController]),
                      builder: (context, child) {
                        final t = _flipAnimation.value;
                        final tilt = pi * (1 - t);
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(320, 220),
                              painter: ParticleSplashPainter(progress: _splashController.value),
                            ),
                            Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.001)
                                ..rotateY(tilt),
                              child: child,
                            ),
                          ],
                        );
                      },
                      child: Container(
                        width: 300,
                        height: 190,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.indigo.shade400, Colors.purple.shade300],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 18,
                              offset: Offset(0, 12),
                              color: Color(0x33000000),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            prompts[promptIndex].text,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (promptIndex < prompts.length - 1)
                FilledButton(
                  onPressed: _submitting ? null : _drawNextPrompt,
                  child: Text(_submitting ? 'Drawing...' : 'Draw next card'),
                )
              else
                const Text('Round complete. Wait for next round to pair with someone new.'),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Prompts are syncing. Ask your partner to submit your code too.'),
              ),
          ] else ...[
            const Text('Enter someone else\'s 4-character code to pair:'),
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
      paint.color = Colors.primaries[i % Colors.primaries.length]
          .withAlpha(alpha);
      canvas.drawCircle(center + offset, 2 + (1 - progress) * 4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticleSplashPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class SignupPayload {
  const SignupPayload({
    required this.name,
    required this.phone,
    required this.gender,
    required this.sexualPreference,
    required this.acceptedTermsAndGameTexts,
    required this.acceptedPromoTexts,
    required this.roundPreference,
  });

  final String name;
  final String phone;
  final String gender;
  final String sexualPreference;
  final bool acceptedTermsAndGameTexts;
  final bool acceptedPromoTexts;
  final RoundPreference roundPreference;
}


class PersistedSessionState {
  const PersistedSessionState({
    required this.sessionId,
    required this.playerId,
  });

  final String sessionId;
  final String playerId;
}

class SessionStateStore {
  static const _sessionIdKey = 'session_state.session_id';
  static const _playerIdKey = 'session_state.player_id';

  Future<void> save({
    required String sessionId,
    required String playerId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionIdKey, sessionId);
    await prefs.setString(_playerIdKey, playerId);
  }

  Future<PersistedSessionState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString(_sessionIdKey);
    final playerId = prefs.getString(_playerIdKey);

    if (sessionId == null || playerId == null) {
      return null;
    }

    return PersistedSessionState(
      sessionId: sessionId,
      playerId: playerId,
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionIdKey);
    await prefs.remove(_playerIdKey);
  }
}

class SessionRecord {
  SessionRecord({required this.status, required this.round});

  final String? status;
  final int? round;

  factory SessionRecord.fromJson(Map<String, dynamic> json) {
    return SessionRecord(
      status: json['status'] as String?,
      round: (json['round'] as num?)?.toInt(),
    );
  }
}

class PlayerRecord {
  PlayerRecord({
    required this.id,
    required this.name,
    required this.phone,
    required this.gender,
    required this.sexualPreference,
    required this.acceptedTermsAndGameTexts,
    required this.acceptedPromoTexts,
    required this.roundPreference,
    required this.inviteCode,
    this.partnerCode,
    this.pairedWith,
    this.pairedRound,
    this.currentPromptRound,
    this.currentPromptIndex = 0,
    this.currentRoundPrompts = const <String>[],
    this.askedPromptIds = const <String>[],
    this.seeAgainPlayerIds = const <String>[],
  });

  final String id;
  final String name;
  final String phone;
  final String gender;
  final String sexualPreference;
  final bool acceptedTermsAndGameTexts;
  final bool acceptedPromoTexts;
  final RoundPreference roundPreference;
  final String inviteCode;
  String? partnerCode;
  String? pairedWith;
  int? pairedRound;
  int? currentPromptRound;
  int currentPromptIndex;
  List<String> currentRoundPrompts;
  List<String> askedPromptIds;
  List<String> seeAgainPlayerIds;

  List<PromptItem> get currentRoundPromptItems =>
      currentRoundPrompts.map(PromptItem.fromStorage).toList();

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'gender': gender,
      'sexualPreference': sexualPreference,
      'acceptedTermsAndGameTexts': acceptedTermsAndGameTexts,
      'acceptedPromoTexts': acceptedPromoTexts,
      'roundPreference': roundPreference.name,
      'inviteCode': inviteCode,
      'partnerCode': partnerCode,
      'pairedWith': pairedWith,
      'pairedRound': pairedRound,
      'currentPromptRound': currentPromptRound,
      'currentPromptIndex': currentPromptIndex,
      'currentRoundPrompts': currentRoundPrompts,
      'askedPromptIds': askedPromptIds,
      'seeAgainPlayerIds': seeAgainPlayerIds,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  factory PlayerRecord.fromJson(String id, Map<String, dynamic> json) {
    return PlayerRecord(
      id: id,
      name: (json['name'] ?? '') as String,
      phone: (json['phone'] ?? '') as String,
      gender: (json['gender'] ?? '') as String,
      sexualPreference: (json['sexualPreference'] ?? '') as String,
      acceptedTermsAndGameTexts:
          (json['acceptedTermsAndGameTexts'] ?? false) as bool,
      acceptedPromoTexts: (json['acceptedPromoTexts'] ?? false) as bool,
      roundPreference: _roundPreferenceFromString(json['roundPreference'] as String?),
      inviteCode: (json['inviteCode'] ?? '') as String,
      partnerCode: json['partnerCode'] as String?,
      pairedWith: json['pairedWith'] as String?,
      pairedRound: (json['pairedRound'] as num?)?.toInt(),
      currentPromptRound: (json['currentPromptRound'] as num?)?.toInt(),
      currentPromptIndex: (json['currentPromptIndex'] as num?)?.toInt() ?? 0,
      currentRoundPrompts: ((json['currentRoundPrompts'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      askedPromptIds: ((json['askedPromptIds'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      seeAgainPlayerIds: _parseSeeAgainIds(json),
    );
  }
}

List<String> _parseSeeAgainIds(Map<String, dynamic> json) {
  final raw = json['seeAgainPlayerIds'];
  if (raw is List) {
    return raw.map((item) => item.toString()).where((id) => id.isNotEmpty).toList();
  }

  final legacyRaw = json['seeAgain'];
  if (legacyRaw is Map) {
    return legacyRaw.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key.toString())
        .where((id) => id.isNotEmpty)
        .toList();
  }

  return const <String>[];
}

class FirestoreSignupService {
  Uri _uri(String path) => Uri.https(
        'firestore.googleapis.com',
        '/v1/projects/$_firestoreProjectId/databases/(default)/documents/$path',
      );

  Future<void> saveSignup({
    required String sessionId,
    required PlayerRecord player,
  }) async {
    final response = await http.patch(
      _uri('signups/${player.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fields': {
          'sessionId': {'stringValue': sessionId},
          'playerId': {'stringValue': player.id},
          'name': {'stringValue': player.name},
          'phone': {'stringValue': player.phone},
          'gender': {'stringValue': player.gender},
          'sexualPreference': {'stringValue': player.sexualPreference},
          'inviteCode': {'stringValue': player.inviteCode},
          'roundPreference': {'stringValue': player.roundPreference.name},
          'acceptedTermsAndGameTexts': {
            'booleanValue': player.acceptedTermsAndGameTexts,
          },
          'acceptedPromoTexts': {
            'booleanValue': player.acceptedPromoTexts,
          },
          'createdAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        },
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) return;

    throw StateError(
      'Firestore save failed: HTTP ${response.statusCode} '
      '${response.reasonPhrase ?? ''} ${response.body}',
    );
  }
}

class RtdbService {
  Uri _uri(String path) => Uri.parse('$_databaseBaseUrl/$path.json');

  String _sessionBasePath(String sessionId) => 'mini/sessions/$sessionId';

  Future<SessionRecord> fetchSession(String sessionId) async {
    final resp = await http.get(_uri(_sessionBasePath(sessionId)));
    _throwIfNotOk(resp);
    final payload = jsonDecode(resp.body);
    if (payload is! Map<String, dynamic>) {
      return SessionRecord(status: null, round: null);
    }
    return SessionRecord.fromJson(payload);
  }

  Future<void> savePlayer(String sessionId, PlayerRecord player) async {
    final resp = await http.patch(
      _uri('${_sessionBasePath(sessionId)}/players/${player.id}'),
      body: jsonEncode(player.toJson()),
    );
    _throwIfNotOk(resp);
  }

  Future<Map<String, PlayerRecord>> fetchPlayers(String sessionId) async {
    final resp = await http.get(_uri('${_sessionBasePath(sessionId)}/players'));
    _throwIfNotOk(resp);
    final payload = jsonDecode(resp.body);
    if (payload is! Map<String, dynamic>) return {};

    return payload.map(
      (key, value) => MapEntry(
        key,
        PlayerRecord.fromJson(key, Map<String, dynamic>.from(value as Map)),
      ),
    );
  }

  Future<PlayerRecord> fetchPlayer(String sessionId, String playerId) async {
    final resp = await http.get(_uri('${_sessionBasePath(sessionId)}/players/$playerId'));
    _throwIfNotOk(resp);
    final payload = jsonDecode(resp.body);
    if (payload is! Map<String, dynamic>) {
      throw StateError('Player record not found.');
    }
    return PlayerRecord.fromJson(playerId, payload);
  }

  Future<void> setPairing({
    required String sessionId,
    required PlayerRecord me,
    required PlayerRecord partner,
    required int? round,
    required String enteredCode,
  }) async {
    me.partnerCode = enteredCode;
    me.pairedWith = partner.id;
    me.pairedRound = round;

    partner.pairedWith = me.id;
    partner.pairedRound = round;

    await savePlayer(sessionId, me);
    await savePlayer(sessionId, partner);
  }

  Future<void> clearPairing(String sessionId, String playerId) async {
    final resp = await http.patch(
      _uri('${_sessionBasePath(sessionId)}/players/$playerId'),
      body: jsonEncode(
        {
          'pairedWith': null,
          'pairedRound': null,
          'partnerCode': null,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      ),
    );
    _throwIfNotOk(resp);
  }

  Future<void> setSeeAgainPreference({
    required String sessionId,
    required String playerId,
    required String partnerId,
  }) async {
    final player = await fetchPlayer(sessionId, playerId);
    final updated = {
      ...player.seeAgainPlayerIds,
      partnerId,
    }.toList();

    final resp = await http.patch(
      _uri('${_sessionBasePath(sessionId)}/players/$playerId'),
      body: jsonEncode(
        {
          'seeAgainPlayerIds': updated,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      ),
    );
    _throwIfNotOk(resp);
  }

  Future<void> updateRoundPrompts({
    required String sessionId,
    required String playerId,
    required int round,
    required List<String> promptEntries,
    required List<String> askedPromptIds,
  }) async {
    final resp = await http.patch(
      _uri('${_sessionBasePath(sessionId)}/players/$playerId'),
      body: jsonEncode(
        {
          'currentPromptRound': round,
          'currentPromptIndex': 0,
          'currentRoundPrompts': promptEntries,
          'askedPromptIds': askedPromptIds,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      ),
    );
    _throwIfNotOk(resp);
  }

  Future<void> syncPromptIndexForPair({
    required String sessionId,
    required PlayerRecord me,
    required String partnerId,
    required int promptIndex,
  }) async {
    final update = {
      'currentPromptIndex': promptIndex,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    final meResp = await http.patch(
      _uri('${_sessionBasePath(sessionId)}/players/${me.id}'),
      body: jsonEncode(update),
    );
    _throwIfNotOk(meResp);

    final partnerResp = await http.patch(
      _uri('${_sessionBasePath(sessionId)}/players/$partnerId'),
      body: jsonEncode(update),
    );
    _throwIfNotOk(partnerResp);
  }

  void _throwIfNotOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw StateError(
      'HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}: ${response.body}',
    );
  }
}

RoundPreference _roundPreferenceFromString(String? raw) {
  if (raw == RoundPreference.openingUp.name) {
    return RoundPreference.openingUp;
  }
  return RoundPreference.playful;
}

class PromptItem {
  const PromptItem({required this.id, required this.text});

  final String id;
  final String text;

  String toStorage() => '$id::$text';

  factory PromptItem.fromStorage(String value) {
    final separatorIndex = value.indexOf('::');
    if (separatorIndex == -1) {
      return PromptItem(id: value, text: value);
    }
    return PromptItem(
      id: value.substring(0, separatorIndex),
      text: value.substring(separatorIndex + 2),
    );
  }
}

class PromptCatalog {
  const PromptCatalog({required this.pools});

  final Map<String, List<PromptItem>> pools;

  PromptItem pickUnused(String poolName, Set<String> usedIds) {
    final options = pools[poolName] ?? const <PromptItem>[];
    if (options.isEmpty) {
      throw StateError('Prompt pool $poolName is empty.');
    }

    final unused = options.where((item) => !usedIds.contains(item.id)).toList();
    final source = unused.isNotEmpty ? unused : options;
    final index = Random.secure().nextInt(source.length);
    return source[index];
  }
}

class PromptCatalogService {
  Future<PromptCatalog> loadDatingCatalog() async {
    final raw = await rootBundle.loadString('Prompts/Dating/prompt_set_x.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final dating = decoded['dating'] as Map<String, dynamic>?;
    if (dating == null) {
      throw StateError('Missing dating prompt bucket in prompt_set_x.json');
    }

    final pools = dating.map(
      (key, value) => MapEntry(
        key,
        ((value as List?) ?? const [])
            .map(
              (item) => PromptItem(
                id: (item['id'] ?? '').toString(),
                text: (item['text'] ?? '').toString(),
              ),
            )
            .where((item) => item.id.isNotEmpty && item.text.isNotEmpty)
            .toList(),
      ),
    );

    return PromptCatalog(pools: pools);
  }
}

String _generateInviteCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
}

String _generateId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  final suffix = List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  return '$now-$suffix';
}
