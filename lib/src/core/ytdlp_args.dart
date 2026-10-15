import 'models.dart';

/// Prefixes of the machine-readable progress lines we ask yt-dlp to print.
const kDownloadTag = 'NXDL|';
const kPostprocessTag = 'NXPP|';

const _downloadTemplate = 'download:$kDownloadTag'
    '%(progress.status)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|'
    '%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|'
    '%(info.vcodec)s|%(info.acodec)s|%(info.format_id)s';

const _postprocessTemplate = 'postprocess:$kPostprocessTag%(progress.status)s|%(progress.postprocessor)s';

/// yt-dlp `-S` (format sort) for a video spec. `res:N` = largest resolution ≤ N (or the smallest
/// above it if nothing is ≤ N), so a choice never fails just because a size is missing.
/// With [DownloadSpec.preferCompat], H.264 + AAC wins whenever it exists at that resolution.
/// Keep in sync with `format_sort()` in server/nxsaves_server.py.
String formatSort(DownloadSpec spec) {
  final res = spec.height == null ? 'res' : 'res:${spec.height}';
  return spec.preferCompat ? '$res,vcodec:h264,fps,acodec:aac' : '$res,fps';
}

/// Format selection + post-processing for a spec. Keep in sync with server/nxsaves_server.py.
List<String> specArgs(DownloadSpec spec) {
  switch (spec.kind) {
    case MediaKind.video:
      return ['-f', 'bv*+ba/b', '-S', formatSort(spec), '--merge-output-format', 'mp4'];
    case MediaKind.audio:
      return [
        '-f',
        spec.audioFormat == AudioFormat.m4a ? 'ba[ext=m4a]/ba/b' : 'ba/b',
        '-x',
        '--audio-format',
        spec.audioFormat.name,
        '--audio-quality',
        '0',
        '--embed-metadata',
        '--embed-thumbnail',
      ];
  }
}

/// Full argument list for an on-device download into [outputDir].
List<String> buildDownloadArgs(DownloadSpec spec, {required String outputDir, String? cookiesFile}) => [
      '--no-playlist',
      '--newline',
      '--progress-delta',
      '0.5',
      '--progress-template',
      _downloadTemplate,
      '--progress-template',
      _postprocessTemplate,
      // Files get "now" as their date, so they sort as new in the gallery.
      '--no-mtime',
      // Strips characters that shared storage rejects (":", "?", "|"…).
      '--windows-filenames',
      '--concurrent-fragments',
      '4',
      '--retries',
      '10',
      '--fragment-retries',
      '10',
      ...cookieArgs(cookiesFile),
      '-P',
      outputDir,
      '-o',
      '%(title,id).150B.%(ext)s',
      ...specArgs(spec),
    ];

List<String> cookieArgs(String? cookiesFile) =>
    cookiesFile == null || cookiesFile.isEmpty ? const [] : ['--cookies', cookiesFile];
