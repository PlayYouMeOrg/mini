import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mini/main.dart';
import 'package:mini/session_domain.dart';
import 'package:mini/session_flow_bootstrap.dart';
import 'package:mini/story_prompt_demo.dart';

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
      expect(find.text('Story'), findsOneWidget);
    });

    testWidgets('shows story mode directly from preview controls', (
      tester,
    ) async {
      await _pumpFlow(
        tester,
        initialUri: Uri.parse('https://example.com/?preview=1'),
      );

      await tester.tap(find.text('Story'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await _dismissGotItIfVisible(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Story Cards'), findsNothing);
      expect(find.text('Story mode'), findsNothing);
      expect(_visibleStoryCategoryCount(), 1);
      expect(
        find.byIcon(Icons.radio_button_unchecked_rounded),
        findsNWidgets(3),
      );
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
        currentRoundPrompts: const ['p1', 'p2', 'p3', storyModePromptId],
        askedPromptIds: const ['p1', 'p2', 'p3'],
        currentPromptIndex: 3,
        activeTurnPlayerId: null,
      );
      final partner = _buildPairedPlayer(
        id: 'player-2',
        name: 'Taylor',
        partnerId: 'player-1',
        currentRoundPrompts: const ['p1b', 'p2b', 'p3b', storyModePromptId],
        askedPromptIds: const ['p1b', 'p2b', 'p3b'],
        currentPromptIndex: 3,
        activeTurnPlayerId: null,
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
      await _dismissGotItIfVisible(tester);

      final gameView = tester.widget<GameView>(find.byType(GameView));
      await gameView.onContinueInteraction();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(me.interactionRound, 1);
      expect(me.continueVoteRound, 2);
      expect(
        find.text('You picked keep going. Round 2 starts only if they do too.'),
        findsOneWidget,
      );

      partner.continueVoteRound = 2;

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final updatedMe = fakeRtdbService.players['demo-public']![me.id]!;
      final updatedPartner =
          fakeRtdbService.players['demo-public']![partner.id]!;
      expect(updatedMe.interactionRound, 2);
      expect(updatedMe.continueVoteRound, isNull);
      expect(updatedMe.currentRoundPrompts,
          isNot(updatedPartner.currentRoundPrompts));
      expect(updatedMe.currentRoundPrompts, hasLength(3));
      expect(updatedPartner.currentRoundPrompts, hasLength(3));
      expect(updatedMe.activeTurnPlayerId, 'player-2');
      expect(find.text('Ask same question'), findsOneWidget);
    });

    testWidgets(
      'shows meet someone else popup when partner declines after keep going',
      (tester) async {
        final me = _buildPairedPlayer(
          id: 'player-1',
          name: 'Avery',
          partnerId: 'player-2',
          currentRoundPrompts: const ['p1', 'p2', 'p3', storyModePromptId],
          askedPromptIds: const ['p1', 'p2', 'p3'],
          currentPromptIndex: 3,
          activeTurnPlayerId: null,
        );
        final partner = _buildPairedPlayer(
          id: 'player-2',
          name: 'Taylor',
          partnerId: 'player-1',
          currentRoundPrompts: const ['p1b', 'p2b', 'p3b', storyModePromptId],
          askedPromptIds: const ['p1b', 'p2b', 'p3b'],
          currentPromptIndex: 3,
          activeTurnPlayerId: null,
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
        await _dismissGotItIfVisible(tester);

        final gameView = tester.widget<GameView>(find.byType(GameView));
        await gameView.onContinueInteraction();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

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
              sessionId: 'test-session',
              player: player,
              session: SessionRecord(status: 'started', round: 1),
              onSubmitCode: (_) async {},
              onDrawPrompt: ({
                required int promptIndex,
                required String partnerId,
              }) async {},
              onAskSameQuestion: () async {},
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

      await _dismissGotItIfVisible(tester);

      final promptText = tester.widgetList<Text>(find.text(longPrompt)).first;
      expect(promptText.style?.fontSize, lessThan(28));
    });

    testWidgets('starts prompt stacking from zero completed cards', (
      tester,
    ) async {
      final promptCatalog =
          await FakePromptCatalogService().loadDatingCatalog();
      final player = _buildPairedPlayer(
        id: 'player-1',
        name: 'Preview User',
        partnerId: 'player-2',
        currentPromptIndex: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameView(
              sessionId: 'test-session',
              player: player,
              session: SessionRecord(status: 'started', round: 1),
              onSubmitCode: (_) async {},
              onDrawPrompt: ({
                required int promptIndex,
                required String partnerId,
              }) async {},
              onAskSameQuestion: () async {},
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
      await _dismissGotItIfVisible(tester);

      expect(find.text('Prompt 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('prompt-stack-card-0')), findsNothing);
    });

    testWidgets('round 2 completion does not offer keep going', (
      tester,
    ) async {
      final promptCatalog =
          await FakePromptCatalogService().loadDatingCatalog();
      StateSetter? rebuild;
      var player = _buildPairedPlayer(
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
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Scaffold(
                body: GameView(
                  sessionId: 'test-session',
                  player: player,
                  session: SessionRecord(status: 'started', round: 1),
                  onSubmitCode: (_) async {},
                  onDrawPrompt: ({
                    required int promptIndex,
                    required String partnerId,
                  }) async {
                    rebuild?.call(() {
                      player = PlayerRecord.fromJson(
                        player.id,
                        Map<String, dynamic>.from(player.toJson()),
                      )
                        ..currentPromptIndex = 1
                        ..activeTurnPlayerId = null;
                    });
                  },
                  onAskSameQuestion: () async {},
                  onContinueInteraction: () async {},
                  promptCatalog: promptCatalog,
                  unpairedInstructions:
                      'Enter any 4-character code to connect instantly.',
                  codeEntryPrompt: 'Enter any 4-character code to start:',
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await _dismissGotItIfVisible(tester);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();

      expect(find.text('Pass turn'), findsOneWidget);

      await tester.ensureVisible(find.text('Pass turn'));
      await tester.tap(find.text('Pass turn'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
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

    testWidgets('shows same-question prompt while waiting for partner turn', (
      tester,
    ) async {
      final promptCatalog =
          await FakePromptCatalogService().loadDatingCatalog();
      final player = _buildPairedPlayer(
        id: 'player-1',
        name: 'Preview User',
        partnerId: 'player-2',
        currentPromptIndex: 0,
        activeTurnPlayerId: 'player-2',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameView(
              sessionId: 'test-session',
              player: player,
              session: SessionRecord(status: 'started', round: 1),
              onSubmitCode: (_) async {},
              onDrawPrompt: ({
                required int promptIndex,
                required String partnerId,
              }) async {},
              onAskSameQuestion: () async {},
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
      await _dismissGotItIfVisible(tester);

      expect(find.text('Ask same question'), findsOneWidget);
      expect(
        find.textContaining('your next turn will be skipped'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('prompt-stack-card-0')), findsNothing);
    });

    testWidgets('keeps completed cards stacked while waiting for partner turn',
        (
      tester,
    ) async {
      final promptCatalog =
          await FakePromptCatalogService().loadDatingCatalog();
      final player = _buildPairedPlayer(
        id: 'player-1',
        name: 'Preview User',
        partnerId: 'player-2',
        currentPromptIndex: 2,
        activeTurnPlayerId: 'player-2',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameView(
              sessionId: 'test-session',
              player: player,
              session: SessionRecord(status: 'started', round: 1),
              onSubmitCode: (_) async {},
              onDrawPrompt: ({
                required int promptIndex,
                required String partnerId,
              }) async {},
              onAskSameQuestion: () async {},
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
      await _dismissGotItIfVisible(tester);

      expect(find.text('Ask same question'), findsOneWidget);
      expect(find.byKey(const ValueKey('prompt-stack-card-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('prompt-stack-card-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('prompt-stack-card-2')), findsNothing);
    });

    testWidgets('shows server-backed story options on the fourth card', (
      tester,
    ) async {
      final promptCatalog =
          await FakePromptCatalogService().loadDatingCatalog();
      final fakeRtdbService = FakeRtdbService();
      final player = _buildPairedPlayer(
        id: 'player-1',
        name: 'Preview User',
        partnerId: 'player-2',
        currentRoundPrompts: const ['p1', 'p2', 'p3', storyModePromptId],
        askedPromptIds: const ['p1', 'p2', 'p3'],
        currentPromptIndex: 3,
        activeTurnPlayerId: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameView(
              sessionId: 'test-session',
              player: player,
              session: SessionRecord(status: 'started', round: 1),
              onSubmitCode: (_) async {},
              onDrawPrompt: ({
                required int promptIndex,
                required String partnerId,
              }) async {},
              onAskSameQuestion: () async {},
              onContinueInteraction: () async {},
              promptCatalog: promptCatalog,
              storyPromptCatalogService: FakeStoryPromptCatalogService(),
              storyRtdbService: fakeRtdbService,
              unpairedInstructions:
                  'Enter any 4-character code to connect instantly.',
              codeEntryPrompt: 'Enter any 4-character code to start:',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await _dismissGotItIfVisible(tester);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();

      expect(find.text('Story Cards'), findsNothing);
      expect(find.text('Story mode'), findsNothing);
      expect(_visibleStoryCategoryCount(), 1);
      expect(find.text('Category'), findsNothing);
      expect(find.text('End interaction'), findsNothing);
      expect(find.text('Finish interaction'), findsNothing);
      expect(
        find.byIcon(Icons.radio_button_unchecked_rounded),
        findsNWidgets(3),
      );
    });

    testWidgets('hides story prompts after submit and shows loading state', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final promptCatalog =
          await FakePromptCatalogService().loadDatingCatalog();
      final fakeRtdbService = FakeRtdbService();
      final player = _buildPairedPlayer(
        id: 'player-1',
        name: 'Preview User',
        partnerId: 'player-2',
        currentRoundPrompts: const ['p1', 'p2', 'p3', storyModePromptId],
        askedPromptIds: const ['p1', 'p2', 'p3'],
        currentPromptIndex: 3,
        activeTurnPlayerId: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameView(
              sessionId: 'test-session',
              player: player,
              session: SessionRecord(status: 'started', round: 1),
              onSubmitCode: (_) async {},
              onDrawPrompt: ({
                required int promptIndex,
                required String partnerId,
              }) async {},
              onAskSameQuestion: () async {},
              onContinueInteraction: () async {},
              promptCatalog: promptCatalog,
              storyPromptCatalogService: FakeStoryPromptCatalogService(),
              storyRtdbService: fakeRtdbService,
              unpairedInstructions:
                  'Enter any 4-character code to connect instantly.',
              codeEntryPrompt: 'Enter any 4-character code to start:',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await _dismissGotItIfVisible(tester);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();

      for (var index = 0; index < 3; index += 1) {
        final choice = find.byIcon(Icons.radio_button_unchecked_rounded).first;
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pump();
      }

      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Choose 1 item from each category card.'), findsNothing);
      expect(find.text('Writing your story'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows end interaction only after a story is available', (
      tester,
    ) async {
      final promptCatalog =
          await FakePromptCatalogService().loadDatingCatalog();
      final fakeRtdbService = FakeRtdbService();
      final player = _buildPairedPlayer(
        id: 'player-1',
        name: 'Preview User',
        partnerId: 'player-2',
        currentRoundPrompts: const ['p1', 'p2', 'p3', storyModePromptId],
        askedPromptIds: const ['p1', 'p2', 'p3'],
        currentPromptIndex: 3,
        activeTurnPlayerId: null,
      );
      final pairId = buildStoryPairId(
        sessionId: 'test-session',
        playerId: player.id,
        partnerId: player.pairedWith!,
        pairRound: player.pairedRound ?? 1,
      );
      fakeRtdbService.storyPairPlayers[pairId] = {
        player.id: _buildCompletedStoryPairPlayer(
          playerId: player.id,
          playerName: player.name,
          partnerId: player.pairedWith!,
          sessionId: 'test-session',
          pairRound: player.pairedRound ?? 1,
        ),
      };
      fakeRtdbService.storyPairStories[pairId] =
          'They left with the same private joke and a second date.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameView(
              sessionId: 'test-session',
              player: player,
              session: SessionRecord(status: 'started', round: 1),
              onSubmitCode: (_) async {},
              onDrawPrompt: ({
                required int promptIndex,
                required String partnerId,
              }) async {},
              onAskSameQuestion: () async {},
              onContinueInteraction: () async {},
              promptCatalog: promptCatalog,
              storyPromptCatalogService: FakeStoryPromptCatalogService(),
              storyRtdbService: fakeRtdbService,
              unpairedInstructions:
                  'Enter any 4-character code to connect instantly.',
              codeEntryPrompt: 'Enter any 4-character code to start:',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await _dismissGotItIfVisible(tester);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();

      expect(find.text('Story Cards'), findsNothing);
      expect(find.text('Generated result'), findsOneWidget);
      expect(
        find.text(
          'They left with the same private joke and a second date.',
        ),
        findsOneWidget,
      );

      Navigator.of(tester.element(find.text('Generated result'))).pop();
      await tester.pumpAndSettle();

      expect(find.text('End interaction'), findsOneWidget);
      expect(find.text('Open story page again'), findsOneWidget);
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

Future<void> _dismissGotItIfVisible(WidgetTester tester) async {
  final finder = find.text('Got it');
  if (finder.evaluate().isEmpty) return;

  await tester.ensureVisible(finder);
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

int _visibleStoryCategoryCount() {
  final categoryFinders = [
    find.text('Action'),
    find.text('Animal'),
    find.text('Clothing'),
  ];
  return categoryFinders.where((finder) => finder.evaluate().isNotEmpty).length;
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
  final Map<String, Map<String, StoryPairPlayerRecord>> storyPairPlayers =
      <String, Map<String, StoryPairPlayerRecord>>{};
  final Map<String, StoryPairResultRecord> storyPairResults =
      <String, StoryPairResultRecord>{};
  final Map<String, String> storyPairStories = <String, String>{};
  final Map<String, String> storyPairPrompts = <String, String>{};
  final Map<String, bool> storyPairReady = <String, bool>{};
  final Object? fetchSessionError;
  int savePlayerCalls = 0;

  @override
  Future<Object?> fetchValue(String path) async {
    if (path == 'mini/prompts') {
      return const {
        'Story': {
          'playerPrompt': 'Choose one option from each card.',
          'categories': {
            'Action': ['kiss', 'tease', 'chase', 'hide'],
            'Animal': ['fox', 'owl', 'wolf', 'cat'],
            'Clothing': ['leather', 'silk', 'denim', 'linen'],
          },
        },
      };
    }

    throw StateError('Unexpected fetchValue path: $path');
  }

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
      ..continueVoteRound = null
      ..activeTurnPlayerId = null
      ..skipNextTurn = false;
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
    String? activeTurnPlayerId,
    bool skipNextTurn = false,
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
      ..activeTurnPlayerId = activeTurnPlayerId
      ..skipNextTurn = skipNextTurn
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

  @override
  Future<void> setSkipNextTurn({
    required String sessionId,
    required String playerId,
    required bool skipNextTurn,
  }) async {
    final player = players[sessionId]?[playerId];
    if (player == null) {
      throw StateError('Player record not found.');
    }

    player.skipNextTurn = skipNextTurn;
  }

  @override
  Future<StoryPairPlayerRecord?> fetchStoryPairPlayer({
    required String pairId,
    required String playerId,
  }) async {
    final player = storyPairPlayers[pairId]?[playerId];
    if (player == null) return null;
    return StoryPairPlayerRecord.fromJson(player.toJson());
  }

  @override
  Future<StoryPairResultRecord?> fetchStoryPairResult(String pairId) async {
    final story = storyPairStories[pairId];
    if (story != null && story.trim().isNotEmpty) {
      return StoryPairResultRecord(status: 'complete', text: story);
    }

    final result = storyPairResults[pairId];
    if (result != null) {
      return StoryPairResultRecord.fromJson(result.toJson());
    }

    if (storyPairReady[pairId] == true ||
        (storyPairPrompts[pairId]?.trim().isNotEmpty ?? false)) {
      return const StoryPairResultRecord(status: 'waiting');
    }

    return null;
  }

  @override
  Future<void> saveStoryPairPlayer({
    required String pairId,
    required StoryPairPlayerRecord player,
  }) async {
    storyPairPlayers.putIfAbsent(
            pairId, () => <String, StoryPairPlayerRecord>{})[player.playerId] =
        StoryPairPlayerRecord.fromJson(player.toJson());

    final players = storyPairPlayers[pairId]!.values;
    final storyReady = isStoryPairReady(players);
    final storyPrompt = storyReady ? buildStoryPairPrompt(players) : null;
    if (!storyReady || storyPrompt == null) {
      storyPairPrompts.remove(pairId);
      storyPairReady[pairId] = false;
      return;
    }

    storyPairPrompts[pairId] = storyPrompt;
    storyPairReady[pairId] = true;
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
          PromptItem(id: 'p1b', text: 'Prompt 1B'),
          PromptItem(id: 'p1c', text: 'Prompt 1C'),
          PromptItem(id: 'p1d', text: 'Prompt 1D'),
        ],
        'activities_level1': <PromptItem>[
          PromptItem(id: 'p2', text: 'Prompt 2'),
          PromptItem(id: 'p2b', text: 'Prompt 2B'),
          PromptItem(id: 'p2c', text: 'Prompt 2C'),
          PromptItem(id: 'p2d', text: 'Prompt 2D'),
        ],
        'dating_questions_level1': <PromptItem>[
          PromptItem(id: 'p3', text: 'Prompt 3'),
          PromptItem(id: 'p3b', text: 'Prompt 3B'),
          PromptItem(id: 'p3c', text: 'Prompt 3C'),
          PromptItem(id: 'p3d', text: 'Prompt 3D'),
        ],
        'icebreakers_level2': <PromptItem>[
          PromptItem(id: 'p4', text: 'Prompt 4'),
          PromptItem(id: 'p4b', text: 'Prompt 4B'),
          PromptItem(id: 'p4c', text: 'Prompt 4C'),
          PromptItem(id: 'p4d', text: 'Prompt 4D'),
          PromptItem(id: 'p4e', text: 'Prompt 4E'),
          PromptItem(id: 'p4f', text: 'Prompt 4F'),
        ],
      },
      itemsById: <String, PromptItem>{
        'p1': PromptItem(id: 'p1', text: 'Prompt 1'),
        'p1b': PromptItem(id: 'p1b', text: 'Prompt 1B'),
        'p1c': PromptItem(id: 'p1c', text: 'Prompt 1C'),
        'p1d': PromptItem(id: 'p1d', text: 'Prompt 1D'),
        'p2': PromptItem(id: 'p2', text: 'Prompt 2'),
        'p2b': PromptItem(id: 'p2b', text: 'Prompt 2B'),
        'p2c': PromptItem(id: 'p2c', text: 'Prompt 2C'),
        'p2d': PromptItem(id: 'p2d', text: 'Prompt 2D'),
        'p3': PromptItem(id: 'p3', text: 'Prompt 3'),
        'p3b': PromptItem(id: 'p3b', text: 'Prompt 3B'),
        'p3c': PromptItem(id: 'p3c', text: 'Prompt 3C'),
        'p3d': PromptItem(id: 'p3d', text: 'Prompt 3D'),
        'p4': PromptItem(id: 'p4', text: 'Prompt 4'),
        'p4b': PromptItem(id: 'p4b', text: 'Prompt 4B'),
        'p4c': PromptItem(id: 'p4c', text: 'Prompt 4C'),
        'p4d': PromptItem(id: 'p4d', text: 'Prompt 4D'),
        'p4e': PromptItem(id: 'p4e', text: 'Prompt 4E'),
        'p4f': PromptItem(id: 'p4f', text: 'Prompt 4F'),
      },
    );
  }
}

class FakeStoryPromptCatalogService implements StoryPromptCatalogService {
  @override
  Future<StoryPromptDeck> loadStoryDeck() async {
    return const StoryPromptDeck(
      playerPrompt: 'Choose one option from each card.',
      categories: <StoryPromptType>[
        StoryPromptType(
          category: 'Action',
          options: ['kiss', 'tease', 'chase', 'hide'],
        ),
        StoryPromptType(
          category: 'Animal',
          options: ['fox', 'owl', 'wolf', 'cat'],
        ),
        StoryPromptType(
          category: 'Clothing',
          options: ['leather', 'silk', 'denim', 'linen'],
        ),
      ],
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

const _defaultTurnOwner = Object();

PlayerRecord _buildPairedPlayer({
  required String id,
  required String name,
  required String partnerId,
  int interactionRound = 1,
  int? continueVoteRound,
  List<String> currentRoundPrompts = const ['p1', 'p2', 'p3'],
  List<String> askedPromptIds = const ['p1', 'p2', 'p3'],
  int currentPromptIndex = 2,
  Object? activeTurnPlayerId = _defaultTurnOwner,
  bool skipNextTurn = false,
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
    activeTurnPlayerId: identical(activeTurnPlayerId, _defaultTurnOwner)
        ? id
        : activeTurnPlayerId as String?,
    skipNextTurn: skipNextTurn,
    currentRoundPrompts: currentRoundPrompts,
    askedPromptIds: askedPromptIds,
  );
}

StoryPairPlayerRecord _buildCompletedStoryPairPlayer({
  required String playerId,
  required String playerName,
  required String partnerId,
  required String sessionId,
  required int pairRound,
}) {
  return StoryPairPlayerRecord(
    playerId: playerId,
    name: playerName,
    sessionId: sessionId,
    partnerId: partnerId,
    pairRound: pairRound,
    completedAt: 1,
    choices: const [
      StoryPairChoiceRecord(
        typeName: 'Action',
        category: 'Action',
        options: ['kiss', 'tease', 'chase', 'hide'],
        selectedOption: 'kiss',
      ),
      StoryPairChoiceRecord(
        typeName: 'Animal',
        category: 'Animal',
        options: ['fox', 'owl', 'wolf', 'cat'],
        selectedOption: 'fox',
      ),
      StoryPairChoiceRecord(
        typeName: 'Clothing',
        category: 'Clothing',
        options: ['leather', 'silk', 'denim', 'linen'],
        selectedOption: 'leather',
      ),
    ],
  );
}
