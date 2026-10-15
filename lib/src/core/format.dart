String formatBytes(num? bytes, {int decimals = 1}) {
  if (bytes == null || bytes < 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : decimals;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatSpeed(double? bytesPerSecond) =>
    bytesPerSecond == null || bytesPerSecond <= 0 ? '' : '${formatBytes(bytesPerSecond)}/s';

String formatDuration(num? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

String formatEta(int? seconds) {
  if (seconds == null || seconds < 0) return '';
  if (seconds < 60) return '${seconds}s left';
  if (seconds < 3600) return '${(seconds / 60).ceil()} min left';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return '${h}h ${m}m left';
}

String formatDate(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final base = '${months[date.month - 1]} ${date.day}';
  return date.year == today.year ? base : '$base, ${date.year}';
}

/// Friendly name for a yt-dlp extractor key ("Youtube" → "YouTube").
String siteName(String? extractor, {String? url}) {
  final key = (extractor ?? '').toLowerCase();
  // Prefix match, so "YoutubeTab", "TikTokUser", "FacebookReel"… map to their site.
  const known = {
    'youtube': 'YouTube',
    'tiktok': 'TikTok',
    'instagram': 'Instagram',
    'facebook': 'Facebook',
    'twitter': 'X',
    'vimeo': 'Vimeo',
    'reddit': 'Reddit',
    'soundcloud': 'SoundCloud',
    'twitch': 'Twitch',
    'dailymotion': 'Dailymotion',
    'pinterest': 'Pinterest',
    'bilibili': 'Bilibili',
    'generic': 'Web',
  };
  for (final entry in known.entries) {
    if (key == entry.key || key.startsWith(entry.key)) return entry.value;
  }
  if (key.isNotEmpty) return extractor!;
  final host = url == null ? null : Uri.tryParse(url)?.host;
  return host?.replaceFirst('www.', '') ?? 'Web';
}
