// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/pages/chat/telegram_motion.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class SwipeToReply extends StatefulWidget {
  final Widget child;
  final void Function() onReply;
  final bool rightToLeft;

  static const double threshold = 64;

  const SwipeToReply({
    required this.child,
    required this.onReply,
    this.rightToLeft = false,
    super.key,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  // The controller value is the raw finger drag; the bubble moves at
  // `TelegramMotion.swipeFingerDamping` of it - Telegram's rubber band.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: TelegramMotion.swipeSnapBackDuration,
    upperBound: SwipeToReply.threshold / TelegramMotion.swipeFingerDamping,
  );

  bool _thresholdReached = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _direction {
    final ltr = Directionality.of(context) == TextDirection.ltr;
    return ltr != widget.rightToLeft ? 1 : -1;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _controller.value += details.primaryDelta! * _direction;
    final reached = _controller.value >= SwipeToReply.threshold;
    if (reached && !_thresholdReached) HapticFeedback.lightImpact();
    _thresholdReached = reached;
  }

  void _onDragEnd([_]) {
    if (_thresholdReached) widget.onReply();
    _thresholdReached = false;
    _controller.animateTo(
      0,
      duration: TelegramMotion.swipeSnapBackDuration,
      curve: TelegramMotion.swipeSnapBackCurve,
    );
  }

  /// How far the bubble has travelled on screen: damped finger drag.
  double get _offset => _controller.value * TelegramMotion.swipeFingerDamping;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Mouse drags are left to text selection.
      supportedDevices: const {PointerDeviceKind.touch},
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragEnd,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final progress = min(1.0, _controller.value / SwipeToReply.threshold);
          return Stack(
            alignment: _direction > 0 ? .centerLeft : .centerRight,
            children: [
              if (progress > 0)
                Padding(
                  // The reply arrow fades in and grows with the drag.
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Opacity(
                    opacity: progress,
                    child: Transform.scale(
                      scale: 0.5 + progress / 2,
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          // swipe_reply_action_icon = accent blue.
                          color: TelegramPalette.accentBlue,
                        ),
                        padding: const EdgeInsets.all(10.0),
                        child: const Icon(
                          Icons.reply,
                          // White glyph on the accent circle.
                          color: TelegramPalette.dayTextOnBubble,
                        ),
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(_offset * _direction, 0),
                child: child,
              ),
            ],
          );
        },
      ),
    );
  }
}
