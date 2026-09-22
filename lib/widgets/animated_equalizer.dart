import 'dart:io';
import 'package:flutter/material.dart';

class AnimatedEqualizer extends StatefulWidget {
  const AnimatedEqualizer({
    super.key,
    required this.isPlaying,
    this.color,
    this.size = 18,
  });

  final bool isPlaying;
  final Color? color;
  final double size;

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final bool _isTest = Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    if (widget.isPlaying && !_isTest) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 0.6;
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying && !_isTest) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = widget.isPlaying ? 0.6 : 0.2;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barColor = widget.color ?? Theme.of(context).colorScheme.primary;
    final barWidth = widget.size / 6;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final val = _controller.value;
        // 3 bars with staggered phase
        final h1 = widget.isPlaying ? (0.3 + 0.7 * val).clamp(0.2, 1.0) : 0.3;
        final h2 = widget.isPlaying ? (0.2 + 0.8 * ((val + 0.33) % 1.0)).clamp(0.2, 1.0) : 0.5;
        final h3 = widget.isPlaying ? (0.4 + 0.6 * ((val + 0.66) % 1.0)).clamp(0.2, 1.0) : 0.25;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBar(h1, barWidth, barColor),
              _buildBar(h2, barWidth, barColor),
              _buildBar(h3, barWidth, barColor),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBar(double heightFactor, double width, Color color) {
    return Container(
      width: width,
      height: widget.size * heightFactor,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(width / 2),
      ),
    );
  }
}
