import 'package:flutter/foundation.dart';

import '../../core/errors.dart';
import '../../core/links.dart';
import '../../core/models.dart';
import '../../core/quality.dart';
import '../../engine/local_engine.dart';
import '../../services/app_services.dart';

enum FetchState { idle, loading, loaded, failed }

/// State of the Download tab: the link being analyzed and the chosen quality.
class HomeController extends ChangeNotifier {
  HomeController(this.services);

  final AppServices services;

  FetchState state = FetchState.idle;
  String? url;
  MediaInfo? info;
  String? error;
  String? errorDetail;
  MediaKind kind = MediaKind.video;
  List<QualityOption> videoOptions = const [];
  List<QualityOption> audioOptions = const [];
  QualityOption? selected;
  int _seq = 0;

  List<QualityOption> get options => kind == MediaKind.video ? videoOptions : audioOptions;

  Future<void> fetch(String input) async {
    final link = extractUrl(input);
    if (link == null) {
      _fail("That doesn't look like a link. Copy the video's share link and paste it here.");
      return;
    }
    final seq = ++_seq;
    url = link;
    info = null;
    error = null;
    errorDetail = null;
    state = FetchState.loading;
    notifyListeners();

    final engine = services.downloads.currentEngine;
    if (engine is LocalEngine) await engine.cancelInfo();
    try {
      final json = await engine.fetchInfo(link);
      if (seq != _seq) return;
      final media = MediaInfo.fromJson(json, sourceUrl: link);
      if (media.isLive) {
        _fail("This is a live stream (or hasn't started yet). It can be downloaded once it has ended.");
        return;
      }
      if (media.isPlaylist && media.entries.isEmpty) {
        _fail('This playlist or profile has no downloadable videos.');
        return;
      }
      info = media;
      _buildOptions();
      state = FetchState.loaded;
      notifyListeners();
    } on EngineException catch (e) {
      if (seq != _seq || e.canceled) return;
      _fail(e.message, detail: e.detail);
    } catch (e) {
      if (seq != _seq) return;
      _fail('Could not read this link.', detail: '$e');
    }
  }

  void _buildOptions() {
    final media = info!;
    final settings = services.settings;
    if (media.isPlaylist) {
      videoOptions = genericVideoOptions(preferCompat: settings.preferCompat);
      audioOptions = const [
        QualityOption(spec: DownloadSpec(kind: MediaKind.audio, audioFormat: AudioFormat.mp3), title: 'MP3', badge: 'Universal'),
        QualityOption(spec: DownloadSpec(kind: MediaKind.audio, audioFormat: AudioFormat.m4a), title: 'M4A', badge: 'Original'),
      ];
    } else {
      videoOptions = buildVideoOptions(media, preferCompat: settings.preferCompat);
      audioOptions = buildAudioOptions(media);
    }
    final wantsAudio = settings.defaultKind == MediaKind.audio && audioOptions.isNotEmpty;
    kind = wantsAudio || videoOptions.isEmpty ? MediaKind.audio : MediaKind.video;
    _selectDefault();
  }

  void _selectDefault() {
    final settings = services.settings;
    if (kind == MediaKind.video) {
      final height = settings.defaultHeight == 0 ? null : settings.defaultHeight;
      selected = defaultOption(videoOptions, height);
    } else {
      selected = audioOptions.where((o) => o.spec.audioFormat == settings.defaultAudioFormat).firstOrNull ??
          audioOptions.firstOrNull;
    }
  }

  void setKind(MediaKind value) {
    if (kind == value) return;
    kind = value;
    _selectDefault();
    notifyListeners();
  }

  void select(QualityOption option) {
    selected = option;
    notifyListeners();
  }

  /// Adds the analyzed link (or every playlist entry) to the queue. Returns how many were added.
  int enqueue() {
    final media = info;
    final option = selected;
    if (media == null || option == null) return 0;
    final downloads = services.downloads;
    if (media.isPlaylist) {
      for (final entry in media.entries) {
        downloads.enqueue(
          url: entry.url,
          title: entry.title,
          spec: option.spec,
          thumbnail: entry.thumbnail,
          uploader: entry.uploader ?? media.uploader,
          duration: entry.duration,
          extractor: media.extractor,
        );
      }
      return media.entries.length;
    }
    downloads.enqueue(
      url: media.url,
      title: media.title,
      spec: option.spec,
      thumbnail: media.thumbnail,
      uploader: media.uploader,
      duration: media.duration,
      extractor: media.extractor,
    );
    return 1;
  }

  void reset() {
    _seq++;
    state = FetchState.idle;
    url = null;
    info = null;
    error = null;
    errorDetail = null;
    selected = null;
    notifyListeners();
  }

  void _fail(String message, {String? detail}) {
    state = FetchState.failed;
    error = message;
    errorDetail = detail;
    notifyListeners();
  }
}
