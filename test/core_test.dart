import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nxsaves/src/core/errors.dart';
import 'package:nxsaves/src/core/format.dart';
import 'package:nxsaves/src/core/links.dart';
import 'package:nxsaves/src/core/models.dart';
import 'package:nxsaves/src/core/progress_parser.dart';
import 'package:nxsaves/src/core/quality.dart';
import 'package:nxsaves/src/core/ytdlp_args.dart';

MediaInfo loadFixture() {
  final json = jsonDecode(File('test/fixtures/youtube_bbb.json').readAsStringSync()) as Map<String, dynamic>;
  return MediaInfo.fromJson(json, sourceUrl: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ');
}

void main() {
  group('MediaInfo + quality options (real yt-dlp output)', () {
    final info = loadFixture();

    test('parses metadata', () {
      expect(info.title, startsWith('Big Buck Bunny'));
      expect(info.extractor, 'Youtube');
      expect(info.duration, 635);
      expect(info.isPlaylist, isFalse);
      expect(info.formats, hasLength(53));
      expect(siteName(info.extractor), 'YouTube');
    });

    test('video options list every resolution, best first, without storyboards', () {
      final options = buildVideoOptions(info, preferCompat: true);
      expect(options.map((o) => o.title).toList(), ['2160p', '1440p', '1080p', '720p', '480p', '360p', '240p', '144p']);
      expect(options.first.badge, '4K');
      // Only VP9/AV1 exist at 4K and 1440p on YouTube.
      expect(options[0].compatible, isFalse);
      expect(options[1].compatible, isFalse);
      expect(options[2].compatible, isTrue);
    });

    test('compatible 1080p picks H.264 + AAC and estimates the merged size', () {
      final options = buildVideoOptions(info, preferCompat: true);
      final hd = options.firstWhere((o) => o.title == '1080p');
      expect(hd.detail, contains('H.264'));
      expect(hd.detail, contains('60 fps'));
      expect(hd.approxBytes, 257619653 + 10271496); // format 299 + 140
      expect(hd.spec, const DownloadSpec(kind: MediaKind.video, height: 1080, preferCompat: true));
    });

    test('compat mode above 1080p shows what yt-dlp picks without H.264: VP9 (315), not AV1', () {
      final uhd = buildVideoOptions(info, preferCompat: true).first;
      expect(uhd.detail, '60 fps · VP9');
      expect(uhd.approxBytes, 1362269481 + 10271496); // format 315 + 140
    });

    test('without compat preference the codec yt-dlp picks (AV1 399 + Opus 251) is shown', () {
      final hd = buildVideoOptions(info, preferCompat: false).firstWhere((o) => o.title == '1080p');
      expect(hd.detail, '60 fps · AV1');
      expect(hd.approxBytes, 124386876 + 10202210);
    });

    test('audio options: MP3 and original M4A', () {
      final audio = buildAudioOptions(info);
      expect(audio.map((o) => o.title), ['MP3', 'M4A']);
      // yt-dlp's `ba` picks Opus 251 here, so that's what the MP3 is converted from.
      expect(audio[0].detail, startsWith('From Opus'));
      expect(audio[1].approxBytes, 10271496);
      expect(audio[1].detail, contains('no re-encode'));
    });

    test('default option is the best one at or below the preferred height', () {
      final options = buildVideoOptions(info, preferCompat: true);
      expect(defaultOption(options, 1080)!.title, '1080p');
      expect(defaultOption(options, 1000)!.title, '720p');
      expect(defaultOption(options, null)!.title, '2160p');
      expect(defaultOption(options, 100)!.title, '144p');
    });

    test('playlist choices honour the default height instead of picking "Best"', () {
      final generic = genericVideoOptions(preferCompat: true);
      expect(defaultOption(generic, 1080)!.title, '1080p');
      expect(defaultOption(generic, 2160)!.title, '2160p');
      expect(defaultOption(generic, null)!.title, 'Best');
      expect(defaultOption(generic, 240)!.title, '360p');
    });

    test('vertical videos are labelled by their short side', () {
      final vertical = MediaInfo.fromJson({
        'id': 'x',
        'title': 'Short',
        'formats': [
          {'format_id': 'a', 'width': 1080, 'height': 1920, 'vcodec': 'avc1.640028', 'acodec': 'mp4a.40.2', 'ext': 'mp4'},
        ],
      }, sourceUrl: 'https://example.com');
      expect(buildVideoOptions(vertical, preferCompat: true).single.title, '1080p');
    });

    test('formats without any resolution still get a "Best available" choice', () {
      final unknown = MediaInfo.fromJson({
        'id': 'x',
        'title': 'Clip',
        'formats': [
          {'format_id': 'hd', 'ext': 'mp4'},
        ],
      }, sourceUrl: 'https://example.com');
      final options = buildVideoOptions(unknown, preferCompat: true);
      expect(options.single.spec.height, isNull);
    });

    test('flat playlists keep entries with URLs', () {
      final playlist = MediaInfo.fromJson({
        '_type': 'playlist',
        'title': 'Mix',
        'entries': [
          {'url': 'https://www.youtube.com/watch?v=1', 'title': 'One'},
          {'title': 'no url'},
          {'url': 'https://www.youtube.com/watch?v=2', 'title': 'Two', 'thumbnails': [
            {'url': 'https://i.ytimg.com/a.jpg'},
          ]},
        ],
      }, sourceUrl: 'https://www.youtube.com/playlist?list=x');
      expect(playlist.isPlaylist, isTrue);
      expect(playlist.entries.map((e) => e.title), ['One', 'Two']);
      expect(playlist.entries[1].thumbnail, 'https://i.ytimg.com/a.jpg');
    });
  });

  group('yt-dlp arguments', () {
    test('format sort strings', () {
      expect(formatSort(const DownloadSpec(kind: MediaKind.video, height: 1080)), 'res:1080,vcodec:h264,fps,acodec:aac');
      expect(formatSort(const DownloadSpec(kind: MediaKind.video, height: 720, preferCompat: false)), 'res:720,fps');
      expect(formatSort(const DownloadSpec(kind: MediaKind.video)), 'res,vcodec:h264,fps,acodec:aac');
    });

    test('video download args', () {
      final args = buildDownloadArgs(const DownloadSpec(kind: MediaKind.video, height: 1080), outputDir: '/w/1');
      expect(args, containsAllInOrder(['-P', '/w/1', '-o', '%(title,id).150B.%(ext)s']));
      expect(args, containsAllInOrder(['-f', 'bv*+ba/b', '-S', 'res:1080,vcodec:h264,fps,acodec:aac']));
      expect(args, containsAllInOrder(['--merge-output-format', 'mp4']));
      expect(args, contains('--no-playlist'));
      expect(args, isNot(contains('--cookies')));
    });

    test('audio download args', () {
      final mp3 = specArgs(const DownloadSpec(kind: MediaKind.audio, audioFormat: AudioFormat.mp3));
      expect(mp3, containsAllInOrder(['-f', 'ba/b', '-x', '--audio-format', 'mp3']));
      final m4a = specArgs(const DownloadSpec(kind: MediaKind.audio, audioFormat: AudioFormat.m4a));
      expect(m4a, containsAllInOrder(['-f', 'ba[ext=m4a]/ba/b', '-x', '--audio-format', 'm4a']));
    });

    test('cookies are passed when configured', () {
      final args = buildDownloadArgs(const DownloadSpec(kind: MediaKind.video), outputDir: '/w', cookiesFile: '/c.txt');
      expect(args, containsAllInOrder(['--cookies', '/c.txt']));
    });
  });

  group('progress parser (real yt-dlp output)', () {
    test('two-part download then merge', () {
      final parser = YtDlpProgressParser();
      final out = <TaskProgress>[];
      for (final line in const [
        '[youtube] Extracting URL: https://www.youtube.com/watch?v=aqz-KE-bpKQ',
        '[info] aqz-KE-bpKQ: Downloading 1 format(s): 160+140',
        '[download] Destination: out/Big Buck Bunny.f160.mp4',
        'NXDL|downloading|1024|4323893|NA|1022854.79|4|avc1.4D400C|none|160',
        'NXDL|finished|4323893|4323893|NA|10416429.0|NA|avc1.4D400C|none|160',
        '[download] Destination: out/Big Buck Bunny.f140.m4a',
        'NXDL|downloading|5135748|10271496|NA|9693294.6|1|none|mp4a.40.2|140',
        'NXDL|finished|10271496|10271496|NA|7770116.6|NA|none|mp4a.40.2|140',
        'NXPP|started|Merger',
        '[Merger] Merging formats into "out/Big Buck Bunny.mp4"',
        'NXPP|finished|Merger',
      ]) {
        final p = parser.feed(line);
        if (p != null) out.add(p);
      }
      expect(out.first.stage, 'Reading link');
      final video = out.firstWhere((p) => p.stage.startsWith('Downloading video'));
      expect(video.stage, 'Downloading video (1/2)');
      expect(video.fraction, closeTo(1024 / 4323893 / 2, 1e-6));
      expect(video.total, 4323893);
      expect(video.eta, 4);
      final audioHalf = out.firstWhere((p) => p.stage.startsWith('Downloading audio') && p.fraction! < 1);
      expect(audioHalf.stage, 'Downloading audio (2/2)');
      expect(audioHalf.fraction, closeTo(0.75, 0.001));
      expect(out.last.stage, 'Merging video and audio');
      expect(out.last.fraction, isNull);
    });

    test('single file with only an estimated size', () {
      final parser = YtDlpProgressParser();
      parser.feed('[info] x: Downloading 1 format(s): hls-720');
      parser.feed('[download] Destination: a.mp4');
      final p = parser.feed('NXDL|downloading|500|NA|1000.0|NA|NA|NA|NA|hls-720')!;
      expect(p.stage, 'Downloading');
      expect(p.fraction, 0.5);
      expect(p.speed, isNull);
    });

    test('remembers the last error line', () {
      final parser = YtDlpProgressParser();
      parser.feed('ERROR: [youtube] abc: Video unavailable');
      expect(parser.lastError, '[youtube] abc: Video unavailable');
    });
  });

  group('errors', () {
    test('maps common yt-dlp failures', () {
      expect(friendlyError('ERROR: Unsupported URL: https://example.com'), contains("isn't supported"));
      expect(friendlyError('ERROR: [youtube] x: Private video. Sign in if you\'ve been granted access'), 'This video is private.');
      expect(friendlyError('ERROR: [Instagram] x: Requested content is not available, rate-limit reached or login required'),
          contains('logged-in'));
      expect(friendlyError("ERROR: [youtube] x: Sign in to confirm you’re not a bot."), contains('not a bot'));
      expect(friendlyError('ERROR: Unable to download webpage: <urlopen error [Errno 7] No address associated with hostname>'),
          contains('Network'));
      expect(friendlyError('ERROR: [youtube] x: Video unavailable'), contains('unavailable'));
    });

    test('falls back to the last ERROR line without the extractor prefix', () {
      expect(friendlyError('WARNING: foo\nERROR: [generic] abc: Something odd happened'), 'Something odd happened');
    });
  });

  group('links', () {
    test('extracts the link from shared text', () {
      expect(extractUrl('Check this https://vm.tiktok.com/ZMabc/ #fyp'), 'https://vm.tiktok.com/ZMabc/');
      expect(extractUrl('https://youtu.be/aqz-KE-bpKQ?si=xyz.'), 'https://youtu.be/aqz-KE-bpKQ?si=xyz');
      expect(extractUrl('(see https://www.instagram.com/reel/abc/)'), 'https://www.instagram.com/reel/abc/');
      expect(extractUrl('no link here'), isNull);
      expect(extractUrl('http://localhost'), isNull);
    });
  });

  group('formatting', () {
    test('bytes, durations and ETAs', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(267891149), '255 MB');
      expect(formatDuration(635), '10:35');
      expect(formatDuration(3725), '1:02:05');
      expect(formatEta(42), '42s left');
      expect(formatEta(125), '3 min left');
    });
  });

  group('persistence', () {
    test('tasks and library items round-trip through JSON', () {
      final task = DownloadTask(
        id: 't1',
        url: 'https://youtu.be/x',
        title: 'Clip',
        spec: const DownloadSpec(kind: MediaKind.audio, audioFormat: AudioFormat.m4a),
        engine: EngineKind.remote,
        createdAt: DateTime(2026, 10, 16),
        status: TaskStatus.failed,
        error: 'boom',
        remoteJobId: 'job9',
      );
      final copy = DownloadTask.fromJson(jsonDecode(jsonEncode(task.toJson())) as Map<String, dynamic>);
      expect(copy.spec, task.spec);
      expect(copy.engine, EngineKind.remote);
      expect(copy.status, TaskStatus.failed);
      expect(copy.remoteJobId, 'job9');

      final item = LibraryItem(
        id: 'i1',
        title: 'Clip',
        sourceUrl: 'https://youtu.be/x',
        kind: MediaKind.video,
        fileName: 'Clip.mp4',
        mime: 'video/mp4',
        sizeBytes: 1234,
        createdAt: DateTime(2026, 10, 16),
        contentUri: 'content://media/external/video/media/5',
      );
      final itemCopy = LibraryItem.fromJson(jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>);
      expect(itemCopy.contentUri, item.contentUri);
      expect(itemCopy.sizeBytes, 1234);
    });
  });
}
