import 'ytdlp_args.dart';

class TaskProgress {
  const TaskProgress({
    required this.stage,
    this.fraction,
    this.downloaded,
    this.total,
    this.speed,
    this.eta,
  });

  final String stage;

  /// 0..1 overall progress; null = indeterminate (e.g. merging).
  final double? fraction;
  final int? downloaded;
  final int? total;
  final double? speed;
  final int? eta;
}

const _postprocessorLabels = {
  'Merger': 'Merging video and audio',
  'ExtractAudio': 'Converting audio',
  'EmbedThumbnail': 'Adding cover art',
  'Metadata': 'Writing metadata',
  'FFmpegMetadata': 'Writing metadata',
  'ThumbnailsConvertor': 'Preparing cover art',
  'VideoRemuxer': 'Remuxing',
  'VideoConvertor': 'Converting video',
  'FixupM3u8': 'Finalizing',
  'FixupM4a': 'Finalizing',
  'FixupStretched': 'Finalizing',
  'FixupDuplicateMoov': 'Finalizing',
  'FixupTimestamp': 'Finalizing',
  'FixupDuration': 'Finalizing',
  'MoveFiles': 'Finalizing',
};

String postprocessorLabel(String? name) => _postprocessorLabels[name] ?? 'Processing';

/// Turns yt-dlp's console output (with our `--progress-template` lines) into progress updates.
///
/// Separate video+audio downloads are reported as parts ("160+140" = 2 parts); overall progress
/// splits evenly between them so the bar only moves forward.
class YtDlpProgressParser {
  static final _formatsLine = RegExp(r'^\[info\] .+: Downloading \d+ format\(s\): (.+)$');

  int _parts = 1;
  int _part = -1;
  String? lastError;

  TaskProgress? feed(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;
    if (line.startsWith(kDownloadTag)) return _download(line.substring(kDownloadTag.length));
    if (line.startsWith(kPostprocessTag)) return _postprocess(line.substring(kPostprocessTag.length));

    final formats = _formatsLine.firstMatch(line);
    if (formats != null) {
      _parts = formats.group(1)!.split('+').length.clamp(1, 8);
      _part = -1;
      return const TaskProgress(stage: 'Starting download');
    }
    if (line.startsWith('[download] Destination:')) {
      _part = (_part + 1).clamp(0, _parts - 1);
      return null;
    }
    if (line.startsWith('[download]') && line.endsWith('has already been downloaded')) {
      _part = (_part + 1).clamp(0, _parts - 1);
      return TaskProgress(stage: 'Already downloaded', fraction: (_part + 1) / _parts);
    }
    if (line.startsWith('ERROR:')) {
      lastError = line.substring(6).trim();
      return null;
    }
    if (line.startsWith('[') && line.contains('Extracting URL')) {
      return const TaskProgress(stage: 'Reading link');
    }
    return null;
  }

  TaskProgress _download(String data) {
    final f = data.split('|');
    String? at(int i) => i < f.length && f[i] != 'NA' && f[i].isNotEmpty ? f[i] : null;
    final status = at(0);
    final downloaded = int.tryParse(at(1) ?? '') ?? double.tryParse(at(1) ?? '')?.round();
    final total = int.tryParse(at(2) ?? '') ?? double.tryParse(at(3) ?? '')?.round();
    final speed = double.tryParse(at(4) ?? '');
    final eta = double.tryParse(at(5) ?? '')?.round();
    final vcodec = at(6);
    final acodec = at(7);

    final part = _part < 0 ? 0 : _part;
    double? partFraction;
    if (status == 'finished') {
      partFraction = 1;
    } else if (downloaded != null && total != null && total > 0) {
      partFraction = (downloaded / total).clamp(0.0, 1.0);
    }

    var stage = switch ((vcodec, acodec)) {
      (final v, 'none') when v != 'none' => 'Downloading video',
      ('none', final a) when a != 'none' => 'Downloading audio',
      _ => 'Downloading',
    };
    if (_parts > 1) stage = '$stage (${part + 1}/$_parts)';

    return TaskProgress(
      stage: stage,
      fraction: partFraction == null ? null : (part + partFraction) / _parts,
      downloaded: downloaded,
      total: total,
      speed: speed,
      eta: eta,
    );
  }

  TaskProgress? _postprocess(String data) {
    final f = data.split('|');
    if (f.isEmpty || f.first != 'started') return null;
    return TaskProgress(stage: postprocessorLabel(f.length > 1 ? f[1] : null));
  }
}
