import 'package:flutter/material.dart';

/// Optional text-message presentation. SDK data, gestures and message ownership
/// stay with the existing chat item; unconfigured chats keep their usual layout.
class ChatTextBubbleStyle {
  const ChatTextBubbleStyle({
    required this.incomingTextStyle,
    required this.outgoingTextStyle,
    required this.incomingMetadataStyle,
    required this.outgoingMetadataStyle,
    required this.incomingBackground,
    required this.outgoingBackground,
    required this.incomingRadius,
    required this.outgoingRadius,
    required this.maxBubbleWidth,
    required this.timelineTextStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.rowMargin = const EdgeInsets.only(bottom: 12),
    this.incomingRowPadding = const EdgeInsets.only(left: 16),
    this.outgoingRowPadding = const EdgeInsets.only(right: 16),
    this.timelineMargin = const EdgeInsets.symmetric(vertical: 8),
    this.avatarSize = 40,
    this.avatarGap = 10,
    this.avatarTextStyle,
    this.avatarTextScaler,
    this.showReadStatus = false,
  });

  final TextStyle incomingTextStyle;
  final TextStyle outgoingTextStyle;
  final TextStyle incomingMetadataStyle;
  final TextStyle outgoingMetadataStyle;
  final Color incomingBackground;
  final Color outgoingBackground;
  final BorderRadius incomingRadius;
  final BorderRadius outgoingRadius;

  /// Overall background width, including horizontal padding and border.
  final double maxBubbleWidth;
  final EdgeInsets padding;
  final EdgeInsets rowMargin;
  final EdgeInsets incomingRowPadding;
  final EdgeInsets outgoingRowPadding;
  final EdgeInsets timelineMargin;
  final TextStyle timelineTextStyle;
  final double avatarSize;
  final double avatarGap;
  final TextStyle? avatarTextStyle;
  final TextScaler? avatarTextScaler;
  final bool showReadStatus;

  TextStyle textStyle(bool outgoing) =>
      outgoing ? outgoingTextStyle : incomingTextStyle;
  TextStyle metadataStyle(bool outgoing) =>
      outgoing ? outgoingMetadataStyle : incomingMetadataStyle;
  Color background(bool outgoing) =>
      outgoing ? outgoingBackground : incomingBackground;
  BorderRadius radius(bool outgoing) =>
      outgoing ? outgoingRadius : incomingRadius;
  EdgeInsets rowPadding(bool outgoing) =>
      outgoing ? outgoingRowPadding : incomingRowPadding;
}
