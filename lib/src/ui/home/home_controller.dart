import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/errors.dart';
import '../../core/links.dart';
import '../../core/models.dart';
import '../../core/quality.dart';
import '../../engine/local_engine.dart';
import '../../services/app_services.dart';

enum FetchState { idle, loading, loaded, failed }

/// The link being read and the quality picked for it.
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

  /// True when the last error can be fixed in Settings (server address or token).
  bool get errorNeedsSettings => error != null && (error!.contains('Settings') || error!.contains('server'));

  Future<void> fetch(String input) async {
    final link = extractUrl(input);
    if (link == null) {
      url = null;
      _fail("That doesn't look like a link.");
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
        _fail('Live streams can be saved once they have ended.');
        return;
      }
      if (media.isPlaylist && media.entries.isEmpty) {
        _fail('Nothing to download here.');
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
      _fail("Couldn't read this link.", detail: '$e');
    }
  }

  void retry() {
    final link = url;
    if (link != null) fetch(link);
  }

  void _buildOptions() {
    final media = info!;
    final settings = services.settings;
    if (media.isPlaylist) {
      // Above 1080p (and "Best") usually means VP9/AV1, which Photos on iPhone can't take.
      videoOptions = genericVideoOptions(preferCompat: true)
          .where((o) => (o.spec.height ?? 0) <= 1080 && !(Platform.isIOS && o.spec.height == null))
          .toList();
      audioOptions = const [
        QualityOption(spec: DownloadSpec(kind: MediaKind.audio, audioFormat: AudioFormat.mp3), title: 'MP3'),
        QualityOption(spec: DownloadSpec(kind: MediaKind.audio, audioFormat: AudioFormat.m4a), title: 'M4A'),
      ];
    } else {
      var video = buildVideoOptions(media, preferCompat: true);
      // Photos on iPhone can't take VP9/AV1, which is all YouTube has above 1080p.
      if (Platform.isIOS && video.any((o) => o.compatible)) video = video.where((o) => o.compatible).toList();
      videoOptions = video;
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

  /// Adds the link (or every playlist entry) to the downloads and remembers the choice for next
  /// time. Returns how many were added.
  int enqueue() {
    final media = info;
    final option = selected;
    if (media == null || option == null) return 0;
    _remember(option.spec);
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

  void _remember(DownloadSpec spec) {
    final settings = services.settings;
    settings.defaultKind = spec.kind;
    if (spec.kind == MediaKind.audio) {
      settings.defaultAudioFormat = spec.audioFormat;
    } else {
      settings.defaultHeight = spec.height ?? 0;
    }
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
