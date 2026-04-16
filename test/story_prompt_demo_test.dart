import 'package:flutter_test/flutter_test.dart';

import 'package:mini/session_domain.dart';
import 'package:mini/story_prompt_demo.dart';

void main() {
  group('parseStoryPromptDeck', () {
    test('parses nested Story prompt data with prompt copy and categories', () {
      final deck = parseStoryPromptDeck({
        'mini': {
          'prompts': {
            'Story': {
              'playerPrompt': 'Choose one item from each card.',
              'nextLevel': {
                'categories': {
                  'Vibe': {
                    'items': ['Playful', 'Romantic', 'Bold'],
                  },
                  'Date': {
                    'options': [
                      'Rooftop picnic',
                      'Night market',
                      'Museum sprint',
                    ],
                  },
                  'Twist': {
                    '1': 'Unexpected rain',
                    '2': 'Secret challenge',
                    '3': 'Lost reservation',
                  },
                },
              },
            },
          },
        },
      });

      expect(deck.playerPrompt, 'Choose one item from each card.');
      expect(deck.categories, hasLength(3));
      expect(
        deck.categories.map((category) => category.category),
        containsAll(<String>['Vibe', 'Date', 'Twist']),
      );
      expect(
        deck.categories
            .firstWhere((category) => category.category == 'Twist')
            .options,
        orderedEquals(<String>[
          'Unexpected rain',
          'Secret challenge',
          'Lost reservation',
        ]),
      );
    });

    test('parses mixed direct and nested option values inside a category', () {
      final deck = parseStoryPromptDeck({
        'mini': {
          'prompts': {
            'Story': {
              'Action': {
                '0': 'kiss',
                '1': 'tease',
                '2': 'chase',
                '3': {
                  'value': 'hide',
                },
              },
              'Animal': {
                'items': ['fox', 'owl', 'wolf'],
              },
              'Clothing': {
                'items': ['leather', 'silk', 'denim'],
              },
            },
          },
        },
      });

      expect(
        deck.categories
            .firstWhere((category) => category.category == 'Action')
            .options,
        orderedEquals(<String>['kiss', 'tease', 'chase', 'hide']),
      );
    });

    test('parses direct array values for Story categories', () {
      final deck = parseStoryPromptDeck({
        'Story': {
          'Action': ['kiss', 'tease', 'chase'],
          'Animal': ['fox', 'owl', 'wolf'],
          'Clothing': ['leather', 'silk', 'denim'],
        },
      });

      expect(
        deck.categories.map((category) => category.category),
        containsAll(<String>['Action', 'Animal', 'Clothing']),
      );
      expect(
        deck.categories
            .firstWhere((category) => category.category == 'Action')
            .options,
        orderedEquals(<String>['kiss', 'tease', 'chase']),
      );
    });
  });

  group('StoryPromptCardDealer', () {
    final categories = <StoryPromptType>[
      const StoryPromptType(
        category: 'Vibe',
        options: ['Playful', 'Romantic', 'Bold', 'Soft'],
      ),
      const StoryPromptType(
        category: 'Date',
        options: ['Rooftop', 'Market', 'Museum', 'Picnic'],
      ),
      const StoryPromptType(
        category: 'Twist',
        options: ['Rain', 'Challenge', 'Detour', 'Fireworks'],
      ),
      const StoryPromptType(
        category: 'Soundtrack',
        options: ['Jazz', 'Disco', 'Lo-fi', 'Pop'],
      ),
      const StoryPromptType(
        category: 'Setting',
        options: ['City', 'Beach', 'Cabin', 'Garden'],
      ),
      const StoryPromptType(
        category: 'Energy',
        options: ['Calm', 'Electric', 'Cozy', 'Wild'],
      ),
    ];

    test('deals deterministic non-overlapping categories for both players', () {
      final dealer = StoryPromptCardDealer();

      final firstDeal = dealer.dealPromptCardsForPlayers(
        categories,
        playerIds: const ['player-b', 'player-a'],
        seed: 'pair-42',
        playerPrompt: 'Pick one from each card.',
      );
      final secondDeal = dealer.dealPromptCardsForPlayers(
        categories,
        playerIds: const ['player-a', 'player-b'],
        seed: 'pair-42',
        playerPrompt: 'Pick one from each card.',
      );

      final playerACard = firstDeal['player-a']!;
      final playerBCard = firstDeal['player-b']!;
      final playerACategories =
          playerACard.choices.map((choice) => choice.category).toSet();
      final playerBCategories =
          playerBCard.choices.map((choice) => choice.category).toSet();

      expect(playerACard.playerPrompt, 'Pick one from each card.');
      expect(playerBCard.playerPrompt, 'Pick one from each card.');
      expect(playerACategories, hasLength(3));
      expect(playerBCategories, hasLength(3));
      expect(playerACategories.intersection(playerBCategories), isEmpty);
      expect(
        secondDeal['player-a']!.choices.map((choice) => choice.category),
        orderedEquals(playerACard.choices.map((choice) => choice.category)),
      );
      expect(
        secondDeal['player-b']!.choices.map((choice) => choice.category),
        orderedEquals(playerBCard.choices.map((choice) => choice.category)),
      );
      expect(
        secondDeal['player-a']!.choices.first.options,
        orderedEquals(playerACard.choices.first.options),
      );
    });

    test('throws when there are not enough categories for the pair', () {
      final dealer = StoryPromptCardDealer();

      expect(
        () => dealer.dealPromptCardsForPlayers(
          categories.take(2).toList(),
          playerIds: const ['player-a', 'player-b'],
          seed: 'pair-99',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('falls back to overlapping categories when only one hand is available',
        () {
      final dealer = StoryPromptCardDealer();

      final firstDeal = dealer.dealPromptCardsForPlayers(
        categories.take(3).toList(),
        playerIds: const ['player-b', 'player-a'],
        seed: 'pair-77',
      );
      final secondDeal = dealer.dealPromptCardsForPlayers(
        categories.take(3).toList(),
        playerIds: const ['player-a', 'player-b'],
        seed: 'pair-77',
      );

      expect(firstDeal['player-a']!.choices, hasLength(3));
      expect(firstDeal['player-b']!.choices, hasLength(3));
      expect(
        secondDeal['player-a']!.choices.map((choice) => choice.category),
        orderedEquals(
          firstDeal['player-a']!.choices.map((choice) => choice.category),
        ),
      );
      expect(
        secondDeal['player-b']!.choices.map((choice) => choice.category),
        orderedEquals(
          firstDeal['player-b']!.choices.map((choice) => choice.category),
        ),
      );
    });
  });

  group('buildStoryPairPrompt', () {
    test('formats names and selections with commas and spacing', () {
      final prompt = buildStoryPairPrompt([
        StoryPairPlayerRecord(
          playerId: 'player-b',
          name: 'Sam',
          sessionId: 'session-1',
          partnerId: 'player-a',
          pairRound: 1,
          completedAt: 2,
          choices: const [
            StoryPairChoiceRecord(
              typeName: 'Setting',
              category: 'Setting',
              options: ['Rooftop', 'Beach', 'Cabin'],
              selectedOption: 'Rooftop',
            ),
            StoryPairChoiceRecord(
              typeName: 'Weather',
              category: 'Weather',
              options: ['Rain', 'Sun', 'Snow'],
              selectedOption: 'Rain',
            ),
            StoryPairChoiceRecord(
              typeName: 'Twist',
              category: 'Twist',
              options: ['Fireworks', 'Music', 'Detour'],
              selectedOption: 'Fireworks',
            ),
          ],
        ),
        StoryPairPlayerRecord(
          playerId: 'player-a',
          name: 'Alex',
          sessionId: 'session-1',
          partnerId: 'player-b',
          pairRound: 1,
          completedAt: 1,
          choices: const [
            StoryPairChoiceRecord(
              typeName: 'Action',
              category: 'Action',
              options: ['Kiss', 'Tease', 'Chase'],
              selectedOption: 'Kiss',
            ),
            StoryPairChoiceRecord(
              typeName: 'Animal',
              category: 'Animal',
              options: ['Fox', 'Owl', 'Wolf'],
              selectedOption: 'Fox',
            ),
            StoryPairChoiceRecord(
              typeName: 'Clothing',
              category: 'Clothing',
              options: ['Leather', 'Silk', 'Denim'],
              selectedOption: 'Leather',
            ),
          ],
        ),
      ]);

      expect(
        prompt,
        'Names: Alex, Sam\nAlex: Action: Kiss, Animal: Fox, Clothing: Leather\nSam: Setting: Rooftop, Weather: Rain, Twist: Fireworks',
      );
    });

    test('requires both players to finish before the story is ready', () {
      final alex = StoryPairPlayerRecord(
        playerId: 'player-a',
        name: 'Alex',
        sessionId: 'session-1',
        partnerId: 'player-b',
        pairRound: 1,
        completedAt: 1,
        choices: const [
          StoryPairChoiceRecord(
            typeName: 'Action',
            category: 'Action',
            options: ['Kiss', 'Tease', 'Chase'],
            selectedOption: 'Kiss',
          ),
          StoryPairChoiceRecord(
            typeName: 'Animal',
            category: 'Animal',
            options: ['Fox', 'Owl', 'Wolf'],
            selectedOption: 'Fox',
          ),
          StoryPairChoiceRecord(
            typeName: 'Clothing',
            category: 'Clothing',
            options: ['Leather', 'Silk', 'Denim'],
            selectedOption: 'Leather',
          ),
        ],
      );
      final samPending = StoryPairPlayerRecord(
        playerId: 'player-b',
        name: 'Sam',
        sessionId: 'session-1',
        partnerId: 'player-a',
        pairRound: 1,
        choices: const [
          StoryPairChoiceRecord(
            typeName: 'Setting',
            category: 'Setting',
            options: ['Rooftop', 'Beach', 'Cabin'],
            selectedOption: 'Rooftop',
          ),
          StoryPairChoiceRecord(
            typeName: 'Weather',
            category: 'Weather',
            options: ['Rain', 'Sun', 'Snow'],
            selectedOption: 'Rain',
          ),
          StoryPairChoiceRecord(
            typeName: 'Twist',
            category: 'Twist',
            options: ['Fireworks', 'Music', 'Detour'],
            selectedOption: 'Fireworks',
          ),
        ],
      );
      final samComplete = StoryPairPlayerRecord(
        playerId: 'player-b',
        name: 'Sam',
        sessionId: 'session-1',
        partnerId: 'player-a',
        pairRound: 1,
        completedAt: 2,
        choices: samPending.choices,
      );

      expect(isStoryPairReady([alex, samPending]), isFalse);
      expect(isStoryPairReady([alex, samComplete]), isTrue);
    });
  });

  group('StoryPairResultRecord.fromJson', () {
    test('extracts nested story text values', () {
      final result = StoryPairResultRecord.fromJson({
        'status': 'complete',
        'text': {
          'value': 'Two strangers kept choosing the same moonlit detour.',
        },
      });

      expect(result.isComplete, isTrue);
      expect(result.hasText, isTrue);
      expect(
        result.text,
        'Two strangers kept choosing the same moonlit detour.',
      );
    });
  });
}
