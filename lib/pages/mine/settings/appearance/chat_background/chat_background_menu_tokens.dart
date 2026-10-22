import 'package:flutter/material.dart';

abstract final class ChatBackgroundMenuTokens {
  static const dualPaneWidth = 760.0;
  static const previewHeight = 168.0;
  static const bubbleWidth = 190.0;
  static const gridGap = 14.0;
  static const bannerLight = Color(0xFFF0F4FA);
  static const bannerDark = Color(0xFF23262D);
  static const colors = <Color>[
    Color(0xFFF1F1F1),
    Color(0xFFCFECCB),
    Color(0xFFBEDBFF),
    Color(0xFFF9C9D2),
    Color(0xFFFFF3B6),
    Color(0xFFD9B8E8),
  ];
  static const colorNamesZh = ['浅灰', '浅绿', '浅蓝', '浅粉', '浅黄', '浅紫'];
  static const colorNamesEn = [
    'Light gray',
    'Light green',
    'Light blue',
    'Light pink',
    'Light yellow',
    'Light purple'
  ];
  static const background = Color(0xFFEDEDED);
  static const dividerWidth = 0.5;
  static const actionWidth = 80.0;
  static const thumbnailWidth = 384;
  static const titlesZh = [
    '雪山云海',
    '碧海轻浪',
    '晨雾森林',
    '静谧山湖',
    '红岩荒漠',
    '林间瀑布',
    '极光星空',
    '落日晚霞',
    '山野鹿影'
  ];
  static const titlesEn = [
    'Alpine Mountains',
    'Ocean Waves',
    'Misty Forest',
    'Mountain Lake',
    'Desert Mesas',
    'Forest Waterfall',
    'Northern Lights',
    'Sunset Sky',
    'Mountain Meadow'
  ];
  static const options = <String>[
    'asset:assets/images/chat_backgrounds/alpine_lake.webp',
    'asset:assets/images/chat_backgrounds/ocean_cliffs.webp',
    'asset:assets/images/chat_backgrounds/forest.webp',
    'asset:assets/images/chat_backgrounds/mountain_lake.webp',
    'asset:assets/images/chat_backgrounds/desert.webp',
    'asset:assets/images/chat_backgrounds/waterfall.webp',
    'asset:assets/images/chat_backgrounds/aurora.webp',
    'asset:assets/images/chat_backgrounds/sunset.webp',
    'asset:assets/images/chat_backgrounds/meadow.webp',
  ];
}
