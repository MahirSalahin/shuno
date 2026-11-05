import 'dart:async';

import 'package:flutter/material.dart';

/// A widget that displays scrolling text horizontally when the content overflows
/// its available width, mimicking the Spotify title marquee experience.
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.velocity = 32.0,
    this.pauseDuration = const Duration(milliseconds: 1600),
  });

  final String text;
  final TextStyle? style;
  final double velocity;
  final Duration pauseDuration;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrollCycle());
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _stopScroll();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScrollCycle());
    }
  }

  void _stopScroll() {
    _timer?.cancel();
    _timer = null;
  }

  void _startScrollCycle() {
    if (_isDisposed || !mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    _stopScroll();

    // Pause at the start so the user can read the beginning
    _timer = Timer(widget.pauseDuration, () async {
      if (_isDisposed || !mounted || !_scrollController.hasClients) return;
      final currentMax = _scrollController.position.maxScrollExtent;
      if (currentMax <= 0) return;

      final scrollTimeMs = ((currentMax / widget.velocity) * 1000).toInt();

      try {
        await _scrollController.animateTo(
          currentMax,
          duration: Duration(milliseconds: scrollTimeMs.clamp(500, 15000)),
          curve: Curves.easeInOut,
        );
      } catch (_) {
        return;
      }

      if (_isDisposed || !mounted || !_scrollController.hasClients) return;

      // Pause at the end before returning to start
      _timer = Timer(widget.pauseDuration, () async {
        if (_isDisposed || !mounted || !_scrollController.hasClients) return;

        try {
          await _scrollController.animateTo(
            0.0,
            duration: Duration(
              milliseconds: (scrollTimeMs * 0.7).toInt().clamp(400, 10000),
            ),
            curve: Curves.easeInOut,
          );
        } catch (_) {
          return;
        }

        if (_isDisposed || !mounted) return;
        _startScrollCycle();
      });
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stopScroll();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure whether the text fits within the available width
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: double.infinity);

        final overflows = textPainter.width > constraints.maxWidth;

        if (!overflows) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        return ShaderMask(
          shaderCallback: (Rect bounds) {
            return const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.94, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Text(
              widget.text,
              maxLines: 1,
              softWrap: false,
              style: widget.style,
            ),
          ),
        );
      },
    );
  }
}

