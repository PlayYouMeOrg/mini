import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _databaseBaseUrl =
    'https://youmedev-feab4-default-rtdb.firebaseio.com';
const _firestoreProjectId = 'youmedev-feab4';

enum RoundPreference { openingUp, playful }

extension RoundPreferenceLabel on RoundPreference {
  String get label => this == RoundPreference.openingUp ? 'Opening up' : 'Playful';
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
  int? currentPromptRound;
  int currentPromptIndex;
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
      'currentPromptRound': currentPromptRound,
      'currentPromptIndex': currentPromptIndex,
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
    me.matchedPlayerIds = {
      ...me.matchedPlayerIds,
      partner.id,
    }.toList();

    partner.pairedWith = me.id;
    partner.pairedRound = round;
    partner.matchedPlayerIds = {
      ...partner.matchedPlayerIds,
      me.id,
    }.toList();

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

String generateInviteCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
}

String generateId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  final suffix = List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  return '$now-$suffix';
}
