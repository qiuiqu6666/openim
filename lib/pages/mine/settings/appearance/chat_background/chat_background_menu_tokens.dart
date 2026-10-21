import 'package:flutter/material.dart';

abstract final class ChatBackgroundMenuTokens {
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
