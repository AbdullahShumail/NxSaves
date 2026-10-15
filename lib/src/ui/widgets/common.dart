import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme.dart';

/// Rounded surface used for every card in the app.
class NxCard extends StatelessWidget {
  const NxCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.highlight = false});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: context.nx.card,
        borderRadius: radius,
        border: Border.all(
          color: highlight ? NxColors.violet.withValues(alpha: 0.6) : context.nx.border,
          width: highlight ? 1.4 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Primary call-to-action with the brand gradient, a press animation and a loading state.
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.height = 56,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedOpacity(
        opacity: widget.onPressed == null ? 0.45 : 1,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            gradient: NxColors.brand,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              if (enabled)
                BoxShadow(
                  color: NxColors.violet.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: enabled ? widget.onPressed : null,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(anim), child: child),
                  ),
                  child: widget.loading
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                        )
                      : Row(
                          key: ValueKey(widget.label),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, color: Colors.white, size: 22),
                              const SizedBox(width: 10),
                            ],
                            Text(
                              widget.label,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app mark: a gradient tile with a download arrow.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: NxColors.brand,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: [BoxShadow(color: NxColors.pink.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Icon(Icons.south_rounded, color: Colors.white, size: size * 0.58),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.icon, this.color, this.filled = false});

  final String label;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? Colors.black.withValues(alpha: 0.62) : c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: filled ? Colors.white : c), const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: filled ? Colors.white : c, height: 1.1),
          ),
        ],
      ),
    );
  }
}

/// Progress bar with the brand gradient; animates value changes and shows a moving shimmer
/// when the value is unknown (null).
class NxProgressBar extends StatelessWidget {
  const NxProgressBar({super.key, required this.value, this.height = 7, this.color});

  final double? value;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final track = context.nx.field;
    final fill = color == null ? NxColors.brand : LinearGradient(colors: [color!, color!]);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (value == null) {
              return Container(color: track)
                  .animate(onPlay: (c) => c.repeat())
                  .shimmer(duration: 1400.ms, colors: [track, NxColors.violet.withValues(alpha: 0.7), track]);
            }
            return Stack(
              children: [
                Container(color: track),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: value!.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Container(
                    width: width * v,
                    decoration: BoxDecoration(gradient: fill, borderRadius: BorderRadius.circular(height)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Network or file thumbnail with a branded placeholder.
class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, this.url, this.file, required this.icon, this.radius = 16, this.aspectRatio});

  final String? url;
  final File? file;
  final IconData icon;
  final double radius;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [NxColors.violet.withValues(alpha: 0.35), NxColors.pink.withValues(alpha: 0.25)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(icon, color: Colors.white.withValues(alpha: 0.85))),
    );
    Widget image = placeholder;
    Widget frame(BuildContext context, Widget child, int? frame, bool sync) => sync
        ? child
        : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 350), child: child);
    if (file != null && file!.existsSync()) {
      image = Image.file(file!, fit: BoxFit.cover, frameBuilder: frame, errorBuilder: (_, _, _) => placeholder);
    } else if (url != null) {
      image = Image.network(url!, fit: BoxFit.cover, frameBuilder: frame, errorBuilder: (_, _, _) => placeholder);
    }
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(fit: StackFit.expand, children: [placeholder, image]),
    );
    return aspectRatio == null ? content : AspectRatio(aspectRatio: aspectRatio!, child: content);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [NxColors.violet.withValues(alpha: 0.22), NxColors.pink.withValues(alpha: 0.16)],
                ),
              ),
              child: Icon(icon, size: 42, color: context.colors.primary),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: -4, end: 4, duration: 1800.ms, curve: Curves.easeInOut),
            const SizedBox(height: 22),
            Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, style: context.text.bodyMedium?.copyWith(color: context.nx.muted), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic),
    );
  }
}

/// Page title block used at the top of each tab.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.headlineMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: context.nx.muted)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Soft brand glow behind the top of a page.
class GlowBackground extends StatelessWidget {
  const GlowBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned(
          top: -160,
          left: -80,
          right: -80,
          height: 380,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    NxColors.violet.withValues(alpha: dark ? 0.30 : 0.16),
                    NxColors.pink.withValues(alpha: dark ? 0.10 : 0.06),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

void showSnack(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    // Snackbars with an action persist by default since Flutter 3.32; these are just notices.
    persist: false,
    duration: const Duration(seconds: 4),
    action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
  ));
}

/// Bottom sheet showing an error message and the raw yt-dlp output behind it.
Future<void> showErrorDetails(BuildContext context, {required String message, String? detail}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What went wrong', style: context.text.titleLarge),
            const SizedBox(height: 10),
            Text(message, style: context.text.bodyLarge),
            if (detail != null && detail.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Details', style: context.text.titleSmall?.copyWith(color: context.nx.muted)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: context.nx.field, borderRadius: BorderRadius.circular(14)),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      detail.trim(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
