import 'package:flutter/material.dart';

/// Single-line text that auto-scrolls (marquee) when it overflows.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double scrollPixels;
  final Duration duration;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.scrollPixels = 24,
    this.duration = const Duration(seconds: 6),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final ScrollController _controller;
  late final AnimationController _anim;
  double? _textWidth;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _anim = AnimationController(vsync: this, duration: widget.duration);
    _anim.addListener(() {
      final end = _textWidth ?? 0;
      if (end <= 0 || !_controller.hasClients) return;
      final target = end * Curves.easeInOut.transform(_anim.value);
      _controller.jumpTo(target);
    });
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _textWidth = null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _sync(double viewport) {
    _textWidth ??= _measure();
    final overflow = (_textWidth ?? 0) - viewport - widget.scrollPixels;
    final shouldScroll = overflow > 0;
    if (shouldScroll && !_anim.isAnimating) {
      _anim.repeat();
    } else if (!shouldScroll && _anim.isAnimating) {
      _anim.stop();
      _controller.jumpTo(0);
      _anim.reset();
    }
  }

  double _measure() {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sync(constraints.maxWidth);
        });
        return SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            style: widget.style,
          ),
        );
      },
    );
  }
}