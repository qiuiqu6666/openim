import 'package:flutter/material.dart';

/// Dimensions measured from the 938 px wide product reference.
abstract final class GroupPersonalizationStyle {
  static const referenceWidth = 938.0;
  static const maxWidth = 600.0;
  static const page = Color(0xFFF7F8FA);
  static const ink = Color(0xFF07132D);
  static const muted = Color(0xFF7E879C);
  static const blue = Color(0xFF008BFF);
  static const blueEnd = Color(0xFF3299FF);
  static const tile = Color(0xFFF4F4FB);
  static const previewBackground =
      'assets/images/group_personalization_diamond_background.png';
  static const previewDarkOverlay = Color(0xD91C293C);
  static const previewStart = Color(0xFFE9F1FF);
  static const previewEnd = Color(0xFFD7E6FF);
  static const palette = <int, String>{
    0xFF008BFF: '蓝色',
    0xFFDC2626: '红色',
    0xFF961ED0: '紫色',
    0xFF00A390: '绿色',
    0xFFEB8415: '橙色',
    0xFFEB3689: '粉色',
    0xFFFFB821: '黄色',
    0xFF0CC3DB: '青色',
  };
  static const iconNames = [
    '机器人',
    '爱心',
    '皇冠',
    '游戏手柄',
    '啤酒',
    '足球',
    '火箭',
    '四叶草',
    '柴犬',
    '钻石',
    '小幽灵',
    '星星',
    '樱花'
  ];
}
