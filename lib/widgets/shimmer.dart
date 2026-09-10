import 'package:flutter/material.dart';

/// A shimmering skeleton box used while API data is loading.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double? height;
  final double radius;
  final bool circle;

  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.radius = 8,
    this.circle = false,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = bounds.width * (_controller.value * 2 - 1);
            return const LinearGradient(
              colors: [Color(0xFF242424), Color(0xFF414141), Color(0xFF242424)],
              stops: [0.35, 0.5, 0.65],
            ).createShader(
              Rect.fromLTWH(
                  dx - bounds.width / 2, 0, bounds.width, bounds.height),
            );
          },
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius:
                  widget.circle ? null : BorderRadius.circular(widget.radius),
            ),
          ),
        );
      },
    );
  }
}