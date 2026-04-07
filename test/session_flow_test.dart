import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mini/main.dart';
import 'package:mini/session_domain.dart';
import 'package:mini/session_flow_bootstrap.dart';

void main() {
  group('LaunchIntent.fromUri', () {
    test('returns none when no query params are present', () {
      final intent = LaunchIntent.fromUri(Uri.parse('https://example.com/'));

      expect(intent.type, LaunchIntentType.none);
      expect(intent.sessionId, isNull);
    });

    test('returns demo when demo param is present in fragment query', () {
      final intent = LaunchIntent.fromUri(
        Uri.parse('https://example.com/#/?demo=1'),
      );

      expect(intent.type, LaunchIntentType.demo);
    });

    test('returns preview before demo when both params are present', () {
      final intent = LaunchIntent.fromUri(
        Uri.parse('https://example.com/?preview=1&demo=1'),
      );

      expect(intent.type, LaunchIntentType.preview);
    });

    test('returns session intent for session query param', () {
      final intent = LaunchIntent.fromUri(
        Uri.parse('https://example.com/?session=AB12'),
      );

      expect(intent.type, LaunchIntentType.session);
      expect(intent.sessionId, 'AB12');
    });
  });

  group('SessionFlowPage', () {
    testWidgets('shows join screen when there are no URL params', (
      tester,
    ) async {
      await _pumpFlow(
        tester,
        initialUri: Uri.parse('https://example.com/'),
      );

      expect(
        find.text('Enter your session code to join the room.'),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsOneWidget);

      final codeField = tester.widget<TextField>(find.byType(TextField).first);
      expect(codeField.style?.color, isNotNull);
    });

    testWidgets('asks for a demo name and saves it before joining', (
      tester,
    ) async {
      final fakeRtdbService = FakeRtdbService();

      await _pumpFlow(
        tester,
        initialUri: Uri.parse('https://example.com/?demo=1'),
        services: SessionFlowServices(
          rtdbService: fakeRtdbService,
          promptCatalogService: FakePromptCatalogService(),
          sessionStateStore: FakeSessionStateStore(),
        ),
      );

      expect(find.text('Enter your name'), findsOneWidget);
      expect(
          find.text(
              'We save it to the demo session so the story action can use the right name.'),
          findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Jordan');
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        find.text(
          'Share your code, then enter someone else\'s 4-character code to start talking.',
        ),
        findsOneWidget,
      );
      expect(find.text('Enter another person\'s 4-character code:'),
          findsOneWidget);
      expect(fakeRtdbService.savePlayerCalls, 1);
      expect(fakeRtdbService.players['demo-public'], isNotEmpty);
      expect(
        fakeRtdbService.players['demo-public']!.values.single.name,
        'Jordan',
      );
    });

    testWidgets('shows preview controls in preview mode', (tester) async {
      await _pumpFlow(
        tester,
        initialUri: Uri.parse('https://example.com/?preview=1'),
      );

      expect(find.text('Signup'), findsOneWidget);
      expect(find.text('Matching'), findsOneWidget);
    });

    testWidgets('shows error screen when explicit session boot fails', (
      tester,
    ) async {
      final fakeRtdbService = FakeRtdbService(
        fetchSessionError: StateError('offline'),
      );

      await _pumpFlow(
        tester,
        initialUri: Uri.parse('https://example.com/?session=AB12'),
        services: SessionFlowServices(
          rtdbService: fakeRtdbService,
          promptCatalogService: FakePromptCatalogService(),
          sessionStateStore: FakeSessionStateStore(),
        ),
      );

      expect(find.text('Error'), findsOneWidget);
      expect(find.textContaining('Unable to connect to the session server.'),
          findsOneWidget);
    });

    testWidgets('joins explicit started session into matching screen', (
      tester,
    ) async {
      final fakeRtdbService = FakeRtdbService(
        sessions: <String, SessionRecord>{
          'AB12': SessionRecord(status: 'started', round: 1),
        },
      );

      await _pumpFlow(
        tester,
        initialUri: Uri.parse('https://example.com/?session=AB12'),
        services: SessionFlowServices(
          rtdbService: fakeRtdbService,
          promptCatalogService: FakePromptCatalogService(),
          sessionStateStore: FakeSessionStateStore(),
        ),
      );

      expect(
        find.text('Enter another person\'s 4-character code:'),
        findsOneWidget,
      );
      expect(fakeRtdbService.savePlayerCalls, 1);
    });

    testWidgets('round 2 starts only after both players choose keep going', (
      tester,
    ) async {
      final me = _buildPairedPlayer(
        id: 'player-1',
        name: 'Avery',
        partnerId: 'player-2',
      );
      final partner = _buildPairedPlayer(
        id: 'player-2',
        name: 'Taylor',
        partnerId: 'player-1',
      );
      final fakeRtdbService = FakeRtdbService(
        sessions: <String, SessionRecord>{
          'demo-public': SessionRecord(status: 'started', round: 1),
        },
        players: <String, Map<String, PlayerRecord>>{
          'demo-public': <String, PlayerRecord>{
            me.id: me,
            partner.id: partner,
          },
        },
      );
      final sessionStore = FakeSessionStateStore(
        savedState: const PersistedSessionState(
          sessionId: 'demo-public',
          playerId: 'player-1',
        ),
      );

      await _pumpFlow(
        tester,
        initialUri: Uri.parse('https://example.com/?demo=1'),
        services: SessionFlowServices(
          rtdbService: fakeRtdbService,
          promptCatalogService: FakePromptCatalogService(),
          sessionStateStore: sessionStore,
        ),
      );

      await tester.pump();
      if (find.text('Got it').evaluate().isNotEmpty) {
        await tester.tap(find.text('Got it'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      final gameView = tester.widget<GameView>(find.byType(GameView));
      await gameView.onContinueInteraction();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(me.interactionRound, 1);
      expect(me.continueVoteRound, 2);
      expect(find.text('Waiting for them...'), findsOneWidget);
      expect(
        find.text('You picked keep going. Round 2 starts only if they do too.'),
        findsOneWidget,
      );

      partner.continueVoteRound = 2;

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(me.interactionRound, 2);
      expect(me.continueVoteRound, isNull);
      expect(find.text('Prompt 4'), findsWidgets);
    });

    testWidgets(
      'shows meet someone else popup when partner declines after keep going',
      (tester) async {
        final me = _buildPairedPlayer(
          id: 'player-1',
          name: 'Avery',
          partnerId: 'player-2',
        );
        final partner = _buildPairedPlayer(
          id: 'player-2',
          name: 'Taylor',
          partnerId: 'player-1',
        );
        final fakeRtdbService = FakeRtdbService(
          sessions: <String, SessionRecord>{
            'demo-public': SessionRecord(status: 'started', round: 1),
          },
          players: <String, Map<String, PlayerRecord>>{
            'demo-public': <String, PlayerRecord>{
              me.id: me,
              partner.id: partner,
            },
          },
        );
        final sessionStore = FakeSessionStateStore(
          savedState: const PersistedSessionState(
            sessionId: 'demo-public',
            playerId: 'player-1',
          ),
        );

        await _pumpFlow(
          tester,
          initialUri: Uri.parse('https://example.com/?demo=1'),
          services: SessionFlowServices(
            rtdbService: fakeRtdbService,
            promptCatalogService: FakePromptCatalogService(),
            sessionStateStore: sessionStore,
          ),
        );

        await tester.pump();
        if (find.text('Got it').evaluate().isNotEmpty) {
          await tester.tap(find.text('Got it'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        }

        final gameView = tester.widget<GameView>(find.byType(GameView));
        await gameView.onContinueInteraction();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Waiting for them...'), findsOneWidget);

        await fakeRtdbService.clearPairing('demo-public', partner.id);
        await fakeRtdbService.clearPairing('demo-public', me.id);

        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Lets meet someone else'), findsOneWidget);
        expect(
          find.text('Enter another person\'s 4-character code:'),
          findsOneWidget,
        );
        expect(me.pairedWith, isNull);
        expect(partner.pairedWith, isNull);
      },
    );
  });

  group('GameView', () {
    testWidgets('scales long prompt copy to fit the card', (tester) async {
      const longPrompt =
          'Tell the story of a conversation that changed your mind about love, '
          'what you learned from it, and the small detail you still remember '
          'years later when you think about that moment.';

      final player = PlayerRecord(
        id: 'player-1',
        name: 'Preview User',
        phone: '',
        gender: '',
        sexualPreference: '',
        acceptedTermsAndGameTexts: true,
        acceptedPromoTexts: false,
        roundPreference: RoundPreference.playful,
        inviteCode: 'AB12',
        pairedWith: 'player-2',
        pairedRound: 1,
        currentPromptRound: 1,
        currentPromptIndex: 0,
        currentRoundPrompts: const ['long-prompt'],
        askedPromptIds: const ['long-prompt'],
      );

      const promptCatalog = PromptCatalog(
        sets: <String, List<PromptItem>>{
          'preview': <PromptItem>[
            PromptItem(id: 'long-prompt', text: longPrompt),
          ],
        },
        itemsById: <String, PromptItem>{
          'long-prompt': PromptItem(id: 'long-prompt', text: longPrompt),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameView(
              player: player,
              session: SessionRecord(status: 'started', round: 1),
              onSubmitCode: (_) async {},
              onDrawPrompt: ({
                required int promptIndex,
                required String partnerId,
              }) async {},
              onContinueInteraction: () async {},
              promptCatalog: promptCatalog,
              unpairedInstructions:
                  'Enter any 4-character code to connect instantly.',
              codeEntryPrompt: 'Enter any 4-character code to start:',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      if (find.text('Got it').evaluate().isNotEmpty) {
        await tester.tap(find.text('Got it'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      final promptText = tester.widgetList<Text>(find.text(longPrompt)).first;
      expect(promptText.style?.fontSize, lessThan(28));
    });

    testWidgets('round 2 completion does not offer keep going', (
      tester,
    ) async {
      final promptCatalog =
          await FakePromptCatalogService().loadDatingCatalog();
      final player = _buildPairedPlayer(
        id: 'player-1',
        name: 'Preview User',
        partnerId: 'player-2',
        interactionRound: 2,
        currentRoundPrompts: const ['p4'],
        askedPromptIds: const ['p1', 'p2', 'p3', 'p4'],
        currentPromptIndex: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameView(
              player: player,
              session: SessionRecord(status: 'started', round: 1),
              onSubmitCode: (_) async {},
              onDrawPrompt: ({
                required int promptIndex,
                required String partnerId,
              }) async {},
              onContinueInteraction: () async {},
              promptCatalog: promptCatalog,
              unpairedInstructions:
                  'Enter any 4-character code to connect instantly.',
              codeEntryPrompt: 'Enter any 4-character code to start:',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      if (find.text('Got it').evaluate().isNotEmpty) {
        await tester.tap(find.text('Got it'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();

      expect(find.text('Finish interaction'), findsOneWidget);

      await tester.ensureVisible(find.text('Finish interaction'));
      await tester.tap(find.text('Finish interaction'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('This was round 2'), findsOneWidget);
      expect(find.text('Finish interaction'), findsWidgets);
      expect(find.text('Keep going'), findsNothing);
    });
  });
}

Future<void> _pumpFlow(
  WidgetTester tester, {
  required Uri initialUri,
  SessionFlowServices? services,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SessionFlowPage(
        initialUri: initialUri,
        services: services ??
            SessionFlowServices(
              rtdbService: FakeRtdbService(),
              promptCatalogService: FakePromptCatalogService(),
              sessionStateStore: FakeSessionStateStore(),
            ),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

class FakeRtdbService extends RtdbService {
  FakeRtdbService({
    Map<String, SessionRecord>? sessions,
    Map<String, Map<String, PlayerRecord>>? players,
    this.fetchSessionError,
  })  : sessions = sessions ?? <String, SessionRecord>{},
        players = players ?? <String, Map<String, PlayerRecord>>{};

  final Map<String, SessionRecord> sessions;
  final Map<String, Map<String, PlayerRecord>> players;
  final Object? fetchSessionError;
  int savePlayerCalls = 0;

  @override
  Future<SessionRecord> fetchSession(String sessionId) async {
    if (fetchSessionError != null) {
      throw fetchSessionError!;
    }

    return sessions[sessionId] ?? SessionRecord(status: null, round: null);
  }

  @override
  Future<SessionRecord> ensureSessionStarted(String sessionId) async {
    final existing = sessions[sessionId];
    if (existing != null &&
        existing.status?.trim().toLowerCase() == 'started' &&
        existing.round != null) {
      return existing;
    }

    final session =
        SessionRecord(status: 'started', round: existing?.round ?? 1);
    sessions[sessionId] = session;
    return session;
  }

  @override
  Future<void> savePlayer(String sessionId, PlayerRecord player) async {
    savePlayerCalls += 1;
    players.putIfAbsent(sessionId, () => <String, PlayerRecord>{})[player.id] =
        player;
  }

  @override
  Future<Map<String, PlayerRecord>> fetchPlayers(String sessionId) async {
    return (players[sessionId] ?? <String, PlayerRecord>{}).map(
      (key, value) => MapEntry(key, _clonePlayer(value)),
    );
  }

  @override
  Future<PlayerRecord> fetchPlayer(String sessionId, String playerId) async {
    final player = players[sessionId]?[playerId];
    if (player == null) {
      throw StateError('Player record not found.');
    }

    return _clonePlayer(player);
  }

  @override
  Future<void> clearPairing(String sessionId, String playerId) async {
    final player = players[sessionId]?[playerId];
    if (player == null) return;
    player
      ..pairedWith = null
      ..pairedRound = null
      ..partnerCode = null
      ..interactionRound = 1
      ..continueVoteRound = null;
  }

  @override
  Future<void> updateRoundPrompts({
    required String sessionId,
    required String playerId,
    required int round,
    required List<String> promptEntries,
    required List<String> askedPromptIds,
    int interactionRound = 1,
    int? continueVoteRound,
  }) async {
    final player = players[sessionId]?[playerId];
    if (player == null) {
      throw StateError('Player record not found.');
    }

    player
      ..interactionRound = interactionRound
      ..continueVoteRound = continueVoteRound
      ..currentPromptRound = round
      ..currentPromptIndex = 0
      ..currentRoundPrompts = List<String>.from(promptEntries)
      ..askedPromptIds = List<String>.from(askedPromptIds);
  }

  @override
  Future<void> setContinueVote({
    required String sessionId,
    required String playerId,
    required int continueVoteRound,
  }) async {
    final player = players[sessionId]?[playerId];
    if (player == null) {
      throw StateError('Player record not found.');
    }

    player.continueVoteRound = continueVoteRound;
  }
}

PlayerRecord _clonePlayer(PlayerRecord player) {
  return PlayerRecord.fromJson(
    player.id,
    Map<String, dynamic>.from(player.toJson()),
  );
}

class FakePromptCatalogService extends PromptCatalogService {
  @override
  Future<PromptCatalog> loadDatingCatalog() async {
    return const PromptCatalog(
      sets: <String, List<PromptItem>>{
        'icebreakers_level1': <PromptItem>[
          PromptItem(id: 'p1', text: 'Prompt 1'),
        ],
        'activities_level1': <PromptItem>[
          PromptItem(id: 'p2', text: 'Prompt 2'),
        ],
        'dating_questions_level1': <PromptItem>[
          PromptItem(id: 'p3', text: 'Prompt 3'),
        ],
        'icebreakers_level2': <PromptItem>[
          PromptItem(id: 'p4', text: 'Prompt 4'),
        ],
      },
      itemsById: <String, PromptItem>{
        'p1': PromptItem(id: 'p1', text: 'Prompt 1'),
        'p2': PromptItem(id: 'p2', text: 'Prompt 2'),
        'p3': PromptItem(id: 'p3', text: 'Prompt 3'),
        'p4': PromptItem(id: 'p4', text: 'Prompt 4'),
      },
    );
  }
}

class FakeSessionStateStore extends SessionStateStore {
  FakeSessionStateStore({this.savedState});

  PersistedSessionState? savedState;

  @override
  Future<void> clear() async {
    savedState = null;
  }

  @override
  Future<PersistedSessionState?> load() async => savedState;

  @override
  Future<void> save({
    required String sessionId,
    required String playerId,
  }) async {
    savedState = PersistedSessionState(
      sessionId: sessionId,
      playerId: playerId,
    );
  }
}

PlayerRecord _buildPairedPlayer({
  required String id,
  required String name,
  required String partnerId,
  int interactionRound = 1,
  int? continueVoteRound,
  List<String> currentRoundPrompts = const ['p1', 'p2', 'p3'],
  List<String> askedPromptIds = const ['p1', 'p2', 'p3'],
  int currentPromptIndex = 2,
}) {
  return PlayerRecord(
    id: id,
    name: name,
    phone: '',
    gender: '',
    sexualPreference: '',
    acceptedTermsAndGameTexts: true,
    acceptedPromoTexts: false,
    roundPreference: RoundPreference.playful,
    inviteCode: id == 'player-1' ? 'AB12' : 'CD34',
    pairedWith: partnerId,
    pairedRound: 1,
    interactionRound: interactionRound,
    continueVoteRound: continueVoteRound,
    currentPromptRound: 1,
    currentPromptIndex: currentPromptIndex,
    currentRoundPrompts: currentRoundPrompts,
    askedPromptIds: askedPromptIds,
  );
}
