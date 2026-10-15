import 'dart:math' as math;

enum MediaKind { video, audio }

enum AudioFormat { mp3, m4a }

/// Where yt-dlp runs: on the phone (Android) or on your own NxSaves server (iOS, optional on Android).
enum EngineKind { local, remote }

enum TaskStatus { queued, running, paused, failed }

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

int? asInt(Object? value) => switch (value) {
      int v => v,
      double v when v.isFinite => v.round(),
      String v => int.tryParse(v),
      _ => null,
    };

double? asDouble(Object? value) => switch (value) {
      num v when v.isFinite => v.toDouble(),
      String v => double.tryParse(v),
      _ => null,
    };

String? asString(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

/// What the user asked for. Engines translate this into yt-dlp options; the server never accepts
/// raw yt-dlp arguments from clients.
class DownloadSpec {
  const DownloadSpec({
    required this.kind,
    this.height,
    this.audioFormat = AudioFormat.mp3,
    this.preferCompat = true,
  });

  final MediaKind kind;

  /// Target resolution (shortest side, like yt-dlp's `res`). Null = highest available.
  final int? height;
  final AudioFormat audioFormat;

  /// Prefer H.264/AAC in MP4 so files play everywhere (gallery apps, iOS Photos, WhatsApp).
  final bool preferCompat;

  String get label => switch (kind) {
        MediaKind.video => height == null ? 'Best video' : '${height}p video',
        MediaKind.audio => audioFormat == AudioFormat.mp3 ? 'MP3 audio' : 'M4A audio',
      };

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'height': height,
        'audioFormat': audioFormat.name,
        'preferCompat': preferCompat,
      };

  factory DownloadSpec.fromJson(Map<String, dynamic> json) => DownloadSpec(
        kind: enumByName(MediaKind.values, json['kind'], MediaKind.video),
        height: asInt(json['height']),
        audioFormat: enumByName(AudioFormat.values, json['audioFormat'], AudioFormat.mp3),
        preferCompat: json['preferCompat'] != false,
      );

  @override
  bool operator ==(Object other) =>
      other is DownloadSpec &&
      other.kind == kind &&
      other.height == height &&
      other.audioFormat == audioFormat &&
      other.preferCompat == preferCompat;

  @override
  int get hashCode => Object.hash(kind, height, audioFormat, preferCompat);
}

/// One entry of yt-dlp's `formats` list.
class MediaFormat {
  const MediaFormat({
    required this.id,
    this.ext,
    this.vcodec,
    this.acodec,
    this.width,
    this.height,
    this.fps,
    this.filesize,
    this.tbr,
    this.abr,
    this.protocol,
    this.note,
    this.dynamicRange,
  });

  factory MediaFormat.fromJson(Map<String, dynamic> json) => MediaFormat(
        id: asString(json['format_id']) ?? '',
        ext: asString(json['ext']),
        vcodec: asString(json['vcodec']),
        acodec: asString(json['acodec']),
        width: asInt(json['width']),
        height: asInt(json['height']),
        fps: asDouble(json['fps']),
        filesize: asInt(json['filesize']) ?? asInt(json['filesize_approx']),
        tbr: asDouble(json['tbr']),
        abr: asDouble(json['abr']),
        protocol: asString(json['protocol']),
        note: asString(json['format_note']),
        dynamicRange: asString(json['dynamic_range']),
      );

  final String id;
  final String? ext;
  final String? vcodec;
  final String? acodec;
  final int? width;
  final int? height;
  final double? fps;
  final int? filesize;
  final double? tbr;
  final double? abr;
  final String? protocol;
  final String? note;
  final String? dynamicRange;

  bool get isStoryboard => ext == 'mhtml' || (note?.toLowerCase().contains('storyboard') ?? false);

  /// yt-dlp uses 'none' for "definitely absent"; null means unknown (often a combined stream).
  bool get hasVideo => !isStoryboard && vcodec != 'none';
  bool get hasAudio => !isStoryboard && acodec != 'none';
  bool get isVideoOnly => hasVideo && acodec == 'none';
  bool get isAudioOnly => !isStoryboard && vcodec == 'none' && acodec != 'none';
  bool get isHls => protocol?.contains('m3u8') ?? false;

  /// Shortest side, which is what yt-dlp's `res` sort field (and our quality labels) use, so a
  /// vertical 1080x1920 short is "1080p".
  int? get res {
    final w = width, h = height;
    if (w != null && h != null && w > 0 && h > 0) return math.min(w, h);
    return h;
  }

  String get codecFamily => codecFamilyOf(hasVideo ? vcodec : acodec);

  bool get isH264 => codecFamilyOf(vcodec) == 'H.264';

  /// Size in bytes, from yt-dlp's (approximate) filesize or bitrate × duration.
  int? estimateSize(double? duration) {
    if (filesize != null && filesize! > 0) return filesize;
    final rate = tbr ?? abr;
    if (rate != null && duration != null && duration > 0) return (rate * 125 * duration).round();
    return null;
  }
}

String codecFamilyOf(String? codec) {
  final c = (codec ?? '').toLowerCase();
  if (c.isEmpty || c == 'none') return '';
  if (c.startsWith('avc') || c.startsWith('h264')) return 'H.264';
  if (c.startsWith('hev') || c.startsWith('hvc') || c.startsWith('h265') || c.startsWith('bytevc1')) return 'HEVC';
  if (c.startsWith('vp9') || c.startsWith('vp09')) return 'VP9';
  if (c.startsWith('av01') || c.startsWith('av1')) return 'AV1';
  if (c.startsWith('vp8')) return 'VP8';
  if (c.startsWith('mp4a') || c.startsWith('aac')) return 'AAC';
  if (c.startsWith('opus')) return 'Opus';
  if (c.startsWith('mp3')) return 'MP3';
  return codec!;
}

class PlaylistEntry {
  const PlaylistEntry({required this.url, required this.title, this.thumbnail, this.duration, this.uploader});

  static PlaylistEntry? fromJson(Map<String, dynamic> json) {
    final url = asString(json['url']) ?? asString(json['webpage_url']) ?? asString(json['original_url']);
    if (url == null || !url.startsWith('http')) return null;
    return PlaylistEntry(
      url: url,
      title: asString(json['title']) ?? asString(json['id']) ?? url,
      thumbnail: pickThumbnail(json),
      duration: asDouble(json['duration']),
      uploader: asString(json['uploader']) ?? asString(json['channel']),
    );
  }

  final String url;
  final String title;
  final String? thumbnail;
  final double? duration;
  final String? uploader;
}

String? pickThumbnail(Map<String, dynamic> json) {
  final direct = asString(json['thumbnail']);
  if (direct != null) return direct;
  final list = json['thumbnails'];
  if (list is List && list.isNotEmpty) {
    for (final t in list.reversed) {
      if (t is Map && asString(t['url']) != null) return asString(t['url']);
    }
  }
  return null;
}

/// Metadata returned by yt-dlp (`-J`) for a link: a single video, or a playlist / profile.
class MediaInfo {
  const MediaInfo({
    required this.id,
    required this.title,
    required this.url,
    this.uploader,
    this.thumbnail,
    this.duration,
    this.extractor,
    this.isLive = false,
    this.isPlaylist = false,
    this.formats = const [],
    this.entries = const [],
  });

  factory MediaInfo.fromJson(Map<String, dynamic> json, {required String sourceUrl}) {
    final rawEntries = json['entries'];
    final isPlaylist = json['_type'] == 'playlist' || rawEntries is List;
    final formats = <MediaFormat>[];
    final rawFormats = json['formats'];
    if (rawFormats is List) {
      for (final f in rawFormats) {
        if (f is Map<String, dynamic>) formats.add(MediaFormat.fromJson(f));
      }
    } else if (!isPlaylist && json['url'] != null) {
      formats.add(MediaFormat.fromJson(json));
    }
    return MediaInfo(
      id: asString(json['id']) ?? '',
      title: asString(json['title']) ?? asString(json['fulltitle']) ?? 'Untitled',
      url: asString(json['webpage_url']) ?? asString(json['original_url']) ?? sourceUrl,
      uploader: asString(json['uploader']) ??
          asString(json['channel']) ??
          asString(json['creator']) ??
          asString(json['uploader_id']),
      thumbnail: pickThumbnail(json),
      duration: asDouble(json['duration']),
      extractor: asString(json['extractor_key']) ?? asString(json['extractor']),
      isLive: json['is_live'] == true || json['live_status'] == 'is_live' || json['live_status'] == 'is_upcoming',
      isPlaylist: isPlaylist,
      formats: formats,
      entries: [
        if (rawEntries is List)
          for (final e in rawEntries)
            if (e is Map<String, dynamic>) ?PlaylistEntry.fromJson(e),
      ],
    );
  }

  final String id;
  final String title;
  final String url;
  final String? uploader;
  final String? thumbnail;
  final double? duration;
  final String? extractor;
  final bool isLive;
  final bool isPlaylist;
  final List<MediaFormat> formats;
  final List<PlaylistEntry> entries;

  bool get hasVideo => formats.isEmpty || formats.any((f) => f.hasVideo);
  bool get hasAudio => formats.isEmpty || formats.any((f) => f.hasAudio);
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.title,
    required this.spec,
    required this.engine,
    required this.createdAt,
    this.thumbnail,
    this.uploader,
    this.duration,
    this.extractor,
    this.status = TaskStatus.queued,
    this.stage = 'Waiting…',
    this.error,
    this.errorDetail,
    this.remoteJobId,
  });

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id'] as String,
        url: json['url'] as String,
        title: asString(json['title']) ?? 'Untitled',
        spec: DownloadSpec.fromJson(Map<String, dynamic>.from(json['spec'] as Map)),
        engine: enumByName(EngineKind.values, json['engine'], EngineKind.local),
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
        thumbnail: asString(json['thumbnail']),
        uploader: asString(json['uploader']),
        duration: asDouble(json['duration']),
        extractor: asString(json['extractor']),
        status: enumByName(TaskStatus.values, json['status'], TaskStatus.queued),
        error: asString(json['error']),
        errorDetail: asString(json['errorDetail']),
        remoteJobId: asString(json['remoteJobId']),
      );

  final String id;
  final String url;
  String title;
  final DownloadSpec spec;
  final EngineKind engine;
  final DateTime createdAt;
  final String? thumbnail;
  final String? uploader;
  final double? duration;
  final String? extractor;

  TaskStatus status;
  String stage;
  String? error;
  String? errorDetail;
  String? remoteJobId;

  // Live progress (not persisted).
  double? progress;
  int? downloadedBytes;
  int? totalBytes;
  double? speed;
  int? eta;

  bool get isActive => status == TaskStatus.running || status == TaskStatus.queued;

  void clearProgress() {
    progress = null;
    downloadedBytes = null;
    totalBytes = null;
    speed = null;
    eta = null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'spec': spec.toJson(),
        'engine': engine.name,
        'createdAt': createdAt.toIso8601String(),
        'thumbnail': thumbnail,
        'uploader': uploader,
        'duration': duration,
        'extractor': extractor,
        'status': status.name,
        'error': error,
        'errorDetail': errorDetail,
        'remoteJobId': remoteJobId,
      };
}

/// A finished, saved download.
class LibraryItem {
  LibraryItem({
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.kind,
    required this.fileName,
    required this.mime,
    required this.sizeBytes,
    required this.createdAt,
    this.uploader,
    this.extractor,
    this.duration,
    this.filePath,
    this.contentUri,
    this.thumbnailFile,
    this.savedToPhotos = false,
  });

  factory LibraryItem.fromJson(Map<String, dynamic> json) => LibraryItem(
        id: json['id'] as String,
        title: asString(json['title']) ?? 'Untitled',
        sourceUrl: asString(json['sourceUrl']) ?? '',
        kind: enumByName(MediaKind.values, json['kind'], MediaKind.video),
        fileName: asString(json['fileName']) ?? '',
        mime: asString(json['mime']) ?? 'application/octet-stream',
        sizeBytes: asInt(json['sizeBytes']) ?? 0,
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
        uploader: asString(json['uploader']),
        extractor: asString(json['extractor']),
        duration: asDouble(json['duration']),
        filePath: asString(json['filePath']),
        contentUri: asString(json['contentUri']),
        thumbnailFile: asString(json['thumbnailFile']),
        savedToPhotos: json['savedToPhotos'] == true,
      );

  final String id;
  final String title;
  final String sourceUrl;
  final MediaKind kind;
  final String fileName;
  final String mime;
  final int sizeBytes;
  final DateTime createdAt;
  final String? uploader;
  final String? extractor;
  final double? duration;

  /// Android: absolute path in shared storage. iOS: path relative to the app's Documents folder
  /// (the container path changes between installs, so it is resolved at runtime).
  final String? filePath;

  /// Android MediaStore content:// URI used to open, share and delete the file.
  final String? contentUri;

  /// File name inside the app's thumbnail folder.
  final String? thumbnailFile;
  bool savedToPhotos;

  /// Set at runtime when the file was deleted outside the app.
  bool missing = false;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sourceUrl': sourceUrl,
        'kind': kind.name,
        'fileName': fileName,
        'mime': mime,
        'sizeBytes': sizeBytes,
        'createdAt': createdAt.toIso8601String(),
        'uploader': uploader,
        'extractor': extractor,
        'duration': duration,
        'filePath': filePath,
        'contentUri': contentUri,
        'thumbnailFile': thumbnailFile,
        'savedToPhotos': savedToPhotos,
      };
}
