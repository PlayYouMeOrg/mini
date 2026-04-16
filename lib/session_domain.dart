import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _databaseBaseUrl = 'https://youmedev-feab4-default-rtdb.firebaseio.com';
const _firestoreProjectId = 'youmedev-feab4';
const _promptCatalogPath = 'mini/prompts';

Future<String?> _firebaseIdToken() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  } catch (_) {
    return null;
  }
}

Future<Map<String, String>> _authorizedHeaders({
  bool includeJsonContentType = false,
}) async {
  final headers = <String, String>{};
  if (includeJsonContentType) {
    headers['Content-Type'] = 'application/json';
  }

  final token = await _firebaseIdToken();
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }

  return headers;
}

enum RoundPreference { openingUp, playful }

extension RoundPreferenceLabel on RoundPreference {
  String get label =>
      this == RoundPreference.openingUp ? 'Opening up' : 'Playful';
}

const storyModePromptId = '__story_mode__';
const storyModePromptItem = PromptItem(
  id: storyModePromptId,
  text: 'Story mode\nOpen the final card together to build your story.',
);

class SignupPayload {
  const SignupPayload({
    required this.name,
    required this.phone,
    required this.acceptedTermsAndGameTexts,
    required this.acceptedPromoTexts,
    required this.roundPreference,
  });

  final String name;
  final String phone;
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
    this.interactionRound = 1,
    this.continueVoteRound,
    this.currentPromptRound,
    this.currentPromptIndex = 0,
    this.activeTurnPlayerId,
    this.skipNextTurn = false,
    this.currentRoundPrompts = const <String>[],
    this.askedPromptIds = const <String>[],
    this.matchedPlayerIds = const <String>[],
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
  int interactionRound;
  int? continueVoteRound;
  int? currentPromptRound;
  int currentPromptIndex;
  String? activeTurnPlayerId;
  bool skipNextTurn;
  List<String> currentRoundPrompts;
  List<String> askedPromptIds;
  List<String> matchedPlayerIds;
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
      'interactionRound': interactionRound,
      'continueVoteRound': continueVoteRound,
      'currentPromptRound': currentPromptRound,
      'currentPromptIndex': currentPromptIndex,
      'activeTurnPlayerId': activeTurnPlayerId,
      'skipNextTurn': skipNextTurn,
      'currentRoundPrompts': currentRoundPrompts,
      'askedPromptIds': askedPromptIds,
      'matchedPlayerIds': matchedPlayerIds,
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
      roundPreference:
          _roundPreferenceFromString(json['roundPreference'] as String?),
      inviteCode: (json['inviteCode'] ?? '') as String,
      partnerCode: json['partnerCode'] as String?,
      pairedWith: json['pairedWith'] as String?,
      pairedRound: (json['pairedRound'] as num?)?.toInt(),
      interactionRound: (json['interactionRound'] as num?)?.toInt() ?? 1,
      continueVoteRound: (json['continueVoteRound'] as num?)?.toInt(),
      currentPromptRound: (json['currentPromptRound'] as num?)?.toInt(),
      currentPromptIndex: (json['currentPromptIndex'] as num?)?.toInt() ?? 0,
      activeTurnPlayerId:
          (json['activeTurnPlayerId'] as String?)?.trim().isEmpty ?? true
              ? null
              : json['activeTurnPlayerId'] as String?,
      skipNextTurn: (json['skipNextTurn'] ?? false) as bool,
      currentRoundPrompts: ((json['currentRoundPrompts'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      askedPromptIds: ((json['askedPromptIds'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      matchedPlayerIds: ((json['matchedPlayerIds'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((id) => id.isNotEmpty)
          .toList(),
      seeAgainPlayerIds: _parseSeeAgainIds(json),
    );
  }
}

List<String> _parseSeeAgainIds(Map<String, dynamic> json) {
  final raw = json['seeAgainPlayerIds'];
  if (raw is List) {
    return raw
        .map((item) => item.toString())
        .where((id) => id.isNotEmpty)
        .toList();
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
    final headers = await _authorizedHeaders(includeJsonContentType: true);
    final response = await http.patch(
      _uri('signups/${player.id}'),
      headers: headers,
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
          'createdAt': {
            'timestampValue': DateTime.now().toUtc().toIso8601String()
          },
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

  Future<Uri> _authorizedUri(String path) async {
    final uri = _uri(path);
    final token = await _firebaseIdToken();
    if (token == null || token.isEmpty) return uri;
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'auth': token,
      },
    );
  }

  Future<http.Response> _get(String path) async {
    final uri = await _authorizedUri(path);
    return http.get(uri, headers: await _authorizedHeaders());
  }

  Future<http.Response> _patch(String path, Map<String, dynamic> body) async {
    final uri = await _authorizedUri(path);
    return http.patch(
      uri,
      headers: await _authorizedHeaders(includeJsonContentType: true),
      body: jsonEncode(body),
    );
  }

  Future<Object?> fetchValue(String path) async {
    final resp = await _get(path);
    _throwIfNotOk(resp);
    return jsonDecode(resp.body);
  }

  Future<void> patchValue(String path, Map<String, dynamic> body) async {
    final resp = await _patch(path, body);
    _throwIfNotOk(resp);
  }

  String _sessionBasePath(String sessionId) => 'mini/sessions/$sessionId';

  Future<SessionRecord> fetchSession(String sessionId) async {
    final resp = await _get(_sessionBasePath(sessionId));
    _throwIfNotOk(resp);
    final payload = jsonDecode(resp.body);
    if (payload is! Map<String, dynamic>) {
      return SessionRecord(status: null, round: null);
    }
    return SessionRecord.fromJson(payload);
  }

  Future<void> ensureSessionOpen(String sessionId) async {
    final resp = await _patch(
      _sessionBasePath(sessionId),
      {
        'status': 'started',
        'round': 1,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );
    _throwIfNotOk(resp);
  }

  Future<SessionRecord> ensureSessionStarted(String sessionId) async {
    final existing = await fetchSession(sessionId);
    final normalizedStatus = existing.status?.trim().toLowerCase();
    if (normalizedStatus == 'started' && existing.round != null) {
      return existing;
    }

    final nextRound = existing.round ?? 1;
    final resp = await _patch(
      _sessionBasePath(sessionId),
      {
        'status': 'started',
        'round': nextRound,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );
    _throwIfNotOk(resp);

    return SessionRecord(status: 'started', round: nextRound);
  }

  Future<void> savePlayer(String sessionId, PlayerRecord player) async {
    final resp = await _patch(
      '${_sessionBasePath(sessionId)}/players/${player.id}',
      player.toJson(),
    );
    _throwIfNotOk(resp);
  }

  Future<Map<String, PlayerRecord>> fetchPlayers(String sessionId) async {
    final resp = await _get('${_sessionBasePath(sessionId)}/players');
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
    final resp = await _get('${_sessionBasePath(sessionId)}/players/$playerId');
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
    me.interactionRound = 1;
    me.continueVoteRound = null;
    me.activeTurnPlayerId = null;
    me.skipNextTurn = false;
    me.matchedPlayerIds = {
      ...me.matchedPlayerIds,
      partner.id,
    }.toList();

    partner.pairedWith = me.id;
    partner.pairedRound = round;
    partner.interactionRound = 1;
    partner.continueVoteRound = null;
    partner.activeTurnPlayerId = null;
    partner.skipNextTurn = false;
    partner.matchedPlayerIds = {
      ...partner.matchedPlayerIds,
      me.id,
    }.toList();

    await savePlayer(sessionId, me);
    await savePlayer(sessionId, partner);
  }

  Future<void> clearPairing(String sessionId, String playerId) async {
    final resp = await _patch(
      '${_sessionBasePath(sessionId)}/players/$playerId',
      {
        'pairedWith': null,
        'pairedRound': null,
        'partnerCode': null,
        'interactionRound': 1,
        'continueVoteRound': null,
        'activeTurnPlayerId': null,
        'skipNextTurn': false,
        'updatedAt': DateTime.now().toIso8601String(),
      },
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

    final resp = await _patch(
      '${_sessionBasePath(sessionId)}/players/$playerId',
      {
        'seeAgainPlayerIds': updated,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );
    _throwIfNotOk(resp);
  }

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
    final resp = await _patch(
      '${_sessionBasePath(sessionId)}/players/$playerId',
      {
        'interactionRound': interactionRound,
        'continueVoteRound': continueVoteRound,
        'currentPromptRound': round,
        'currentPromptIndex': 0,
        'activeTurnPlayerId': activeTurnPlayerId,
        'skipNextTurn': skipNextTurn,
        'currentRoundPrompts': promptEntries,
        'askedPromptIds': askedPromptIds,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );
    _throwIfNotOk(resp);
  }

  Future<void> setContinueVote({
    required String sessionId,
    required String playerId,
    required int continueVoteRound,
  }) async {
    final resp = await _patch(
      '${_sessionBasePath(sessionId)}/players/$playerId',
      {
        'continueVoteRound': continueVoteRound,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );
    _throwIfNotOk(resp);
  }

  Future<void> setSkipNextTurn({
    required String sessionId,
    required String playerId,
    required bool skipNextTurn,
  }) async {
    final resp = await _patch(
      '${_sessionBasePath(sessionId)}/players/$playerId',
      {
        'skipNextTurn': skipNextTurn,
        'updatedAt': DateTime.now().toIso8601String(),
      },
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

    final meResp = await _patch(
      '${_sessionBasePath(sessionId)}/players/${me.id}',
      update,
    );
    _throwIfNotOk(meResp);

    final partnerResp = await _patch(
      '${_sessionBasePath(sessionId)}/players/$partnerId',
      update,
    );
    _throwIfNotOk(partnerResp);
  }

  Future<StoryPairPlayerRecord?> fetchStoryPairPlayer({
    required String pairId,
    required String playerId,
  }) async {
    final payload =
        await fetchValue('mini/storyPairs/$pairId/players/$playerId');
    if (payload is! Map<String, dynamic>) return null;
    return StoryPairPlayerRecord.fromJson(payload);
  }

  Future<StoryPairResultRecord?> fetchStoryPairResult(String pairId) async {
    final payload = await fetchValue('mini/storyPairs/$pairId');
    if (payload is! Map<String, dynamic>) return null;

    final story = _extractStoryPairText(payload['story']);
    if (story != null && story.isNotEmpty) {
      return StoryPairResultRecord(
        status: 'complete',
        text: story,
        completedAt: (payload['storyCompletedAt'] as num?)?.toInt() ??
            (payload['updatedAt'] as num?)?.toInt(),
      );
    }

    final storyError = _extractStoryPairError(payload['storyError']);
    if (storyError != null && storyError.isNotEmpty) {
      return StoryPairResultRecord(
        status: 'error',
        error: storyError,
        completedAt: (payload['storyCompletedAt'] as num?)?.toInt(),
      );
    }

    final legacyResult = payload['result'];
    if (legacyResult is Map) {
      return StoryPairResultRecord.fromJson(
        Map<String, dynamic>.from(legacyResult),
      );
    }

    final storyPrompt = (payload['storyPrompt'] as String?)?.trim();
    if (payload['storyReady'] == true ||
        (storyPrompt != null && storyPrompt.isNotEmpty)) {
      return const StoryPairResultRecord(status: 'waiting');
    }

    return null;
  }

  Future<void> saveStoryPairPlayer({
    required String pairId,
    required StoryPairPlayerRecord player,
  }) async {
    await patchValue(
      'mini/storyPairs/$pairId/meta',
      {
        'sessionId': player.sessionId,
        'pairRound': player.pairRound,
        'playerIds': <String>[player.playerId, player.partnerId],
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );

    await patchValue(
      'mini/storyPairs/$pairId/players/${player.playerId}',
      player.toJson(),
    );

    final playersPayload = await fetchValue('mini/storyPairs/$pairId/players');
    final players = playersPayload is Map
        ? playersPayload.values
            .whereType<Map>()
            .map(
              (item) => StoryPairPlayerRecord.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList()
        : const <StoryPairPlayerRecord>[];
    final storyReady = isStoryPairReady(players);
    final storyPrompt = storyReady ? buildStoryPairPrompt(players) : null;

    await patchValue(
      'mini/storyPairs/$pairId',
      {
        'storyPrompt': storyPrompt,
        'storyReady': storyReady,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  void _throwIfNotOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError(
        'Firebase permission denied. Sign in first or relax the backend rules. '
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }
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
  const PromptCatalog({
    required this.sets,
    required this.itemsById,
  });

  final Map<String, List<PromptItem>> sets;
  final Map<String, PromptItem> itemsById;

  PromptItem pickUnused(String setId, Set<String> usedIds) {
    final options = sets[setId] ?? const <PromptItem>[];
    if (options.isEmpty) {
      throw StateError('Prompt set $setId is empty.');
    }

    final unused = options.where((item) => !usedIds.contains(item.id)).toList();
    final source = unused.isNotEmpty ? unused : options;
    final index = Random.secure().nextInt(source.length);
    return source[index];
  }

  List<PromptItem> resolveIds(List<String> promptIds) {
    return promptIds
        .map(
          (id) => id == storyModePromptId
              ? storyModePromptItem
              : itemsById[id] ?? PromptItem(id: id, text: id),
        )
        .toList();
  }
}

PromptCatalog parseDatingPromptCatalog(Object? raw) {
  final promptRoot = _resolvePromptCatalogRoot(raw);
  if (promptRoot is! Map) {
    throw StateError('Expected a map at $_promptCatalogPath.');
  }

  final sets = <String, List<PromptItem>>{};
  final itemsById = <String, PromptItem>{};

  promptRoot.forEach((setId, value) {
    if (value is! Map) return;

    final promptItems = _extractPromptItems(value, setId.toString());
    if (promptItems.isEmpty) return;

    sets[setId.toString()] = promptItems;
    for (final item in promptItems) {
      itemsById[item.id] = item;
    }
  });

  if (itemsById.isEmpty) {
    throw StateError('No dating prompt sets found at $_promptCatalogPath.');
  }

  return PromptCatalog(sets: sets, itemsById: itemsById);
}

Object? _resolvePromptCatalogRoot(Object? raw) {
  if (raw is! Map) return raw;

  final prompts = _lookupCaseInsensitive(raw, 'prompts');
  if (prompts != null) {
    return _resolvePromptCatalogRoot(prompts);
  }

  final mini = _lookupCaseInsensitive(raw, 'mini');
  if (mini != null) {
    return _resolvePromptCatalogRoot(mini);
  }

  return raw;
}

List<PromptItem> _extractPromptItems(Map raw, String setId) {
  final collection = _lookupCaseInsensitive(raw, 'prompts');
  if (collection is! List) return const <PromptItem>[];

  final promptItems = <PromptItem>[];
  for (var index = 0; index < collection.length; index += 1) {
    final item =
        _parsePromptItem(collection[index], setId: setId, index: index);
    if (item != null) {
      promptItems.add(item);
    }
  }

  return promptItems;
}

PromptItem? _parsePromptItem(
  Object? raw, {
  required String setId,
  required int index,
}) {
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    return PromptItem(id: '$setId-${index + 1}', text: text);
  }

  if (raw is! Map) return null;

  final resolvedText =
      _firstNonEmptyString(raw, const ['text', 'prompt', 'value']);
  if (resolvedText == null) return null;

  final resolvedId =
      _firstNonEmptyString(raw, const ['id']) ?? '$setId-${index + 1}';
  return PromptItem(id: resolvedId, text: resolvedText);
}

Object? _lookupCaseInsensitive(Map raw, String key) {
  for (final entry in raw.entries.cast<MapEntry<Object?, Object?>>()) {
    if (entry.key.toString().toLowerCase() == key.toLowerCase()) {
      return entry.value;
    }
  }
  return null;
}

String? _firstNonEmptyString(Map raw, List<String> keys) {
  for (final key in keys) {
    final value = _lookupCaseInsensitive(raw, key);
    if (value is! String) continue;
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }

  return null;
}

class PromptCatalogService {
  PromptCatalogService({
    RtdbService? rtdbService,
    this.path = _promptCatalogPath,
  }) : _rtdbService = rtdbService ?? RtdbService();

  final RtdbService _rtdbService;
  final String path;

  Future<PromptCatalog> loadDatingCatalog() async {
    try {
      final raw = await _rtdbService.fetchValue(path);
      return parseDatingPromptCatalog(raw);
    } catch (_) {
      final raw =
          await rootBundle.loadString('Prompts/Dating/prompt_set_x.json');
      return parseDatingPromptCatalog(jsonDecode(raw));
    }
  }
}

class StoryPairChoiceRecord {
  const StoryPairChoiceRecord({
    required this.typeName,
    required this.options,
    this.category,
    this.selectedOption,
  });

  final String typeName;
  final List<String> options;
  final String? category;
  final String? selectedOption;

  bool get hasSelection => (selectedOption ?? '').trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'typeName': typeName,
      'options': options,
      'category': category,
      'selectedOption': selectedOption,
    };
  }

  factory StoryPairChoiceRecord.fromJson(Map<String, dynamic> json) {
    return StoryPairChoiceRecord(
      typeName: (json['typeName'] ?? '') as String,
      options: ((json['options'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      category: (json['category'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['category'] as String?,
      selectedOption:
          (json['selectedOption'] as String?)?.trim().isEmpty ?? true
              ? null
              : json['selectedOption'] as String?,
    );
  }
}

class StoryPairPlayerRecord {
  const StoryPairPlayerRecord({
    required this.playerId,
    required this.name,
    required this.sessionId,
    required this.partnerId,
    required this.pairRound,
    required this.choices,
    this.completedAt,
  });

  final String playerId;
  final String name;
  final String sessionId;
  final String partnerId;
  final int pairRound;
  final List<StoryPairChoiceRecord> choices;
  final int? completedAt;

  bool get isComplete =>
      completedAt != null &&
      choices.length == 3 &&
      choices.every((choice) => choice.hasSelection);

  Map<String, dynamic> toJson() {
    return {
      'playerId': playerId,
      'name': name,
      'sessionId': sessionId,
      'partnerId': partnerId,
      'pairRound': pairRound,
      'choices': choices.map((choice) => choice.toJson()).toList(),
      'completedAt': completedAt,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory StoryPairPlayerRecord.fromJson(Map<String, dynamic> json) {
    return StoryPairPlayerRecord(
      playerId: (json['playerId'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      sessionId: (json['sessionId'] ?? '') as String,
      partnerId: (json['partnerId'] ?? '') as String,
      pairRound: (json['pairRound'] as num?)?.toInt() ?? 1,
      choices: ((json['choices'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => StoryPairChoiceRecord.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      completedAt: (json['completedAt'] as num?)?.toInt(),
    );
  }
}

String? buildStoryPairPrompt(Iterable<StoryPairPlayerRecord> players) {
  final completedPlayers = _completedStoryPairPlayers(players);
  if (completedPlayers.length != 2) return null;

  return [
    'Names: ${completedPlayers.map(_storyPairPromptDisplayName).join(', ')}',
    for (final player in completedPlayers) _storyPairPromptBlock(player),
  ].join('\n');
}

bool isStoryPairReady(Iterable<StoryPairPlayerRecord> players) {
  return _completedStoryPairPlayers(players).length == 2;
}

List<StoryPairPlayerRecord> _completedStoryPairPlayers(
  Iterable<StoryPairPlayerRecord> players,
) {
  return players.where((player) => player.isComplete).toList()
    ..sort((left, right) => left.playerId.compareTo(right.playerId));
}

String _storyPairPromptBlock(StoryPairPlayerRecord player) {
  final selections = player.choices.map(_storyPairPromptChoice).join(', ');
  return '${_storyPairPromptDisplayName(player)}: $selections';
}

String _storyPairPromptDisplayName(StoryPairPlayerRecord player) {
  final name = player.name.trim();
  final resolvedName = name.isNotEmpty ? name : player.playerId;
  return resolvedName;
}

String _storyPairPromptChoice(StoryPairChoiceRecord choice) {
  final label = (choice.category ?? choice.typeName).trim();
  final selected = (choice.selectedOption ?? '').trim();
  return label.isEmpty ? selected : '$label: $selected';
}

class StoryPairResultRecord {
  const StoryPairResultRecord({
    required this.status,
    this.text,
    this.error,
    this.completedAt,
  });

  final String status;
  final String? text;
  final String? error;
  final int? completedAt;

  bool get isComplete => status == 'complete';
  bool get hasText => (text ?? '').trim().isNotEmpty;
  bool get isProcessing => status == 'processing';
  bool get isWaiting => status == 'waiting' || status == 'pending';
  bool get isError => status == 'error';

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'text': text,
      'error': error,
      'completedAt': completedAt,
    };
  }

  factory StoryPairResultRecord.fromJson(Map<String, dynamic> json) {
    final text = _extractStoryPairText(json['text']) ??
        _extractStoryPairText(json['story']);
    final error = _extractStoryPairError(json['error']) ??
        _extractStoryPairError(json['storyError']);
    final rawStatus = (json['status'] as String?)?.trim();
    return StoryPairResultRecord(
      status: rawStatus?.isNotEmpty == true
          ? rawStatus!
          : text != null
              ? 'complete'
              : error != null
                  ? 'error'
                  : 'waiting',
      text: text,
      error: error,
      completedAt: (json['completedAt'] as num?)?.toInt(),
    );
  }
}

String? _extractStoryPairText(Object? raw) {
  return _extractNestedNonEmptyString(
    raw,
    preferredKeys: const ['value', 'text', 'story', 'content'],
  );
}

String? _extractStoryPairError(Object? raw) {
  return _extractNestedNonEmptyString(
    raw,
    preferredKeys: const ['message', 'error', 'value', 'text'],
  );
}

String? _extractNestedNonEmptyString(
  Object? raw, {
  required List<String> preferredKeys,
}) {
  if (raw is String) {
    final normalized = raw.trim();
    return normalized.isEmpty ? null : normalized;
  }

  if (raw is Iterable) {
    for (final value in raw) {
      final extracted = _extractNestedNonEmptyString(
        value,
        preferredKeys: preferredKeys,
      );
      if (extracted != null) return extracted;
    }
    return null;
  }

  if (raw is Map) {
    final entries = raw.entries.toList();
    for (final key in preferredKeys) {
      for (final entry in entries) {
        if (entry.key.toString().trim().toLowerCase() != key) continue;
        final extracted = _extractNestedNonEmptyString(
          entry.value,
          preferredKeys: preferredKeys,
        );
        if (extracted != null) return extracted;
      }
    }

    for (final entry in entries) {
      final extracted = _extractNestedNonEmptyString(
        entry.value,
        preferredKeys: preferredKeys,
      );
      if (extracted != null) return extracted;
    }
  }

  return null;
}

String buildStoryPairId({
  required String sessionId,
  required String playerId,
  required String partnerId,
  required int pairRound,
}) {
  final normalizedSession = _sanitizeStoryPairSegment(sessionId);
  final sortedPlayers = [
    _sanitizeStoryPairSegment(playerId),
    _sanitizeStoryPairSegment(partnerId),
  ]..sort();
  return '$normalizedSession--${sortedPlayers.join('--')}--r$pairRound';
}

String _sanitizeStoryPairSegment(String value) {
  final sanitized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return sanitized.isEmpty ? 'unknown' : sanitized;
}

String generateInviteCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
}

String generateId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  final suffix =
      List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  return '$now-$suffix';
}
