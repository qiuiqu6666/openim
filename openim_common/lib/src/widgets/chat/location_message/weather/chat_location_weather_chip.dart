import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../res/app_tokens.dart';
import '../detail/chat_location_detail_chrome.dart';
import '../detail/chat_location_detail_labels.dart';
import '../detail/chat_location_detail_tokens.dart';
import 'chat_location_weather_source.dart';

class ChatLocationWeatherChip extends StatefulWidget {
  const ChatLocationWeatherChip({super.key, required this.point, this.source});
  final LatLng point;
  final ChatLocationWeatherSource? source;
  @override
  State<ChatLocationWeatherChip> createState() =>
      _ChatLocationWeatherChipState();
}

class _ChatLocationWeatherChipState extends State<ChatLocationWeatherChip> {
  ChatLocationWeather? _weather;
  bool _loading = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ChatLocationWeatherChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.point != oldWidget.point || widget.source != oldWidget.source) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _weather = null;
    });
    try {
      final weather = await (widget.source ?? ChatLocationWeatherSource.shared)
          .load(widget.point);
      if (mounted && generation == _generation) {
        setState(() => _weather = weather);
      }
    } catch (_) {
      /* Unavailable is explicit; never substitute sample weather. */
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  (IconData, String) _condition(ChatLocationDetailLabels labels) {
    final symbol = _weather!.symbol;
    if (symbol.contains('thunder')) {
      return (
        Icons.thunderstorm_outlined,
        labels.text('雷雨', '雷雨', 'Thunderstorms')
      );
    }
    if (symbol.contains('snow') || symbol.contains('sleet')) {
      return (Icons.ac_unit, labels.text('降雪／雨夹雪', '降雪／雨夾雪', 'Snow / sleet'));
    }
    if (symbol.contains('rain')) {
      return (Icons.water_drop_outlined, labels.text('有雨', '有雨', 'Rain'));
    }
    if (symbol.contains('fog')) {
      return (Icons.blur_on, labels.text('雾', '霧', 'Fog'));
    }
    if (symbol.startsWith('clearsky')) {
      return (
        symbol.endsWith('night')
            ? Icons.nightlight_outlined
            : Icons.wb_sunny_outlined,
        labels.text('晴', '晴', 'Clear')
      );
    }
    if (symbol.contains('cloudy') || symbol.startsWith('fair')) {
      return (Icons.cloud_outlined, labels.text('多云', '多雲', 'Cloudy'));
    }
    return (Icons.thermostat, labels.text('天气', '天氣', 'Weather'));
  }

  @override
  Widget build(BuildContext context) {
    final labels = ChatLocationDetailLabels.of(context);
    final weather = _weather;
    final text = _loading
        ? labels.text('天气加载中…', '天氣載入中…', 'Loading weather…')
        : weather == null
            ? labels.text(
                '天气暂不可用 · 重试', '天氣暫不可用 · 重試', 'Weather unavailable · Retry')
            : '${weather.temperature.round()}°C';
    final condition = weather == null ? null : _condition(labels);
    return ChatLocationDetailSurface(
        child: TextButton(
            key: const ValueKey('chat-location-weather'),
            onPressed: _loading
                ? null
                : weather == null
                    ? _load
                    : null,
            style: TextButton.styleFrom(
                minimumSize: const Size(ChatLocationDetailTokens.controlSize,
                    ChatLocationDetailTokens.controlSize),
                disabledForegroundColor: AppTokens.textPrimary(
                    dark: Theme.of(context).brightness == Brightness.dark),
                foregroundColor: AppTokens.textPrimary(
                    dark: Theme.of(context).brightness == Brightness.dark),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s4, vertical: AppTokens.s3)),
            child: Tooltip(
                message: weather == null
                    ? text
                    : '${labels.text('分享地点天气', '分享地點天氣', 'Weather at shared location')} · ${condition!.$2} · MET Norway · CC BY 4.0',
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(condition?.$1 ?? Icons.cloud_outlined,
                      size: AppTokens.s6),
                  const SizedBox(width: AppTokens.s3),
                  Flexible(
                      child: Text(text,
                          maxLines: 2, overflow: TextOverflow.ellipsis)),
                ]))));
  }
}
