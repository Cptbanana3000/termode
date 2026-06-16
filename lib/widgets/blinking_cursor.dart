import 'dart:async';
import 'package:flutter/material.dart';

class BlinkingCursor extends StatefulWidget {
  final Color color;
  final String style; // 'block', 'bar', 'underline'
  final bool blink;
  final double fontSize;

  const BlinkingCursor({
    super.key,
    required this.color,
    required this.style,
    required this.blink,
    required this.fontSize,
  });

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(BlinkingCursor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.blink != oldWidget.blink) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.blink) {
      _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (mounted) {
          setState(() {
            _visible = !_visible;
          });
        }
      });
    } else {
      setState(() {
        _visible = true;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.style == 'block' ? widget.fontSize * 0.6 : 2.0;
    if (!_visible) {
      return SizedBox(
        width: widget.style == 'underline' ? widget.fontSize * 0.6 : width,
        height: widget.fontSize,
      );
    }

    switch (widget.style) {
      case 'block':
        return Container(
          width: widget.fontSize * 0.6,
          height: widget.fontSize,
          color: widget.color,
        );
      case 'underline':
        return Container(
          width: widget.fontSize * 0.6,
          height: widget.fontSize,
          alignment: Alignment.bottomCenter,
          child: Container(
            width: widget.fontSize * 0.6,
            height: 2.0,
            color: widget.color,
          ),
        );
      case 'bar':
      default:
        return Container(
          width: 2.0,
          height: widget.fontSize,
          color: widget.color,
        );
    }
  }
}
