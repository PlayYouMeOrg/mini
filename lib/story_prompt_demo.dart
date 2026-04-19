import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'session_domain.dart';

const _demoPanel = Color(0xFFF8F2E8);
const _demoCard = Color(0xFFFFFCF6);
const _demoBorder = Color(0xFFD4C2A9);
const _demoInk = Color(0xFF1D1A16);
const _demoMutedInk = Color(0xFF685E54);
const _demoAccent = Color(0xFFB85432);
const _demoAccentSoft = Color(0xFFF6E0D4);
const _storyTextureAssets = <String>[
  'assets/Polaroid1.png',
  'assets/Polaroid2.png',
  'assets/Polaroid3.png',
  'assets/Polaroid4.png',
];
const _storyPromptCardWidth = 248.0;
const _storyPromptCardHeight = 322.0;
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

double _storyCardRotationForSeed(String seed) {
  final random = Random(_stableSeedFromString('$seed-rotation'));
  return (random.nextDouble() - 0.5) * 0.08;
}

String _storyTextureAssetForSeed(String seed) {
  final random = Random(_stableSeedFromString('$seed-texture-asset'));
  return _storyTextureAssets[random.nextInt(_storyTextureAssets.length)];
}

int? _storyTargetTextureDecodeWidth({
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
    this.onStoryComplete,
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
  final VoidCallback? onStoryComplete;

  @override
  Widget build(BuildContext context) {
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
                  onStoryComplete: onStoryComplete,
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
    this.completedFooter,
    this.onStoryComplete,
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
  final Widget? completedFooter;
  final VoidCallback? onStoryComplete;

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
  bool _hasNotifiedStoryComplete = false;
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
      _notifyStoryCompleteIfNeeded(existingResult);

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
    return result?.hasText == true || result?.isError == true;
  }

  void _notifyStoryCompleteIfNeeded(StoryPairResultRecord? result) {
    if (_hasNotifiedStoryComplete || result?.hasText != true) {
      return;
    }
    _hasNotifiedStoryComplete = true;
    widget.onStoryComplete?.call();
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
    if (_hasSubmittedSelections || _submitting) return;

    final card = _card;
    if (card == null) return;

    final updatedCard = card.updateSelection(
      choiceIndex: choiceIndex,
      selectedOption: option,
    );

    setState(() {
      _card = updatedCard;
      _error = null;
      if (_result?.isComplete != true) {
        _result = null;
      }
    });

    if (updatedCard.isComplete) {
      unawaited(_submitSelections(card: updatedCard));
    }
  }

  int _visibleChoiceIndexFor(StoryPromptCardData card) {
    final nextIncomplete = card.choices.indexWhere(
      (choice) => (choice.selectedOption ?? '').trim().isEmpty,
    );
    if (nextIncomplete >= 0) return nextIncomplete;
    return max(0, card.choices.length - 1);
  }

  Future<void> _submitSelections({StoryPromptCardData? card}) async {
    final resolvedCard = card ?? _card;
    if (_submitting || resolvedCard == null || !resolvedCard.isComplete) {
      return;
    }

    setState(() {
      _card = resolvedCard;
      _hasSubmittedSelections = true;
      _submitting = true;
      _error = null;
    });

    try {
      await _savePlayerCard(
        resolvedCard,
        completedAt: DateTime.now().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hasSubmittedSelections = false;
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
        _notifyStoryCompleteIfNeeded(result);
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
    final hasDisplayableStory = result?.hasText == true;
    final shouldShowPromptCard = !_hasSubmittedSelections && card != null;
    final shouldShowWaitingState =
        _hasSubmittedSelections && !_hasTerminalResult(result);
    final visibleChoiceIndex = card == null ? 0 : _visibleChoiceIndexFor(card);

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
        else if (shouldShowPromptCard)
          StoryPlayerPromptCard(
            title: _playerName,
            subtitle: widget.promptCardSubtitle,
            card: card,
            enabled: !_hasSubmittedSelections && !_submitting,
            showTitle: false,
            showSubtitle: false,
            showPromptCopy: false,
            showInstruction: false,
            visibleChoiceIndex: visibleChoiceIndex,
            onSelect: (choiceIndex, option) => _selectAnswer(
              choiceIndex: choiceIndex,
              option: option,
            ),
          ),
        if (shouldShowWaitingState) ...[
          const SizedBox(height: 14),
          _DemoPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Writing your story',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: _demoInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _submitting
                      ? 'Saving your answers and opening the waiting step.'
                      : result?.isProcessing == true
                          ? 'Your story is being generated now.'
                          : result?.isComplete == true
                              ? 'Your story is almost ready.'
                              : 'Your answers are saved. Waiting for the other player.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: _demoInk,
                    height: 1.4,
                  ),
                ),
              ],
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
        if (hasDisplayableStory) ...[
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
          if (widget.completedFooter != null) ...[
            const SizedBox(height: 16),
            widget.completedFooter!,
          ],
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
    this.showTitle = true,
    this.showSubtitle = true,
    this.showPromptCopy = true,
    this.showInstruction = true,
    this.visibleChoiceIndex,
  });

  final String title;
  final String subtitle;
  final StoryPromptCardData card;
  final void Function(int choiceIndex, String option) onSelect;
  final bool enabled;
  final bool showTitle;
  final bool showSubtitle;
  final bool showPromptCopy;
  final bool showInstruction;
  final int? visibleChoiceIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final promptCopy = (card.playerPrompt ?? '').trim();
    final hasHeader = (showSubtitle && subtitle.trim().isNotEmpty) ||
        (showTitle && title.trim().isNotEmpty) ||
        (showPromptCopy && promptCopy.isNotEmpty) ||
        showInstruction;
    final visibleChoiceEntries = <MapEntry<int, StoryPromptChoice>>[
      for (var index = 0; index < card.choices.length; index += 1)
        if (visibleChoiceIndex == null || index == visibleChoiceIndex)
          MapEntry(index, card.choices[index]),
    ];
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
            if (showSubtitle && subtitle.trim().isNotEmpty)
              Text(
                subtitle,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: _demoAccent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            if (showSubtitle &&
                subtitle.trim().isNotEmpty &&
                showTitle &&
                title.trim().isNotEmpty)
              const SizedBox(height: 6),
            if (showTitle && title.trim().isNotEmpty)
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: _demoInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
            if (showPromptCopy && promptCopy.isNotEmpty) ...[
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
            if (showInstruction) ...[
              const SizedBox(height: 16),
              Text(
                'Choose 1 item from each category card.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _demoMutedInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (hasHeader) const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = _categoryCardWidthFor(constraints.maxWidth);
                if (visibleChoiceIndex != null &&
                    visibleChoiceEntries.isNotEmpty) {
                  final entry = visibleChoiceEntries.single;
                  return Center(
                    child: SizedBox(
                      width: min(cardWidth, _storyPromptCardWidth),
                      child: _PromptChoiceSection(
                        choice: entry.value,
                        enabled: enabled,
                        seed:
                            '${card.playerIndex}-${entry.value.category}-${entry.key}',
                        rotationAngle: 0,
                        onSelect: (option) => onSelect(entry.key, option),
                      ),
                    ),
                  );
                }

                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final entry in visibleChoiceEntries)
                      SizedBox(
                        width: cardWidth,
                        child: _PromptChoiceSection(
                          choice: entry.value,
                          enabled: enabled,
                          seed:
                              '${card.playerIndex}-${entry.value.category}-${entry.key}',
                          onSelect: (option) => onSelect(entry.key, option),
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
    this.rotationAngle,
  });

  final StoryPromptChoice choice;
  final ValueChanged<String> onSelect;
  final String seed;
  final bool enabled;
  final double? rotationAngle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedAngle = rotationAngle ?? _storyCardRotationForSeed(seed);
    return Transform.rotate(
      angle: resolvedAngle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _demoCard,
          borderRadius: BorderRadius.circular(9),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: AspectRatio(
                  aspectRatio: _storyPromptCardWidth / _storyPromptCardHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _StoryTextureBackdrop(seed: seed),
                      const DecoratedBox(
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
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              choice.category,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
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
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: SingleChildScrollView(
                                  primary: false,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.16,
                                        ),
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x26000000),
                                          blurRadius: 16,
                                          offset: Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        8,
                                        8,
                                        8,
                                      ),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          return Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              for (final option
                                                  in choice.options)
                                                ConstrainedBox(
                                                  constraints: BoxConstraints(
                                                    maxWidth:
                                                        constraints.maxWidth,
                                                  ),
                                                  child: _PromptOptionButton(
                                                    option: option,
                                                    selected:
                                                        choice.selectedOption ==
                                                            option,
                                                    enabled: enabled,
                                                    onTap: enabled
                                                        ? () => onSelect(
                                                              option,
                                                            )
                                                        : null,
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryTextureBackdrop extends StatelessWidget {
  const _StoryTextureBackdrop({required this.seed});

  final String seed;

  @override
  Widget build(BuildContext context) {
    final random = Random(_stableSeedFromString('$seed-texture-layout'));
    final resolvedTextureAsset = _storyTextureAssetForSeed(seed);
    final alignment = Alignment(
      -1 + (random.nextDouble() * 2),
      -1 + (random.nextDouble() * 2),
    );
    final rotation = (random.nextDouble() * 2 - 1) * (pi / 24);
    final scale = 1 + (random.nextDouble() * 0.2);
    final blurSigma = 1.4 + (random.nextDouble() * 1.4);

    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ??
            View.of(context).devicePixelRatio;
        final targetDecodeWidth = _storyTargetTextureDecodeWidth(
          constraints: constraints,
          devicePixelRatio: devicePixelRatio,
          scale: scale,
        );
        return ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
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
        );
      },
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
      opacity: enabled ? 1 : 0.84,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.94)
                  : Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? _demoAccent
                    : Colors.white.withValues(alpha: 0.24),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? _demoAccent : Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    option,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? _demoInk : Colors.white,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      height: 1.15,
                    ),
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
