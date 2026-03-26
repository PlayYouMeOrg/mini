enum LaunchIntentType { none, preview, demo, session }

enum ScreenState {
  booting,
  join,
  error,
  preview,
  signup,
  waiting,
  matching,
  game,
  ended,
}

class LaunchIntent {
  const LaunchIntent._({
    required this.type,
    this.sessionId,
  });

  const LaunchIntent.none() : this._(type: LaunchIntentType.none);

  const LaunchIntent.preview() : this._(type: LaunchIntentType.preview);

  const LaunchIntent.demo() : this._(type: LaunchIntentType.demo);

  const LaunchIntent.session(String sessionId)
      : this._(
          type: LaunchIntentType.session,
          sessionId: sessionId,
        );

  final LaunchIntentType type;
  final String? sessionId;

  bool get isLocal => type == LaunchIntentType.preview;

  bool get requiresBackend =>
      type == LaunchIntentType.demo || type == LaunchIntentType.session;

  factory LaunchIntent.fromUri(Uri uri) {
    final params = mergedUrlQueryParameters(uri);
    if (_queryBool(params, 'preview') || _queryBool(params, 'uiPreview')) {
      return const LaunchIntent.preview();
    }

    if (_queryBool(params, 'demo')) {
      return const LaunchIntent.demo();
    }

    final sessionId = _firstNonEmptyValue(
      params,
      const ['session', 'sessionId', 'code'],
    );
    if (sessionId != null) {
      return LaunchIntent.session(sessionId);
    }

    return const LaunchIntent.none();
  }
}

Map<String, String> mergedUrlQueryParameters(Uri uri) {
  final params = <String, String>{};

  void addQueryString(String rawQuery) {
    if (rawQuery.isEmpty) return;

    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) continue;

      final separatorIndex = segment.indexOf('=');
      final rawKey =
          separatorIndex == -1 ? segment : segment.substring(0, separatorIndex);
      if (rawKey.isEmpty) continue;

      final rawValue =
          separatorIndex == -1 ? '' : segment.substring(separatorIndex + 1);
      params[Uri.decodeQueryComponent(rawKey)] =
          Uri.decodeQueryComponent(rawValue);
    }
  }

  addQueryString(uri.query);

  final fragment = uri.fragment;
  final fragmentQueryIndex = fragment.indexOf('?');
  if (fragmentQueryIndex != -1 && fragmentQueryIndex < fragment.length - 1) {
    addQueryString(fragment.substring(fragmentQueryIndex + 1));
  }

  return params;
}

String? _firstNonEmptyValue(
  Map<String, String> params,
  List<String> keys,
) {
  for (final key in keys) {
    final raw = params[key];
    if (raw == null) continue;
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }

  return null;
}

bool _queryBool(Map<String, String> params, String key) {
  final raw = params[key];
  if (raw == null) return false;
  if (raw.trim().isEmpty) return true;

  final normalized = raw.trim().toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}
