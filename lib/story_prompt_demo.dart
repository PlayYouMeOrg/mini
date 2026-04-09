import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'session_domain.dart';

const _demoBackground = Color(0xFFF2E9DD);
const _demoPanel = Color(0xFFF8F2E8);
const _demoCard = Color(0xFFFFFCF6);
const _demoBorder = Color(0xFFD4C2A9);
const _demoInk = Color(0xFF1D1A16);
const _demoMutedInk = Color(0xFF685E54);
const _demoAccent = Color(0xFFB85432);
const _demoAccentSoft = Color(0xFFF6E0D4);
const _storyPromptPath = 'mini/prompts';
const _storyMetadataKeys = <String>{
  'prompt',
  'playerprompt',
  'player_prompt',
  'question',
  'intro',
  'instruction',
  'instructions',
  'copy',
  'description',
  'subtitle',
  'headline',
  'title',
  'story',
};
const _storyContainerKeys = <String>{
  'categories',
  'cards',
  'types',
  'levels',
  'level',
  'nextlevel',
  'next_level',
  'groups',
};
const _storyOptionCollectionKeys = <String>{
  'options',
  'items',
  'values',
  'prompts',
  'choices',
};

class StoryPromptDeck {
  const StoryPromptDeck({
    required this.categories,
    this.playerPrompt,
  });

  final List<StoryPromptType> categories;
  final String? playerPrompt;
}

class StoryPromptType {
  const StoryPromptType({
    required this.category,
    required this.options,
  });

  final String category;
  final List<String> options;

  String get name => category;
}

class StoryPromptChoice {
  const StoryPromptChoice({
    required this.category,
    required this.options,
    this.selectedOption,
  });

  final String category;
  final List<String> options;
  final String? selectedOption;

  String get typeName => category;

  StoryPromptChoice copyWith({String? selectedOption}) {
    return StoryPromptChoice(
      category: category,
      options: options,
      selectedOption: selectedOption,
    );
  }

  StoryPairChoiceRecord toRecord() {
    return StoryPairChoiceRecord(
      typeName: category,
      options: options,
      category: category,
      selectedOption: selectedOption,
    );
  }

  factory StoryPromptChoice.fromRecord(StoryPairChoiceRecord record) {
    return StoryPromptChoice(
      category: (record.category ?? record.typeName).trim(),
      options: record.options,
      selectedOption: record.selectedOption,
    );
  }
}

class StoryPromptCardData {
  const StoryPromptCardData({
    required this.playerIndex,
    required this.choices,
    this.playerPrompt,
  });

  final int playerIndex;
  final List<StoryPromptChoice> choices;
  final String? playerPrompt;

  bool get isComplete => choices
      .every((choice) => (choice.selectedOption ?? '').trim().isNotEmpty);

  StoryPromptCardData updateSelection({
    required int choiceIndex,
    required String selectedOption,
  }) {
    return StoryPromptCardData(
      playerIndex: playerIndex,
      playerPrompt: playerPrompt,
      choices: [
        for (var index = 0; index < choices.length; index += 1)
          if (index == choiceIndex)
            choices[index].copyWith(selectedOption: selectedOption)
          else
            choices[index],
      ],
    );
  }

  List<StoryPairChoiceRecord> toRecords() {
    return choices.map((choice) => choice.toRecord()).toList();
  }

  factory StoryPromptCardData.fromRecords({
    required int playerIndex,
    required List<StoryPairChoiceRecord> records,
    String? playerPrompt,
  }) {
    return StoryPromptCardData(
      playerIndex: playerIndex,
      playerPrompt: playerPrompt,
      choices: records.map(StoryPromptChoice.fromRecord).toList(),
    );
  }
}

class StoryPromptAnswer {
  const StoryPromptAnswer({
    required this.typeName,
    required this.answer,
  });

  final String typeName;
  final String answer;
}

class StoryPromptSubmission {
  const StoryPromptSubmission({
    required this.playerOneName,
    required this.playerTwoName,
    required this.playerOneAnswers,
    required this.playerTwoAnswers,
  });

  final String playerOneName;
  final String playerTwoName;
  final List<StoryPromptAnswer> playerOneAnswers;
  final List<StoryPromptAnswer> playerTwoAnswers;
}

StoryPromptDeck parseStoryPromptDeck(Object? raw) {
  final promptRoot = _resolveStoryPromptRoot(raw);
  if (promptRoot is! Map) {
    throw StateError('Expected a map at $_storyPromptPath/Story.');
  }

  final types = <StoryPromptType>[];
  final seenCategories = <String>{};
  _collectStoryPromptTypes(promptRoot, types, seenCategories);

  if (types.length < 3) {
    throw StateError(
      'Need at least three prompt types with three options each under $_storyPromptPath/Story.',
    );
  }

  return StoryPromptDeck(
    categories: types,
    playerPrompt: _extractStoryPlayerPrompt(promptRoot),
  );
}

List<StoryPromptType> parseStoryPromptTypes(Object? raw) {
  return parseStoryPromptDeck(raw).categories;
}

Object? _resolveStoryPromptRoot(Object? raw) {
  if (raw is! Map) return raw;

  final storyEntry = raw.entries.cast<MapEntry<Object?, Object?>>().firstWhere(
        (entry) => entry.key.toString().toLowerCase() == 'story',
        orElse: () => const MapEntry<Object?, Object?>('__missing__', null),
      );
  if (storyEntry.key != '__missing__') {
    return storyEntry.value;
  }

  final promptsEntry =
      raw.entries.cast<MapEntry<Object?, Object?>>().firstWhere(
            (entry) => entry.key.toString().toLowerCase() == 'prompts',
            orElse: () => const MapEntry<Object?, Object?>('__missing__', null),
          );
  if (promptsEntry.key != '__missing__') {
    return _resolveStoryPromptRoot(promptsEntry.value);
  }

  final miniEntry = raw.entries.cast<MapEntry<Object?, Object?>>().firstWhere(
        (entry) => entry.key.toString().toLowerCase() == 'mini',
        orElse: () => const MapEntry<Object?, Object?>('__missing__', null),
      );
  if (miniEntry.key != '__missing__') {
    return _resolveStoryPromptRoot(miniEntry.value);
  }

  return raw;
}

String? _extractStoryPlayerPrompt(Object? raw) {
  if (raw is! Map) return null;
  for (final key in const [
    'playerPrompt',
    'player_prompt',
    'prompt',
    'question',
    'intro',
    'instruction',
    'instructions',
    'copy',
    'description',
  ]) {
    final value = _extractFirstNonEmptyString(_lookupCaseInsensitive(raw, key));
    if (value != null) return value;
  }
  return null;
}

void _collectStoryPromptTypes(
  Object? raw,
  List<StoryPromptType> types,
  Set<String> seenCategories, {
  String? fallbackName,
}) {
  if (raw is List) {
    final categoryName = _extractCategoryName(raw, fallbackName);
    final options = _extractPromptOptions(raw);
    if (categoryName != null && options.length >= 3) {
      final normalizedKey = categoryName.toLowerCase();
      if (seenCategories.add(normalizedKey)) {
        types.add(StoryPromptType(category: categoryName, options: options));
      }
      return;
    }

    for (final item in raw) {
      _collectStoryPromptTypes(
        item,
        types,
        seenCategories,
        fallbackName: fallbackName,
      );
    }
    return;
  }
  if (raw is! Map) return;

  final categoryName = _extractCategoryName(raw, fallbackName);
  final options = _extractPromptOptions(raw);
  if (categoryName != null && options.length >= 3) {
    final normalizedKey = categoryName.toLowerCase();
    if (seenCategories.add(normalizedKey)) {
      types.add(StoryPromptType(category: categoryName, options: options));
    }
    return;
  }

  final entries = raw.entries.toList()
    ..sort((left, right) => _comparePromptNodeKeys(left.key, right.key));
  for (final entry in entries) {
    final key = entry.key.toString().trim();
    if (key.isEmpty) continue;
    final normalizedKey = key.toLowerCase();
    if (_storyMetadataKeys.contains(normalizedKey) ||
        _storyOptionCollectionKeys.contains(normalizedKey)) {
      continue;
    }
    _collectStoryPromptTypes(
      entry.value,
      types,
      seenCategories,
      fallbackName: key,
    );
  }
}

String? _extractCategoryName(Object? raw, String? fallbackName) {
  if (raw is Map) {
    for (final key in const [
      'category',
      'name',
      'label',
      'title',
      'typeName'
    ]) {
      final value =
          _extractFirstNonEmptyString(_lookupCaseInsensitive(raw, key));
      if (value != null) return value;
    }
  }

  final fallback = fallbackName?.trim();
  if (fallback == null || fallback.isEmpty) return null;
  final normalizedFallback = fallback.toLowerCase();
  if (_storyMetadataKeys.contains(normalizedFallback) ||
      _storyContainerKeys.contains(normalizedFallback) ||
      _storyOptionCollectionKeys.contains(normalizedFallback)) {
    return null;
  }
  return fallback;
}

List<String> _extractPromptOptions(Object? raw) {
  if (raw is List) {
    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  if (raw is! Map) return const <String>[];

  for (final key in _storyOptionCollectionKeys) {
    final nested = _lookupCaseInsensitive(raw, key);
    if (nested is List) {
      final values = nested
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (values.isNotEmpty) return values;
    }
    if (nested is Map) {
      final values = _extractOrderedLeafValues(nested);
      if (values.isNotEmpty) return values;
    }
  }

  return _extractOrderedLeafValues(raw);
}

List<String> _extractOrderedLeafValues(Object? raw) {
  if (raw is List) {
    return raw
        .expand(_extractOrderedLeafValues)
        .where((value) => value.trim().isNotEmpty)
        .toList();
  }
  if (raw is! Map) {
    final normalized = raw?.toString().trim();
    return normalized == null || normalized.isEmpty
        ? const <String>[]
        : <String>[normalized];
  }

  final entries = raw.entries.toList()
    ..sort((left, right) => _comparePromptNodeKeys(left.key, right.key));
  final values = <String>[];
  for (final entry in entries) {
    final normalizedKey = entry.key.toString().toLowerCase();
    if (_storyMetadataKeys.contains(normalizedKey)) continue;
    values.addAll(_extractOrderedLeafValues(entry.value));
  }

  return values;
}

String? _extractFirstNonEmptyString(Object? raw) {
  if (raw is String) {
    final normalized = raw.trim();
    return normalized.isEmpty ? null : normalized;
  }
  if (raw is! Map) return null;

  for (final key in const ['text', 'value', 'label', 'prompt']) {
    final nested = _lookupCaseInsensitive(raw, key);
    if (nested is! String) continue;
    final normalized = nested.trim();
    if (normalized.isNotEmpty) return normalized;
  }

  return null;
}

Object? _lookupCaseInsensitive(Map raw, String key) {
  for (final entry in raw.entries.cast<MapEntry<Object?, Object?>>()) {
    if (entry.key.toString().toLowerCase() == key.toLowerCase()) {
      return entry.value;
    }
  }
  return null;
}

int _stableSeedFromString(String value) {
  var hash = 0x811C9DC5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash & 0x7fffffff;
}

Alignment _storyGlowAlignmentForSeed(String seed) {
  final random = Random(_stableSeedFromString('$seed-align'));
  return Alignment(
    -1 + (random.nextDouble() * 2),
    -1 + (random.nextDouble() * 2),
  );
}

Color _storyToneColorForSeed(String seed) {
  final random = Random(_stableSeedFromString('$seed-tone'));
  return HSLColor.fromAHSL(1, random.nextDouble() * 360, 0.38, 0.48).toColor();
}

double _storyCardRotationForSeed(String seed) {
  final random = Random(_stableSeedFromString('$seed-rotation'));
  return (random.nextDouble() - 0.5) * 0.08;
}

int _comparePromptNodeKeys(Object? left, Object? right) {
  final leftRaw = left.toString();
  final rightRaw = right.toString();
  final leftNumeric = int.tryParse(leftRaw);
  final rightNumeric = int.tryParse(rightRaw);

  if (leftNumeric != null && rightNumeric != null) {
    return leftNumeric.compareTo(rightNumeric);
  }
  if (leftNumeric != null) return -1;
  if (rightNumeric != null) return 1;
  return leftRaw.compareTo(rightRaw);
}

abstract class StoryPromptCatalogService {
  Future<StoryPromptDeck> loadStoryDeck();
}

class DatabaseStoryPromptCatalogService implements StoryPromptCatalogService {
  DatabaseStoryPromptCatalogService({
    RtdbService? rtdbService,
    this.path = _storyPromptPath,
  }) : _rtdbService = rtdbService ?? RtdbService();

  final RtdbService _rtdbService;
  final String path;

  @override
  Future<StoryPromptDeck> loadStoryDeck() async {
    final raw = await _rtdbService.fetchValue(path);
    return parseStoryPromptDeck(raw);
  }
}

class StoryPromptCardDealer {
  StoryPromptCardDealer({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  StoryPromptCardData dealPromptCard(
    List<StoryPromptType> types, {
    required int playerIndex,
    int typeCount = 3,
    int optionCount = 3,
    String? playerPrompt,
    String? seed,
  }) {
    final eligibleTypes = _eligibleTypes(types, optionCount);
    if (eligibleTypes.length < typeCount) {
      throw StateError(
        'Need at least $typeCount prompt types with $optionCount options each.',
      );
    }

    final random = seed == null ? _random : Random(_stableSeedFromString(seed));
    final selectedTypes = _pickUniqueItems(
      eligibleTypes,
      typeCount,
      random: random,
    );
    return StoryPromptCardData(
      playerIndex: playerIndex,
      playerPrompt: playerPrompt,
      choices: [
        for (final type in selectedTypes)
          StoryPromptChoice(
            category: type.category,
            options: _pickUniqueItems(
              type.options,
              optionCount,
              random: seed == null
                  ? _random
                  : Random(
                      _stableSeedFromString(
                        '$seed-${type.category}-$playerIndex-options',
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  Map<String, StoryPromptCardData> dealPromptCardsForPlayers(
    List<StoryPromptType> types, {
    required List<String> playerIds,
    required String seed,
    String? playerPrompt,
    int typeCount = 3,
    int optionCount = 3,
  }) {
    final uniquePlayerIds = playerIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (uniquePlayerIds.isEmpty) {
      return const <String, StoryPromptCardData>{};
    }

    final eligibleTypes = _eligibleTypes(types, optionCount);
    if (eligibleTypes.length < typeCount) {
      throw StateError(
        'Need at least $typeCount prompt categories with '
        '$optionCount items each to deal a story card.',
      );
    }

    final requiredUniqueTypeCount = uniquePlayerIds.length * typeCount;
    if (eligibleTypes.length < requiredUniqueTypeCount) {
      return {
        for (var index = 0; index < uniquePlayerIds.length; index += 1)
          uniquePlayerIds[index]: dealPromptCard(
            eligibleTypes,
            playerIndex: index,
            typeCount: typeCount,
            optionCount: optionCount,
            playerPrompt: playerPrompt,
            seed: '$seed-${uniquePlayerIds[index]}',
          ),
      };
    }

    final shuffledTypes = List<StoryPromptType>.from(eligibleTypes)
      ..shuffle(Random(_stableSeedFromString('$seed-categories')));
    final cards = <String, StoryPromptCardData>{};

    for (var index = 0; index < uniquePlayerIds.length; index += 1) {
      final playerId = uniquePlayerIds[index];
      final assignedTypes =
          shuffledTypes.skip(index * typeCount).take(typeCount).toList();
      cards[playerId] = StoryPromptCardData(
        playerIndex: index,
        playerPrompt: playerPrompt,
        choices: [
          for (final type in assignedTypes)
            StoryPromptChoice(
              category: type.category,
              options: _pickUniqueItems(
                type.options,
                optionCount,
                random: Random(
                  _stableSeedFromString('$seed-$playerId-${type.category}'),
                ),
              ),
            ),
        ],
      );
    }

    return cards;
  }

  List<StoryPromptType> _eligibleTypes(
    List<StoryPromptType> types,
    int optionCount,
  ) {
    return types.where((type) => type.options.length >= optionCount).toList();
  }

  List<T> _pickUniqueItems<T>(
    List<T> source,
    int count, {
    required Random random,
  }) {
    final shuffled = List<T>.from(source)..shuffle(random);
    return shuffled.take(count).toList();
  }
}

abstract class StoryPromptCompletionService {
  Future<String> generateStory(StoryPromptSubmission submission);
}

class UnsupportedStoryPromptCompletionService
    implements StoryPromptCompletionService {
  @override
  Future<String> generateStory(StoryPromptSubmission submission) {
    throw StateError(
      'This demo no longer calls OpenAI from the browser. Use the paired story flow, which writes the pair prompt to RTDB and waits for story.',
    );
  }
}

class StoryPromptDemoPage extends StatefulWidget {
  StoryPromptDemoPage({
    super.key,
    StoryPromptCatalogService? promptCatalogService,
    StoryPromptCompletionService? completionService,
    StoryPromptCardDealer? cardDealer,
  })  : promptCatalogService =
            promptCatalogService ?? DatabaseStoryPromptCatalogService(),
        completionService =
            completionService ?? UnsupportedStoryPromptCompletionService(),
        cardDealer = cardDealer ?? StoryPromptCardDealer();

  final StoryPromptCatalogService promptCatalogService;
  final StoryPromptCompletionService completionService;
  final StoryPromptCardDealer cardDealer;

  @override
  State<StoryPromptDemoPage> createState() => _StoryPromptDemoPageState();
}

class _StoryPromptDemoPageState extends State<StoryPromptDemoPage> {
  final _playerOneController = TextEditingController();
  final _playerTwoController = TextEditingController();
  final _nameFormKey = GlobalKey<FormState>();

  StoryPromptDeck? _loadedDeck;
  List<StoryPromptCardData>? _playerCards;
  bool _isLoadingCards = false;
  bool _isGenerating = false;
  String? _loadError;
  String? _resultError;
  String? _generatedStory;
  int _dealSeed = 0;

  @override
  void dispose() {
    _playerOneController.dispose();
    _playerTwoController.dispose();
    super.dispose();
  }

  String get _playerOneName => _playerOneController.text.trim();
  String get _playerTwoName => _playerTwoController.text.trim();

  bool get _canGenerate {
    final cards = _playerCards;
    return !_isGenerating &&
        cards != null &&
        cards.length == 2 &&
        cards.every((card) => card.isComplete);
  }

  Future<void> _dealPromptCards() async {
    final formState = _nameFormKey.currentState;
    if (formState == null || !formState.validate()) return;

    setState(() {
      _isLoadingCards = true;
      _loadError = null;
      _resultError = null;
      _generatedStory = null;
    });

    try {
      final deck =
          _loadedDeck ?? await widget.promptCatalogService.loadStoryDeck();
      final dealtCards = widget.cardDealer.dealPromptCardsForPlayers(
        deck.categories,
        playerIds: const ['player-1', 'player-2'],
        seed: 'demo-deal-${_dealSeed++}',
        playerPrompt: deck.playerPrompt,
      );
      final playerOneCard = dealtCards['player-1'];
      final playerTwoCard = dealtCards['player-2'];
      if (playerOneCard == null || playerTwoCard == null) {
        throw StateError('Failed to deal cards for both players.');
      }

      if (!mounted) return;
      setState(() {
        _loadedDeck = deck;
        _playerCards = [playerOneCard, playerTwoCard];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingCards = false;
      });
    }
  }

  Future<void> _generateStory() async {
    final cards = _playerCards;
    if (cards == null || cards.length != 2 || !_canGenerate) return;

    final submission = StoryPromptSubmission(
      playerOneName: _playerOneName,
      playerTwoName: _playerTwoName,
      playerOneAnswers: _toAnswers(cards[0]),
      playerTwoAnswers: _toAnswers(cards[1]),
    );

    setState(() {
      _isGenerating = true;
      _resultError = null;
      _generatedStory = null;
    });

    try {
      final result = await widget.completionService.generateStory(submission);
      if (!mounted) return;
      setState(() {
        _generatedStory = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resultError = error.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
      });
    }
  }

  List<StoryPromptAnswer> _toAnswers(StoryPromptCardData card) {
    return [
      for (final choice in card.choices)
        StoryPromptAnswer(
          typeName: choice.typeName,
          answer: choice.selectedOption ?? '',
        ),
    ];
  }

  void _selectAnswer({
    required int cardIndex,
    required int choiceIndex,
    required String option,
  }) {
    final cards = _playerCards;
    if (cards == null) return;

    setState(() {
      _playerCards = [
        for (var index = 0; index < cards.length; index += 1)
          if (index == cardIndex)
            cards[index].updateSelection(
              choiceIndex: choiceIndex,
              selectedOption: option,
            )
          else
            cards[index],
      ];
      _resultError = null;
      _generatedStory = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cards = _playerCards;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF4ECDE),
              Color(0xFFE8DED2),
              Color(0xFFD9D3D8),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DemoHero(
                      titleStyle: theme.textTheme.displaySmall,
                      bodyStyle: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    _DemoPanel(
                      child: Form(
                        key: _nameFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enter both names, then deal three category cards for each player from Story.',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: _demoInk,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 760;
                                if (stacked) {
                                  return Column(
                                    children: [
                                      _NameField(
                                        controller: _playerOneController,
                                        label: 'Player 1 name',
                                      ),
                                      const SizedBox(height: 12),
                                      _NameField(
                                        controller: _playerTwoController,
                                        label: 'Player 2 name',
                                      ),
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    Expanded(
                                      child: _NameField(
                                        controller: _playerOneController,
                                        label: 'Player 1 name',
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: _NameField(
                                        controller: _playerTwoController,
                                        label: 'Player 2 name',
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilledButton(
                                  onPressed:
                                      _isLoadingCards ? null : _dealPromptCards,
                                  child: Text(
                                    _isLoadingCards
                                        ? 'Loading cards...'
                                        : cards == null
                                            ? 'Deal category cards'
                                            : 'Deal new cards',
                                  ),
                                ),
                                Text(
                                  'Source: $_storyPromptPath/Story',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: _demoMutedInk,
                                  ),
                                ),
                              ],
                            ),
                            if (_loadError != null) ...[
                              const SizedBox(height: 14),
                              _InlineError(message: _loadError!),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (cards != null) ...[
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stacked = constraints.maxWidth < 980;
                          if (stacked) {
                            return Column(
                              children: [
                                StoryPlayerPromptCard(
                                  title: _playerOneName,
                                  subtitle: 'Player 1',
                                  card: cards[0],
                                  onSelect: (choiceIndex, option) =>
                                      _selectAnswer(
                                    cardIndex: 0,
                                    choiceIndex: choiceIndex,
                                    option: option,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                StoryPlayerPromptCard(
                                  title: _playerTwoName,
                                  subtitle: 'Player 2',
                                  card: cards[1],
                                  onSelect: (choiceIndex, option) =>
                                      _selectAnswer(
                                    cardIndex: 1,
                                    choiceIndex: choiceIndex,
                                    option: option,
                                  ),
                                ),
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: StoryPlayerPromptCard(
                                  title: _playerOneName,
                                  subtitle: 'Player 1',
                                  card: cards[0],
                                  onSelect: (choiceIndex, option) =>
                                      _selectAnswer(
                                    cardIndex: 0,
                                    choiceIndex: choiceIndex,
                                    option: option,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: StoryPlayerPromptCard(
                                  title: _playerTwoName,
                                  subtitle: 'Player 2',
                                  card: cards[1],
                                  onSelect: (choiceIndex, option) =>
                                      _selectAnswer(
                                    cardIndex: 1,
                                    choiceIndex: choiceIndex,
                                    option: option,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: _canGenerate ? _generateStory : null,
                          child: Text(
                            _isGenerating
                                ? 'Waiting for OpenAI...'
                                : 'Generate result',
                          ),
                        ),
                      ),
                    ],
                    if (_resultError != null) ...[
                      const SizedBox(height: 16),
                      _InlineError(message: _resultError!),
                    ],
                    if (_generatedStory != null) ...[
                      const SizedBox(height: 20),
                      _DemoPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Returned result',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: _demoInk,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SelectableText(
                              _generatedStory!,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: _demoInk,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'Demo note: the production path writes the pair prompt to RTDB and waits for story on that pair record.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _demoMutedInk,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StoryPairSessionPage extends StatelessWidget {
  StoryPairSessionPage({
    super.key,
    required this.sessionId,
    required this.player,
    required this.partnerId,
    required this.sessionRound,
    StoryPromptCatalogService? promptCatalogService,
    StoryPromptCardDealer? cardDealer,
    RtdbService? rtdbService,
  })  : promptCatalogService =
            promptCatalogService ?? DatabaseStoryPromptCatalogService(),
        cardDealer = cardDealer ?? StoryPromptCardDealer(),
        rtdbService = rtdbService ?? RtdbService();

  final String sessionId;
  final PlayerRecord player;
  final String partnerId;
  final int sessionRound;
  final StoryPromptCatalogService promptCatalogService;
  final StoryPromptCardDealer cardDealer;
  final RtdbService rtdbService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _demoInk,
        title: const Text('Story Cards'),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF4ECDE),
              Color(0xFFE8DED2),
              Color(0xFFD9D3D8),
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: StoryPairPromptPanel(
                  sessionId: sessionId,
                  player: player,
                  partnerId: partnerId,
                  sessionRound: sessionRound,
                  promptCatalogService: promptCatalogService,
                  cardDealer: cardDealer,
                  rtdbService: rtdbService,
                  showMetadataPanel: true,
                  showPairId: true,
                  showNameField: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StoryPairPromptPanel extends StatefulWidget {
  StoryPairPromptPanel({
    super.key,
    required this.sessionId,
    required this.player,
    required this.partnerId,
    required this.sessionRound,
    StoryPromptCatalogService? promptCatalogService,
    StoryPromptCardDealer? cardDealer,
    RtdbService? rtdbService,
    this.showMetadataPanel = false,
    this.showPairId = false,
    this.showNameField = false,
    this.promptCardSubtitle = 'Your category cards',
  })  : promptCatalogService =
            promptCatalogService ?? DatabaseStoryPromptCatalogService(),
        cardDealer = cardDealer ?? StoryPromptCardDealer(),
        rtdbService = rtdbService ?? RtdbService();

  final String sessionId;
  final PlayerRecord player;
  final String partnerId;
  final int sessionRound;
  final StoryPromptCatalogService promptCatalogService;
  final StoryPromptCardDealer cardDealer;
  final RtdbService rtdbService;
  final bool showMetadataPanel;
  final bool showPairId;
  final bool showNameField;
  final String promptCardSubtitle;

  @override
  State<StoryPairPromptPanel> createState() => _StoryPairPromptPanelState();
}

class _StoryPairPromptPanelState extends State<StoryPairPromptPanel> {
  late final TextEditingController _nameController;
  StoryPromptCardData? _card;
  StoryPairResultRecord? _result;
  bool _loading = true;
  bool _submitting = false;
  bool _hasSubmittedSelections = false;
  String? _error;
  Timer? _poller;

  String get _pairId => buildStoryPairId(
        sessionId: widget.sessionId,
        playerId: widget.player.id,
        partnerId: widget.partnerId,
        pairRound: _pairRound,
      );

  int get _pairRound => widget.player.pairedRound ?? widget.sessionRound;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.player.name);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _poller?.cancel();
    super.dispose();
  }

  String get _playerName {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) return name;
    final fallback = widget.player.name.trim();
    return fallback.isNotEmpty ? fallback : 'Player';
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final existingPlayer = await widget.rtdbService.fetchStoryPairPlayer(
        pairId: _pairId,
        playerId: widget.player.id,
      );
      final existingResult =
          await widget.rtdbService.fetchStoryPairResult(_pairId);
      StoryPromptDeck? deck;
      try {
        deck = await widget.promptCatalogService.loadStoryDeck();
      } catch (_) {
        if (existingPlayer == null || existingPlayer.choices.length != 3) {
          rethrow;
        }
      }

      StoryPromptCardData card;
      if (existingPlayer != null && existingPlayer.choices.length == 3) {
        card = StoryPromptCardData.fromRecords(
          playerIndex: 0,
          records: existingPlayer.choices,
          playerPrompt: deck?.playerPrompt,
        );
      } else {
        if (deck == null) {
          throw StateError('Story prompt deck is unavailable.');
        }
        final dealtCards = widget.cardDealer.dealPromptCardsForPlayers(
          deck.categories,
          playerIds: [widget.player.id, widget.partnerId],
          seed: _pairId,
          playerPrompt: deck.playerPrompt,
        );
        final dealtCard = dealtCards[widget.player.id];
        if (dealtCard == null) {
          throw StateError('Failed to deal a story card for this player.');
        }
        card = dealtCard;
        await _savePlayerCard(card);
      }

      if (!mounted) return;
      setState(() {
        _card = card;
        _result = existingResult;
        _hasSubmittedSelections = existingPlayer?.isComplete ?? false;
      });

      if (_hasSubmittedSelections && !_hasTerminalResult(existingResult)) {
        _startPolling();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  bool _hasTerminalResult(StoryPairResultRecord? result) {
    return result?.isComplete == true || result?.isError == true;
  }

  Future<void> _savePlayerCard(
    StoryPromptCardData card, {
    int? completedAt,
  }) {
    return widget.rtdbService.saveStoryPairPlayer(
      pairId: _pairId,
      player: StoryPairPlayerRecord(
        playerId: widget.player.id,
        name: _playerName,
        sessionId: widget.sessionId,
        partnerId: widget.partnerId,
        pairRound: _pairRound,
        choices: card.toRecords(),
        completedAt: completedAt,
      ),
    );
  }

  void _selectAnswer({
    required int choiceIndex,
    required String option,
  }) {
    if (_hasSubmittedSelections) return;

    final card = _card;
    if (card == null) return;

    setState(() {
      _card = card.updateSelection(
        choiceIndex: choiceIndex,
        selectedOption: option,
      );
      _error = null;
      if (_result?.isComplete != true) {
        _result = null;
      }
    });
  }

  Future<void> _submitSelections() async {
    final card = _card;
    if (card == null || !card.isComplete) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _savePlayerCard(
        card,
        completedAt: DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) return;
      setState(() {
        _hasSubmittedSelections = true;
      });

      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
    }
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_pollResult());
    });
  }

  Future<void> _pollResult() async {
    try {
      final result = await widget.rtdbService.fetchStoryPairResult(_pairId);
      if (!mounted) return;

      if (result != null) {
        setState(() {
          _result = result;
        });
        if (_hasTerminalResult(result)) {
          _poller?.cancel();
          return;
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = _card;
    final result = _result;
    final showHeaderPanel =
        widget.showMetadataPanel || widget.showPairId || widget.showNameField;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeaderPanel) ...[
          _DemoPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showMetadataPanel)
                  Text(
                    'Pick 1 item from each category card. When both players submit, the app writes the two names and six choices on the pair, then waits for story.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: _demoInk,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                if (widget.showMetadataPanel && widget.showPairId)
                  const SizedBox(height: 10),
                if (widget.showPairId)
                  Text(
                    'Pair: $_pairId',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _demoMutedInk,
                    ),
                  ),
                if (widget.showNameField) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _nameController,
                    enabled: !_hasSubmittedSelections,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      hintText: 'Enter your name',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(),
            ),
          )
        else if (card != null)
          StoryPlayerPromptCard(
            title: _playerName,
            subtitle: widget.promptCardSubtitle,
            card: card,
            enabled: !_hasSubmittedSelections,
            onSelect: (choiceIndex, option) => _selectAnswer(
              choiceIndex: choiceIndex,
              option: option,
            ),
          ),
        if (card != null) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed:
                  _hasSubmittedSelections || _submitting || !card.isComplete
                      ? null
                      : _submitSelections,
              child: Text(
                _submitting
                    ? 'Submitting...'
                    : _hasSubmittedSelections
                        ? 'Submitted'
                        : 'Submit your 3 answers',
              ),
            ),
          ),
        ],
        if (_hasSubmittedSelections && !_hasTerminalResult(result)) ...[
          const SizedBox(height: 14),
          _DemoPanel(
            child: Text(
              result?.isProcessing == true
                  ? 'Your story is being generated now.'
                  : 'Your answers are saved. Waiting for the other player and for story to appear on the pair record.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: _demoInk,
                height: 1.4,
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          _InlineError(message: _error!),
        ],
        if (result?.isError == true && result?.error != null) ...[
          const SizedBox(height: 16),
          _InlineError(message: result!.error!),
        ],
        if (result?.isComplete == true &&
            (result?.text ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 20),
          _DemoPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Generated result',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: _demoInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  result!.text!,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: _demoInk,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DemoHero extends StatelessWidget {
  const _DemoHero({
    required this.titleStyle,
    required this.bodyStyle,
  });

  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _demoPanel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _demoBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _demoAccentSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _demoBorder),
              ),
              child: Text(
                'Two-player story demo',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: _demoAccent,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Pull Story categories from Firebase, show them as polaroid cards, then send both players’ picks into the paired story flow.',
              style: titleStyle?.copyWith(
                color: _demoInk,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Each player gets 3 category cards. When Firebase has enough categories the two hands avoid overlap, and when it does not the app still deals valid cards instead of failing.',
              style: bodyStyle?.copyWith(
                color: _demoMutedInk,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoPanel extends StatelessWidget {
  const _DemoPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _demoPanel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _demoBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textInputAction: TextInputAction.next,
      validator: (value) {
        if ((value ?? '').trim().isEmpty) {
          return 'Enter a name';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Enter name',
      ),
    );
  }
}

class StoryPlayerPromptCard extends StatelessWidget {
  const StoryPlayerPromptCard({
    required this.title,
    required this.subtitle,
    required this.card,
    required this.onSelect,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final StoryPromptCardData card;
  final void Function(int choiceIndex, String option) onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final promptCopy = (card.playerPrompt ?? '').trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _demoCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _demoBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              style: theme.textTheme.labelLarge?.copyWith(
                color: _demoAccent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: _demoInk,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (promptCopy.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                promptCopy,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: _demoInk,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Choose 1 item from each category card.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _demoMutedInk,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = _categoryCardWidthFor(constraints.maxWidth);
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (var index = 0; index < card.choices.length; index += 1)
                      SizedBox(
                        width: cardWidth,
                        child: _PromptChoiceSection(
                          choice: card.choices[index],
                          enabled: enabled,
                          seed:
                              '${card.playerIndex}-${card.choices[index].category}-$index',
                          onSelect: (option) => onSelect(index, option),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

double _categoryCardWidthFor(double maxWidth) {
  if (maxWidth >= 980) {
    return max(220, (maxWidth - 28) / 3);
  }
  if (maxWidth >= 640) {
    return max(220, (maxWidth - 14) / 2);
  }
  return maxWidth;
}

class _PromptChoiceSection extends StatelessWidget {
  const _PromptChoiceSection({
    required this.choice,
    required this.onSelect,
    required this.seed,
    this.enabled = true,
  });

  final StoryPromptChoice choice;
  final ValueChanged<String> onSelect;
  final String seed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toneColor = _storyToneColorForSeed(seed);
    final toneHsl = HSLColor.fromColor(toneColor);
    final accentColor = toneHsl
        .withSaturation(min(toneHsl.saturation + 0.16, 1.0))
        .withLightness(min(toneHsl.lightness + 0.12, 1.0))
        .toColor();
    final glowAlignment = _storyGlowAlignmentForSeed(seed);
    final sweepAlignment = _storyGlowAlignmentForSeed('$seed-sweep');
    return Transform.rotate(
      angle: _storyCardRotationForSeed(seed),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1E000000),
              blurRadius: 20,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 0.92,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.alphaBlend(
                                toneColor.withValues(alpha: 0.72),
                                const Color(0xFF16120F),
                              ),
                              Color.alphaBlend(
                                accentColor.withValues(alpha: 0.30),
                                const Color(0xFF342A21),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: glowAlignment,
                            radius: 1.0,
                            colors: [
                              accentColor.withValues(alpha: 0.34),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: sweepAlignment,
                            end:
                                Alignment(-sweepAlignment.x, -sweepAlignment.y),
                            colors: [
                              Colors.white.withValues(alpha: 0.16),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.22),
                            ],
                            stops: const [0, 0.44, 1],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.alphaBlend(
                                toneColor.withValues(alpha: 0.18),
                                Colors.black.withValues(alpha: 0.26),
                              ),
                              Color.alphaBlend(
                                toneColor.withValues(alpha: 0.46),
                                Colors.black.withValues(alpha: 0.64),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.34),
                                ),
                              ),
                              child: Text(
                                'Category',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              choice.category,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x8A000000),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Pick 1',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'YouMe',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'cursive',
                  fontStyle: FontStyle.italic,
                  color: _demoInk,
                ),
              ),
              const SizedBox(height: 12),
              for (var index = 0;
                  index < choice.options.length;
                  index += 1) ...[
                _PromptOptionButton(
                  option: choice.options[index],
                  selected: choice.selectedOption == choice.options[index],
                  enabled: enabled,
                  onTap: enabled ? () => onSelect(choice.options[index]) : null,
                ),
                if (index < choice.options.length - 1)
                  const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptOptionButton extends StatelessWidget {
  const _PromptOptionButton({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String option;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.82,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? _demoAccentSoft : _demoBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _demoAccent : _demoBorder,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _demoInk,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? _demoAccent : _demoMutedInk,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFEFE6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0AB92)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF7A2F1A),
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
