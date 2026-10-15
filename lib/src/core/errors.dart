class EngineException implements Exception {
  EngineException(this.message, {this.detail, this.canceled = false, this.statusCode});

  EngineException.canceled() : this('Canceled', canceled: true);

  final String message;
  final String? detail;
  final bool canceled;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Picks the most useful line out of yt-dlp's stderr.
String lastErrorLine(String raw) {
  final lines = raw.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  for (final line in lines.reversed) {
    if (line.startsWith('ERROR:')) return line.substring(6).trim();
  }
  return lines.isEmpty ? raw.trim() : lines.last;
}

/// Maps raw yt-dlp / network errors to a message a person can act on.
String friendlyError(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Something went wrong.';
  final text = raw.toLowerCase();
  bool has(String s) => text.contains(s);

  if (has('unsupported url')) {
    return "This link isn't supported. Paste a link to a single video or post.";
  }
  if (has('not a bot') || has('confirm you’re not a bot') || has("confirm you're not a bot")) {
    return 'YouTube wants to confirm you’re not a bot. Wait a bit, update yt-dlp in Settings, or add a cookies file.';
  }
  if (has('sign in to confirm your age') || has('age-restricted') || has('inappropriate for some users')) {
    return 'This video is age-restricted. It needs a cookies file from a signed-in account (Settings → Cookies).';
  }
  if (has('private video') || has('this video is private')) return 'This video is private.';
  if (has('members-only') || has('join this channel')) return 'This video is for channel members only.';
  if (has('login required') ||
      has('rate-limit reached or login required') ||
      has('you need to log in') ||
      has('requires authentication') ||
      has('use --cookies') ||
      has('cookies-from-browser')) {
    return 'The site requires a logged-in account for this. Add a cookies file in Settings and retry.';
  }
  if (has('http error 429') || has('too many requests')) {
    return 'The site is rate-limiting requests. Wait a few minutes and try again.';
  }
  if (has('drm protect') || has('drm-protect') || has('use drm')) {
    return "This video is DRM-protected and can't be downloaded.";
  }
  if (has('is live') || has('live event will begin') || has('premieres in') || has('this live event')) {
    return "Live streams and upcoming premieres can't be downloaded until they end.";
  }
  if (has('requested format is not available')) {
    return "That quality isn't available for this video. Pick another one.";
  }
  if (has('video unavailable') ||
      has('this video is unavailable') ||
      has('has been removed') ||
      has('no longer available') ||
      has('not available in your country') ||
      has('http error 404') ||
      has('http error 410')) {
    return 'This video is unavailable (removed, private, or blocked in your region).';
  }
  if (has('no space left') || has('enospc')) return 'Not enough free storage on this device.';
  if (has('unable to download webpage') ||
      has('timed out') ||
      has('failed to resolve') ||
      has('name or service not known') ||
      has('temporary failure in name resolution') ||
      has('no address associated') ||
      has('getaddrinfo') ||
      has('network is unreachable') ||
      has('connection reset') ||
      has('connection refused') ||
      has('failed host lookup') ||
      has('socketexception') ||
      has('certificate_verify_failed')) {
    return 'Network problem. Check your connection and try again.';
  }
  final line = lastErrorLine(raw).replaceFirst(RegExp(r'^\[[^\]]+\] [^:]+: '), '');
  return line.length > 220 ? '${line.substring(0, 217)}…' : line;
}
