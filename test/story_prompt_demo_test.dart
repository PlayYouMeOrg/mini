import 'package:flutter_test/flutter_test.dart';

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
          categories.take(5).toList(),
          playerIds: const ['player-a', 'player-b'],
          seed: 'pair-99',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
