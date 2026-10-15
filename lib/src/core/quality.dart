import 'models.dart';

/// A choice shown in the quality picker, built from the formats yt-dlp actually reported.
class QualityOption {
  const QualityOption({
    required this.spec,
    required this.title,
    this.badge,
    this.detail = '',
    this.approxBytes,
    this.compatible = true,
  });

  final DownloadSpec spec;
  final String title;
  final String? badge;
  final String detail;
  final int? approxBytes;

  /// False when only VP9/AV1 exists at this resolution (may not play in iOS Photos or old phones).
  final bool compatible;
}

String? resolutionBadge(int res) {
  if (res >= 2160) return '4K';
  if (res >= 1440) return '2K';
  if (res >= 1080) return 'Full HD';
  if (res >= 720) return 'HD';
  return null;
}

/// yt-dlp's default video codec preference (av01 > vp9 > hevc > h264 > vp8 > other).
int _codecRank(MediaFormat f) => switch (codecFamilyOf(f.vcodec)) {
      'AV1' => 6,
      'VP9' => 5,
      'HEVC' => 4,
      'H.264' => 3,
      'VP8' => 2,
      '' => 0,
      _ => 1,
    };

/// `-S vcodec:h264` means "best codec no better than H.264, else the *least* advanced one above
/// it", so when H.264 is missing yt-dlp takes HEVC, then VP9, and AV1 last.
int _compatCodecRank(MediaFormat f) => switch (codecFamilyOf(f.vcodec)) {
      'H.264' => 10,
      'VP8' => 9,
      'HEVC' => 5,
      'VP9' => 4,
      'AV1' => 3,
      '' => 6,
      _ => 7,
    };

/// Mirrors the order of the yt-dlp sort we send (see ytdlp_args.dart: `res:N,vcodec:h264,fps,…`
/// or `res:N,fps` followed by yt-dlp's defaults hdr, vcodec, …, proto) closely enough to show
/// the codec and size yt-dlp will actually pick at each resolution.
MediaFormat _pickVideo(List<MediaFormat> candidates, bool preferCompat) {
  int desc(num a, num b) => b.compareTo(a);
  int hdr(MediaFormat f) => (f.dynamicRange ?? 'SDR') == 'SDR' ? 0 : 1;
  final sorted = [...candidates]
    ..sort((a, b) {
      final keys = <int>[
        if (preferCompat) desc(_compatCodecRank(a), _compatCodecRank(b)),
        desc(a.fps ?? 0, b.fps ?? 0),
        desc(hdr(a), hdr(b)),
        desc(_codecRank(a), _codecRank(b)),
        desc(a.isHls ? 0 : 1, b.isHls ? 0 : 1), // https before m3u8
        desc(a.tbr ?? 0, b.tbr ?? 0),
      ];
      return keys.firstWhere((k) => k != 0, orElse: () => 0);
    });
  return sorted.first;
}

/// The audio stream yt-dlp would take: AAC when [preferAac] (our `acodec:aac` sort / `ba[ext=m4a]`),
/// otherwise its default codec order (Opus > Vorbis > AAC > MP3).
MediaFormat? bestAudio(List<MediaFormat> formats, {required bool preferAac}) {
  final audio = formats.where((f) => f.isAudioOnly).toList();
  if (audio.isEmpty) return null;
  int codecRank(MediaFormat f) => switch (f.codecFamily) {
        'Opus' => 4,
        'AAC' => 2,
        'MP3' => 1,
        _ => (f.acodec ?? '').startsWith('vorbis') ? 3 : 0,
      };
  int score(MediaFormat f) {
    var s = 0;
    final aac = f.codecFamily == 'AAC' || f.ext == 'm4a';
    if (preferAac && aac) s += 1000000;
    if (f.id.contains('drc')) s -= 500000; // dynamic-range-compressed duplicates
    if (!f.isHls) s += 100000;
    if (!preferAac) s += codecRank(f) * 10000;
    s += (f.abr ?? f.tbr ?? 0).round();
    return s;
  }

  audio.sort((a, b) => score(b).compareTo(score(a)));
  return audio.first;
}

List<QualityOption> buildVideoOptions(MediaInfo info, {required bool preferCompat}) {
  final byRes = <int, List<MediaFormat>>{};
  var anyVideo = false;
  for (final f in info.formats) {
    if (!f.hasVideo) continue;
    anyVideo = true;
    final res = f.res;
    if (res == null || res < 100) continue;
    byRes.putIfAbsent(res, () => []).add(f);
  }

  if (byRes.isEmpty) {
    if (!anyVideo && info.formats.isNotEmpty) return const [];
    return [
      QualityOption(
        spec: DownloadSpec(kind: MediaKind.video, preferCompat: preferCompat),
        title: 'Best available',
        detail: 'Highest quality the site offers',
      ),
    ];
  }

  final audio = bestAudio(info.formats, preferAac: preferCompat);
  final resolutions = byRes.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final res in resolutions)
      () {
        final candidates = byRes[res]!;
        final pick = _pickVideo(candidates, preferCompat);
        final videoBytes = pick.estimateSize(info.duration);
        final audioBytes = pick.isVideoOnly ? audio?.estimateSize(info.duration) : 0;
        final fps = candidates.map((f) => f.fps ?? 0).fold<double>(0, (a, b) => b > a ? b : a);
        final parts = <String>[
          if (fps > 31) '${fps.round()} fps',
          if (pick.codecFamily.isNotEmpty) pick.codecFamily,
          if ((pick.dynamicRange ?? 'SDR') != 'SDR') pick.dynamicRange!,
        ];
        return QualityOption(
          spec: DownloadSpec(kind: MediaKind.video, height: res, preferCompat: preferCompat),
          title: '${res}p',
          badge: resolutionBadge(res),
          detail: parts.join(' · '),
          approxBytes: videoBytes == null || audioBytes == null ? null : videoBytes + audioBytes,
          compatible: candidates.any((f) => f.isH264) || pick.codecFamily.isEmpty,
        );
      }(),
  ];
}

List<QualityOption> buildAudioOptions(MediaInfo info) {
  if (!info.hasAudio) return const [];
  final duration = info.duration;
  final aac = bestAudio(info.formats, preferAac: true);
  final best = bestAudio(info.formats, preferAac: false);
  final hasAac = aac != null && aac.codecFamily == 'AAC';
  final aacKbps = (aac?.abr ?? aac?.tbr)?.round();
  return [
    QualityOption(
      spec: const DownloadSpec(kind: MediaKind.audio, audioFormat: AudioFormat.mp3),
      title: 'MP3',
      badge: 'Universal',
      detail: best == null ? 'Best quality, converted' : 'From ${best.codecFamily} · VBR ~245 kbps',
      // LAME V0 averages roughly 245 kbit/s.
      approxBytes: duration == null ? null : (duration * 245000 / 8).round(),
    ),
    QualityOption(
      spec: const DownloadSpec(kind: MediaKind.audio, audioFormat: AudioFormat.m4a),
      title: 'M4A',
      badge: 'Original',
      detail: hasAac
          ? ['AAC', if (aacKbps != null) '$aacKbps kbps', 'no re-encode'].join(' · ')
          : 'AAC audio',
      approxBytes: hasAac ? aac.estimateSize(duration) : null,
    ),
  ];
}

/// The option matching the user's default (the largest ≤ the preferred height), else the smallest.
/// A height-less "Best" option only wins when the default is "best" or nothing else exists.
QualityOption? defaultOption(List<QualityOption> options, int? preferredHeight) {
  if (options.isEmpty) return null;
  if (preferredHeight == null) return options.first;
  for (final option in options) {
    final h = option.spec.height;
    if (h != null && h <= preferredHeight) return option;
  }
  return options.lastWhere((o) => o.spec.height != null, orElse: () => options.first);
}

/// Fixed choices for playlists, where per-video formats aren't known up front.
List<QualityOption> genericVideoOptions({required bool preferCompat}) => [
      for (final h in const [null, 2160, 1440, 1080, 720, 480, 360])
        QualityOption(
          spec: DownloadSpec(kind: MediaKind.video, height: h, preferCompat: preferCompat),
          title: h == null ? 'Best' : '${h}p',
          badge: h == null ? 'Highest' : resolutionBadge(h),
          detail: h == null ? 'Highest each video offers' : 'Or the closest below',
        ),
    ];
