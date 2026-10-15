import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../engine/local_engine.dart';
import '../../services/app_services.dart';
import '../theme.dart';
import '../widgets/common.dart';

const kAppVersion = '1.0.0';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final settings = services.settings;
    return GlowBackground(
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            final remote = settings.engine == EngineKind.remote;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                const PageHeader(title: 'Settings'),
                _Section(
                  title: 'Download engine',
                  icon: Icons.bolt_rounded,
                  children: [
                    if (settings.canRunLocally) ...[
                      SegmentedButton<EngineKind>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: EngineKind.local, icon: Icon(Icons.phone_android_rounded), label: Text('On this phone')),
                          ButtonSegment(value: EngineKind.remote, icon: Icon(Icons.dns_rounded), label: Text('My server')),
                        ],
                        selected: {settings.engine},
                        onSelectionChanged: (s) => settings.engine = s.first,
                      ),
                      const SizedBox(height: 10),
                      _Hint(
                        remote
                            ? 'Links are processed by your NxSaves server and the finished file is sent to this phone.'
                            : 'yt-dlp, Python and ffmpeg run right on this phone. No server needed.',
                      ),
                    ] else
                      const _Hint(
                        'iOS doesn’t let apps start helper programs like ffmpeg, or update their own code, '
                        'and yt-dlp needs both. So on iPhone, NxSaves sends links to your own NxSaves server '
                        '(see the README), which downloads and merges the file and sends it back to your phone.',
                      ),
                  ],
                ),
                if (remote || !settings.canRunLocally) _ServerSection(services: services),
                _Section(
                  title: 'Downloads',
                  icon: Icons.download_rounded,
                  children: [
                    _Row(
                      label: 'Default quality',
                      trailing: DropdownButton<String>(
                        value: settings.defaultKind == MediaKind.audio
                            ? 'audio-${settings.defaultAudioFormat.name}'
                            : 'video-${settings.defaultHeight}',
                        underline: const SizedBox.shrink(),
                        borderRadius: BorderRadius.circular(16),
                        items: const [
                          DropdownMenuItem(value: 'video-0', child: Text('Best available')),
                          DropdownMenuItem(value: 'video-2160', child: Text('Up to 4K')),
                          DropdownMenuItem(value: 'video-1440', child: Text('Up to 1440p')),
                          DropdownMenuItem(value: 'video-1080', child: Text('Up to 1080p')),
                          DropdownMenuItem(value: 'video-720', child: Text('Up to 720p')),
                          DropdownMenuItem(value: 'video-480', child: Text('Up to 480p')),
                          DropdownMenuItem(value: 'audio-mp3', child: Text('Audio · MP3')),
                          DropdownMenuItem(value: 'audio-m4a', child: Text('Audio · M4A')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          final [kind, rest] = value.split('-');
                          if (kind == 'audio') {
                            settings.defaultKind = MediaKind.audio;
                            settings.defaultAudioFormat = enumByName(AudioFormat.values, rest, AudioFormat.mp3);
                          } else {
                            settings.defaultKind = MediaKind.video;
                            settings.defaultHeight = int.parse(rest);
                          }
                        },
                      ),
                    ),
                    _SwitchRow(
                      label: 'Prefer compatible formats',
                      description: 'H.264 + AAC in MP4 whenever available, so videos play in every gallery, '
                          'iOS Photos and messaging apps. Turn off for VP9/AV1 (smaller, but less compatible).',
                      value: settings.preferCompat,
                      onChanged: (v) => settings.preferCompat = v,
                    ),
                    _Row(
                      label: 'Downloads at once',
                      trailing: SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        segments: const [
                          ButtonSegment(value: 1, label: Text('1')),
                          ButtonSegment(value: 2, label: Text('2')),
                          ButtonSegment(value: 3, label: Text('3')),
                        ],
                        selected: {settings.maxConcurrent},
                        onSelectionChanged: (s) => settings.maxConcurrent = s.first,
                      ),
                    ),
                    if (Platform.isIOS)
                      _SwitchRow(
                        label: 'Also save videos to Photos',
                        description: 'Every finished video is kept in Files › NxSaves and, with this on, added to Photos.',
                        value: settings.autoSaveToPhotos,
                        onChanged: (v) => settings.autoSaveToPhotos = v,
                      ),
                  ],
                ),
                if (services.local != null && !remote) _YtDlpSection(services: services),
                _Section(
                  title: 'Where files go',
                  icon: Icons.folder_rounded,
                  children: [
                    _Hint(
                      Platform.isIOS
                          ? 'Files app › On My iPhone › NxSaves (Videos, Audio). Videos are also added to Photos '
                              'when enabled above.'
                          : 'Videos: Movies/NxSaves · Audio: Music/NxSaves. They show up in your gallery and music '
                              'apps and stay there if you uninstall NxSaves.',
                    ),
                  ],
                ),
                _Section(
                  title: 'About',
                  icon: Icons.info_outline_rounded,
                  children: [
                    _Hint(
                      'NxSaves $kAppVersion · private build for personal use. Downloads are powered by yt-dlp '
                      '(github.com/yt-dlp/yt-dlp) and ffmpeg.',
                    ),
                    const SizedBox(height: 8),
                    const _Hint(
                      'Only download content you own or have permission to save. Respect copyright and each '
                      'site’s terms of service. NxSaves does not bypass DRM.',
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ServerSection extends StatefulWidget {
  const _ServerSection({required this.services});

  final AppServices services;

  @override
  State<_ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends State<_ServerSection> {
  late final _url = TextEditingController(text: widget.services.settings.serverUrl);
  late final _token = TextEditingController(text: widget.services.settings.serverToken);
  bool _showToken = false;
  bool _testing = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final health = await widget.services.remote.health();
      final js = health['jsRuntime'];
      final parts = [
        'Connected',
        if (health['ytdlp'] != null) 'yt-dlp ${health['ytdlp']}',
        health['ffmpeg'] == true ? 'ffmpeg ✓' : 'ffmpeg missing!',
        js == null ? 'no JS runtime (YouTube limited)' : 'JS: $js',
      ];
      _ok = health['ffmpeg'] == true;
      _result = parts.join(' · ');
    } on EngineException catch (e) {
      _ok = false;
      _result = e.message;
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.services.settings;
    return _Section(
      title: 'NxSaves server',
      icon: Icons.dns_rounded,
      children: [
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Server address',
            hintText: 'http://100.64.0.5:8765',
            prefixIcon: Icon(Icons.public_rounded),
          ),
          onChanged: (v) => settings.serverUrl = v,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _token,
          obscureText: !_showToken,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Access token',
            prefixIcon: const Icon(Icons.key_rounded),
            suffixIcon: IconButton(
              icon: Icon(_showToken ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              onPressed: () => setState(() => _showToken = !_showToken),
            ),
          ),
          onChanged: (v) => settings.serverToken = v,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: _testing || _url.text.trim().isEmpty ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering_rounded),
              label: const Text('Test connection'),
            ),
          ],
        ),
        if (_result != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  size: 18, color: _ok ? NxColors.teal : NxColors.red),
              const SizedBox(width: 8),
              Expanded(child: Text(_result!, style: context.text.bodySmall)),
            ],
          ),
        ],
        const SizedBox(height: 10),
        const _Hint(
          'Run server/nxsaves_server.py on a computer that stays on. Reach it from anywhere with Tailscale '
          '(recommended) or a Cloudflare Tunnel. The token is printed when the server starts.',
        ),
      ],
    );
  }
}

class _YtDlpSection extends StatefulWidget {
  const _YtDlpSection({required this.services});

  final AppServices services;

  @override
  State<_YtDlpSection> createState() => _YtDlpSectionState();
}

class _YtDlpSectionState extends State<_YtDlpSection> {
  String? _message;

  Future<void> _update() async {
    final downloads = widget.services.downloads;
    if (downloads.tasks.any((t) => t.status == TaskStatus.running && t.engine == EngineKind.local)) {
      setState(() => _message = 'Wait for running downloads to finish, then update.');
      return;
    }
    setState(() => _message = null);
    try {
      final result = await widget.services.local!.update();
      _message = result == 'updated' ? 'Updated to the latest yt-dlp.' : 'yt-dlp is already up to date.';
    } on EngineException catch (e) {
      _message = 'Update failed: ${e.message}';
    }
    if (mounted) setState(() {});
  }

  Future<void> _importCookies() async {
    final android = widget.services.android!;
    try {
      final path = await android.importCookies();
      if (path != null) {
        widget.services.settings.cookiesPath = path;
        _message = 'Cookies imported. yt-dlp will use them for every download.';
      }
    } catch (e) {
      _message = 'Could not import cookies: $e';
    }
    if (mounted) setState(() {});
  }

  void _removeCookies() {
    final path = widget.services.settings.cookiesPath;
    if (path != null) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    widget.services.settings.cookiesPath = null;
    setState(() => _message = 'Cookies removed.');
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.services.settings;
    final engine = widget.services.local!;
    return _Section(
      title: 'yt-dlp on this phone',
      icon: Icons.memory_rounded,
      children: [
        ValueListenableBuilder(
          valueListenable: engine.status,
          builder: (context, status, _) {
            final busy = status.state == LocalEngineState.updating || status.state == LocalEngineState.starting;
            final last = settings.lastUpdateCheck;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Row(
                  label: switch (status.state) {
                    LocalEngineState.starting => 'Starting…',
                    LocalEngineState.updating => 'Updating…',
                    LocalEngineState.failed => 'Failed to start',
                    LocalEngineState.ready => 'Version ${status.version ?? 'unknown'}',
                  },
                  description: status.state == LocalEngineState.failed
                      ? status.message
                      : last == null
                          ? 'Never checked for updates'
                          : 'Last checked ${formatDate(last).toLowerCase()}',
                  trailing: FilledButton.tonal(
                    onPressed: busy || status.state == LocalEngineState.failed ? null : _update,
                    child: busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Update'),
                  ),
                ),
              ],
            );
          },
        ),
        _Row(
          label: 'Update channel',
          description: 'Nightly gets site fixes days earlier.',
          trailing: SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 'stable', label: Text('Stable')),
              ButtonSegment(value: 'nightly', label: Text('Nightly')),
            ],
            selected: {settings.updateChannel},
            onSelectionChanged: (s) => settings.updateChannel = s.first,
          ),
        ),
        _SwitchRow(
          label: 'Update automatically',
          description: 'Checks once a day when the app starts. Sites change often; updates keep downloads working.',
          value: settings.autoUpdateYtDlp,
          onChanged: (v) => settings.autoUpdateYtDlp = v,
        ),
        _Row(
          label: 'Cookies',
          description: settings.cookiesPath == null
              ? 'Optional. Some Instagram, Facebook and age-restricted YouTube posts need a logged-in '
                  'cookies.txt (Netscape format) exported from your browser.'
              : 'A cookies.txt is in use for all downloads.',
          trailing: settings.cookiesPath == null
              ? TextButton(onPressed: _importCookies, child: const Text('Import'))
              : TextButton(onPressed: _removeCookies, child: const Text('Remove')),
        ),
        if (_message != null) _Hint(_message!),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: NxCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: context.colors.primary),
                const SizedBox(width: 8),
                Text(title, style: context.text.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, this.description, required this.trailing});

  final String label;
  final String? description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                if (description != null)
                  Text(description!, style: context.text.bodySmall?.copyWith(color: context.nx.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.label, required this.description, required this.value, required this.onChanged});

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) =>
      _Row(label: label, description: description, trailing: Switch(value: value, onChanged: onChanged));
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: context.text.bodySmall?.copyWith(color: context.nx.muted, height: 1.4));
}
