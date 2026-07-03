import 'dart:async';
import 'package:flutter/material.dart';

/// Left-aligned text that scrolls horizontally ("marquee") when it is too wide
/// to fit its available width. When it fits, it renders as a plain static Text.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double velocity; // pixels per second
  final Duration pauseAtEnds;
  final double gap; // space between the repeated text when scrolling
  final TextAlign textAlign; // alignment used when the text fits (no scroll)

  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.velocity = 40,
    this.pauseAtEnds = const Duration(seconds: 1),
    this.gap = 48,
    this.textAlign = TextAlign.left,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final _controller = ScrollController();
  Timer? _timer;
  bool _scheduled = false;

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) {
      _timer?.cancel();
      _scheduled = false;
      if (_controller.hasClients) _controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startScrolling() async {
    if (!mounted || !_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    if (max <= 0) return;
    await Future.delayed(widget.pauseAtEnds);
    while (mounted && _controller.hasClients) {
      final distance = _controller.position.maxScrollExtent;
      final duration =
          Duration(milliseconds: (distance / widget.velocity * 1000).round());
      await _controller.animateTo(distance,
          duration: duration, curve: Curves.linear);
      if (!mounted || !_controller.hasClients) break;
      await Future.delayed(widget.pauseAtEnds);
      if (!mounted || !_controller.hasClients) break;
      _controller.jumpTo(0);
      await Future.delayed(widget.pauseAtEnds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final overflows = tp.width > constraints.maxWidth;

        if (!overflows) {
          return SizedBox(
            width: double.infinity,
            child: Text(
              widget.text,
              style: style,
              maxLines: 1,
              textAlign: widget.textAlign,
              overflow: TextOverflow.clip,
            ),
          );
        }

        if (!_scheduled) {
          _scheduled = true;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _startScrolling());
        }

        return ClipRect(
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              children: [
                Text(widget.text, style: style, maxLines: 1),
                SizedBox(width: widget.gap),
                Text(widget.text, style: style, maxLines: 1),
              ],
            ),
          ),
        );
      },
    );
  }
}
