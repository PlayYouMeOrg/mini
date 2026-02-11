import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _databaseBaseUrl =
    'https://youmedev-feab4-default-rtdb.firebaseio.com';

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

enum Stage { signup, phoneAuth, waiting, game }

class SessionFlowPage extends StatefulWidget {
  const SessionFlowPage({super.key});

  @override
  State<SessionFlowPage> createState() => _SessionFlowPageState();
}

class _SessionFlowPageState extends State<SessionFlowPage> {
  final _service = RtdbService();

  Stage _stage = Stage.signup;
  String? _sessionId;
  String? _playerId;
  PlayerRecord? _player;
  SessionRecord? _session;
  String? _error;
  Timer? _poller;
  String? _initialSessionStatus;
  SignupPayload? _pendingSignup;

  @override
  void initState() {
    super.initState();
    _sessionId = Uri.base.queryParameters['session'] ??
        Uri.base.queryParameters['sessionId'] ??
        Uri.base.queryParameters['code'];
    if (_sessionId != null && _sessionId!.trim().isEmpty) {
      _sessionId = null;
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
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _handleSignup(SignupPayload payload) async {
    setState(() {
      _error = null;
      _pendingSignup = payload;
      _stage = Stage.phoneAuth;
    });
  }

  Future<void> _handlePhoneAuth() async {
    if (_sessionId == null || _pendingSignup == null) return;

    setState(() {
      _error = null;
    });

    try {
      final session = await _service.fetchSession(_sessionId!);
      final playerId = _generateId();
      final inviteCode = _generateInviteCode();
      final signup = _pendingSignup!;
      final player = PlayerRecord(
        id: playerId,
        name: signup.name,
        phone: signup.phone,
        gender: signup.gender,
        sexualPreference: signup.sexualPreference,
        inviteCode: inviteCode,
      );

      await _service.savePlayer(_sessionId!, player);

      _initialSessionStatus = session.status;
      setState(() {
        _session = session;
        _player = player;
        _playerId = playerId;
        _pendingSignup = null;
        _stage = Stage.waiting;
      });

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

        if (roundChanged && _stage == Stage.game) {
          await _service.clearPairing(_sessionId!, _playerId!);
          player.pairedWith = null;
          player.pairedRound = null;
          player.partnerCode = null;
        }

        setState(() {
          _session = session;
          _player = player;
          _error = null;
        });

        if (_stage == Stage.waiting) {
          final hasStatusChanged = session.status != _initialSessionStatus;
          if (hasStatusChanged) {
            setState(() {
              _stage = Stage.game;
            });
          }
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
      case Stage.phoneAuth:
        return PhoneAuthView(
          phoneNumber: _pendingSignup?.phone,
          error: _error,
          onAuthenticate: _handlePhoneAuth,
          onBack: () {
            setState(() {
              _error = null;
              _stage = Stage.signup;
            });
          },
        );
      case Stage.game:
        return GameView(
          player: _player,
          session: _session,
          error: _error,
          onSubmitCode: _submitPartnerCode,
        );
    }
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
  final _genderCtrl = TextEditingController();
  final _prefCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _genderCtrl.dispose();
    _prefCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    await widget.onSubmit(
      SignupPayload(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        gender: _genderCtrl.text.trim(),
        sexualPreference: _prefCtrl.text.trim(),
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
            const Text('Sign up to enter the game round queue.'),
            const SizedBox(height: 24),
            _input(_nameCtrl, 'Name'),
            const SizedBox(height: 12),
            _input(_phoneCtrl, 'Phone number', phone: true),
            const SizedBox(height: 12),
            _input(_genderCtrl, 'Gender'),
            const SizedBox(height: 12),
            _input(_prefCtrl, 'Sexual preference'),
            if (widget.error != null) ...[
              const SizedBox(height: 12),
              Text(widget.error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? 'Signing up...' : 'Sign up'),
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

class PhoneAuthView extends StatefulWidget {
  const PhoneAuthView({
    super.key,
    required this.phoneNumber,
    required this.onAuthenticate,
    required this.onBack,
    this.error,
  });

  final String? phoneNumber;
  final Future<void> Function() onAuthenticate;
  final VoidCallback onBack;
  final String? error;

  @override
  State<PhoneAuthView> createState() => _PhoneAuthViewState();
}

class _PhoneAuthViewState extends State<PhoneAuthView> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = widget.phoneNumber ?? '';
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    await widget.onAuthenticate();
    if (mounted) {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Phone authentication',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text(
            'Complete phone authentication to finish account creation and join the session.',
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Required';
              if (value.trim() != widget.phoneNumber?.trim()) {
                return 'Phone number must match the create form entry.';
              }
              return null;
            },
            decoration: const InputDecoration(
              labelText: 'Phone number',
              border: OutlineInputBorder(),
            ),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 12),
            Text(widget.error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : widget.onBack,
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _authenticate,
                  child: Text(_submitting ? 'Authenticating...' : 'Authenticate'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GameView extends StatefulWidget {
  const GameView({
    super.key,
    required this.player,
    required this.session,
    required this.onSubmitCode,
    this.error,
  });

  final PlayerRecord? player;
  final SessionRecord? session;
  final Future<void> Function(String code) onSubmitCode;
  final String? error;

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  final _codeCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitCode() async {
    if (_codeCtrl.text.trim().length < 4) return;
    setState(() => _submitting = true);
    await widget.onSubmitCode(_codeCtrl.text);
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final currentRound = widget.session?.round;
    final isPairedThisRound = player?.pairedWith != null &&
        player?.pairedRound != null &&
        player!.pairedRound == currentRound;

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
                  ],
                ),
              ),
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

class SignupPayload {
  const SignupPayload({
    required this.name,
    required this.phone,
    required this.gender,
    required this.sexualPreference,
  });

  final String name;
  final String phone;
  final String gender;
  final String sexualPreference;
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
    required this.inviteCode,
    this.partnerCode,
    this.pairedWith,
    this.pairedRound,
  });

  final String id;
  final String name;
  final String phone;
  final String gender;
  final String sexualPreference;
  final String inviteCode;
  String? partnerCode;
  String? pairedWith;
  int? pairedRound;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'gender': gender,
      'sexualPreference': sexualPreference,
      'inviteCode': inviteCode,
      'partnerCode': partnerCode,
      'pairedWith': pairedWith,
      'pairedRound': pairedRound,
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
      inviteCode: (json['inviteCode'] ?? '') as String,
      partnerCode: json['partnerCode'] as String?,
      pairedWith: json['pairedWith'] as String?,
      pairedRound: (json['pairedRound'] as num?)?.toInt(),
    );
  }
}

class RtdbService {
  Uri _uri(String path) => Uri.parse('$_databaseBaseUrl/$path.json');

  Future<SessionRecord> fetchSession(String sessionId) async {
    final resp = await http.get(_uri('sessions/$sessionId'));
    _throwIfNotOk(resp);
    final payload = jsonDecode(resp.body);
    if (payload is! Map<String, dynamic>) {
      return SessionRecord(status: null, round: null);
    }
    return SessionRecord.fromJson(payload);
  }

  Future<void> savePlayer(String sessionId, PlayerRecord player) async {
    final resp = await http.patch(
      _uri('sessions/$sessionId/players/${player.id}'),
      body: jsonEncode(player.toJson()),
    );
    _throwIfNotOk(resp);
  }

  Future<Map<String, PlayerRecord>> fetchPlayers(String sessionId) async {
    final resp = await http.get(_uri('sessions/$sessionId/players'));
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
    final resp = await http.get(_uri('sessions/$sessionId/players/$playerId'));
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
      _uri('sessions/$sessionId/players/$playerId'),
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

  void _throwIfNotOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw StateError(
      'HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}: ${response.body}',
    );
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
