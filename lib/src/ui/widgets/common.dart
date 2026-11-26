import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme.dart';

/// Shrinks a little while pressed, like a physical button.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.96});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// The main call to action: accent fill, a loading spinner and a "done" check.
class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.done = false,
    this.height = 58,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool done;
  final double height;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final enabled = onPressed != null && !loading && !done;
    final Widget content;
    if (loading) {
      content = SizedBox(
        key: const ValueKey('loading'),
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: nx.onAccent),
      );
    } else if (done) {
      content = Icon(Icons.check_rounded, key: const ValueKey('done'), color: nx.onAccent, size: 28)
          .animate()
          .scale(begin: const Offset(0.4, 0.4), curve: Curves.elasticOut, duration: 600.ms);
    } else {
      content = Row(
        key: ValueKey(label),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, color: nx.onAccent, size: 22), const SizedBox(width: 10)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: nx.onAccent, fontSize: 16.5, fontWeight: FontWeight.w800, letterSpacing: -0.2),
            ),
          ),
        ],
      );
    }
    return Pressable(
      onTap: enabled
          ? () {
              HapticFeedback.mediumImpact();
              onPressed!();
            }
          : null,
      child: AnimatedOpacity(
        opacity: onPressed == null && !done ? 0.4 : 1,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: nx.accent, borderRadius: BorderRadius.circular(18)),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(animation), child: child),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Rounded surface used for cards.
class NxCard extends StatelessWidget {
  const NxCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 22});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: nx.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: nx.border),
      ),
      child: child,
    );
  }
}

/// A network or file image with a quiet placeholder; fades in when it has loaded.
class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, this.url, this.file, required this.icon, this.radius = 14});

  final String? url;
  final File? file;
  final IconData icon;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final placeholder = ColoredBox(
      color: nx.field,
      child: Center(child: Icon(icon, color: nx.muted, size: 22)),
    );
    Widget frame(BuildContext context, Widget child, int? frame, bool sync) => sync
        ? child
        : AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            child: child,
          );
    Widget? image;
    if (file != null && file!.existsSync()) {
      image = Image.file(file!, fit: BoxFit.cover, frameBuilder: frame, errorBuilder: (_, _, _) => placeholder);
    } else if (url != null) {
      image = Image.network(url!, fit: BoxFit.cover, frameBuilder: frame, errorBuilder: (_, _, _) => placeholder);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(fit: StackFit.expand, children: [placeholder, ?image]),
    );
  }
}

/// Thin progress line. A known value animates smoothly; null shows a moving sweep.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.color, this.height = 5});

  final double? value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final fill = color ?? nx.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (value == null) {
              return Stack(
                children: [
                  Container(color: nx.field),
                  Container(width: width * 0.3, color: fill)
                      .animate(onPlay: (c) => c.repeat())
                      .moveX(begin: -width * 0.3, end: width, duration: 1100.ms, curve: Curves.easeInOut),
                ],
              );
            }
            return Stack(
              children: [
                Container(color: nx.field),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: value!.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Container(
                    width: width * v,
                    decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(height)),
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

/// Small dark label on top of images (durations).
class ImageTag extends StatelessWidget {
  const ImageTag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key, this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(color: nx.muted, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 1.1),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Container(
                key: ValueKey(count),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: nx.field, borderRadius: BorderRadius.circular(999)),
                child: Text('$count', style: TextStyle(color: nx.text, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Round icon button with a press animation.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 40,
    this.filled = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final bool filled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final button = Pressable(
      scale: 0.88,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: filled ? nx.accent : nx.field, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.5, color: color ?? (filled ? nx.onAccent : nx.text)),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

void showSnack(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
    // Snackbars with an action persist by default since Flutter 3.32; these are just notices.
    persist: false,
    duration: const Duration(seconds: 3),
    action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
  ));
}

/// A sliver list that animates items in and out when [items] changes, matched by [idOf].
class AnimatedSliverItems<T> extends StatefulWidget {
  const AnimatedSliverItems({super.key, required this.items, required this.idOf, required this.itemBuilder});

  final List<T> items;
  final String Function(T item) idOf;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  State<AnimatedSliverItems<T>> createState() => _AnimatedSliverItemsState<T>();
}

class _AnimatedSliverItemsState<T> extends State<AnimatedSliverItems<T>> {
  final _listKey = GlobalKey<SliverAnimatedListState>();
  late List<T> _items = List.of(widget.items);

  @override
  void didUpdateWidget(AnimatedSliverItems<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final list = _listKey.currentState;
    final next = widget.items;
    final nextIds = {for (final item in next) widget.idOf(item)};
    final current = List.of(_items);
    for (var i = current.length - 1; i >= 0; i--) {
      final old = current[i];
      if (!nextIds.contains(widget.idOf(old))) {
        current.removeAt(i);
        list?.removeItem(
          i,
          (context, animation) => _transition(animation, widget.itemBuilder(context, old)),
          duration: const Duration(milliseconds: 320),
        );
      }
    }
    final currentIds = {for (final item in current) widget.idOf(item)};
    for (var i = 0; i < next.length; i++) {
      if (!currentIds.contains(widget.idOf(next[i]))) {
        list?.insertItem(i, duration: const Duration(milliseconds: 420));
      }
    }
    _items = List.of(next);
  }

  Widget _transition(Animation<double> animation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SizeTransition(
      sizeFactor: curved,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(curved),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SliverAnimatedList(
      key: _listKey,
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) =>
          _transition(animation, widget.itemBuilder(context, _items[index])),
    );
  }
}

/// Gray placeholder block with a light sweep, used while a link is being read.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({super.key, this.width, required this.height, this.radius = 10});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: context.nx.field, borderRadius: BorderRadius.circular(radius)),
    );
  }
}
