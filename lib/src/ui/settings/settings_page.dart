import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../services/app_services.dart';
import '../theme.dart';
import '../widgets/common.dart';

const kAppVersion = '1.1.0';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final settings = services.settings;
    final remote = settings.engine == EngineKind.remote;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Row(
                  children: [
                    RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      size: 42,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 14),
                    Text('Settings', style: context.text.headlineSmall?.copyWith(fontSize: 26)),
                  ],
                ),
                const SizedBox(height: 26),
                if (remote) _ServerCard(services: services),
                if (services.android != null && !remote) _CookiesCard(services: services),
                const SizedBox(height: 28),
                Center(
                  child: Text(
                    'NxSaves $kAppVersion',
                    style: TextStyle(color: context.nx.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ]
                  .animate(interval: 60.ms)
                  .fadeIn(duration: 350.ms)
                  .slideY(begin: 0.12, curve: Curves.easeOutCubic),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerCard extends StatefulWidget {
  const _ServerCard({required this.services});

  final AppServices services;

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  late final _url = TextEditingController(text: widget.services.settings.serverUrl);
  late final _token = TextEditingController(text: widget.services.settings.serverToken);
  bool _showToken = false;
  bool _testing = false;
  bool? _ok;
  String? _message;

  @override
  void initState() {
    super.initState();
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    final settings = widget.services.settings;
    settings.serverUrl = _url.text;
    settings.serverToken = _token.text;
    setState(() {
      _testing = true;
      _ok = null;
      _message = null;
    });
    try {
      final health = await widget.services.remote.health();
      _ok = health['ffmpeg'] != false;
      _message = _ok! ? 'Connected' : "Connected, but the server isn't fully set up";
    } on EngineException catch (e) {
      _ok = false;
      _message = e.message;
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    return NxCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Server', style: context.text.titleMedium),
          const SizedBox(height: 14),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Address',
              prefixIcon: Icon(Icons.public_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _token,
            obscureText: !_showToken,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _connect(),
            decoration: InputDecoration(
              hintText: 'Token',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                icon: Icon(_showToken ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: nx.muted),
                onPressed: () => setState(() => _showToken = !_showToken),
              ),
            ),
          ),
          const SizedBox(height: 16),
          AccentButton(
            label: 'Connect',
            icon: Icons.bolt_rounded,
            height: 54,
            loading: _testing,
            onPressed: _url.text.trim().isEmpty ? null : _connect,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: _message == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      children: [
                        Icon(
                          _ok == true ? Icons.check_circle_rounded : Icons.error_rounded,
                          color: _ok == true ? NxColors.green : NxColors.red,
                          size: 20,
                        ).animate(key: ValueKey(_message)).scale(curve: Curves.elasticOut, duration: 600.ms),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _message!,
                            style: TextStyle(fontWeight: FontWeight.w700, color: _ok == true ? NxColors.green : nx.text),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CookiesCard extends StatefulWidget {
  const _CookiesCard({required this.services});

  final AppServices services;

  @override
  State<_CookiesCard> createState() => _CookiesCardState();
}

class _CookiesCardState extends State<_CookiesCard> {
  String? _message;

  Future<void> _import() async {
    try {
      final path = await widget.services.android!.importCookies();
      if (path != null) {
        widget.services.settings.cookiesPath = path;
        _message = null;
      }
    } catch (e) {
      _message = e is Exception ? "That file didn't work. Use a cookies.txt file." : '$e';
    }
    if (mounted) setState(() {});
  }

  void _remove() {
    final path = widget.services.settings.cookiesPath;
    if (path != null) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    widget.services.settings.cookiesPath = null;
    setState(() => _message = null);
  }

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final settings = widget.services.settings;
    final has = settings.cookiesPath != null;
    return NxCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sign-in cookies', style: context.text.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      has ? 'In use' : 'For posts that need an account',
                      style: TextStyle(color: has ? NxColors.green : nx.muted, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: has ? _remove : _import, child: Text(has ? 'Remove' : 'Add')),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Text(_message!, style: const TextStyle(color: NxColors.red, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
