import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_text_field/extended_text_field.dart'
    show ExtendedRenderEditable;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_composer_palette.dart';

import 'unicode_samples.dart';

/// Standalone native-font probe. It never initializes OpenIM or sends messages.
/// Run in a separate application ID; see README.md before installing it.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('UNICODE_NATIVE_PROBE_ERROR ${details.exceptionAsString()}');
  };
  runApp(const UnicodeNativeProbe());
}

class UnicodeNativeProbe extends StatefulWidget {
  const UnicodeNativeProbe({super.key});

  @override
  State<UnicodeNativeProbe> createState() => _UnicodeNativeProbeState();
}

class _UnicodeNativeProbeState extends State<UnicodeNativeProbe> {
  final _input = TextEditingController();
  final _inputKey = GlobalKey();
  final _rawKey = GlobalKey();
  final _commonKey = GlobalKey();
  final _matchKey = GlobalKey();
  final _markdownKey = GlobalKey();
  final _captureKey = GlobalKey();
  int _index = const int.fromEnvironment('UNICODE_PROBE_SAMPLE')
      .clamp(0, unicodeSamples.length - 1)
      .toInt();
  bool _dark = const bool.fromEnvironment('UNICODE_PROBE_DARK');
  bool _validationQueued = false;
  String? _matchVisible;
  String? _markdownSource;
  Map<String, bool> _checks = const {};

  @override
  void initState() {
    super.initState();
    _setInput(unicodeSamples[_index].text);
    _input.addListener(_inputChanged);
    _queueValidation();
    if (const bool.fromEnvironment('UNICODE_PROBE_AUTORUN')) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(_runBatch()));
    }
  }

  @override
  void dispose() {
    _input.removeListener(_inputChanged);
    _input.dispose();
    super.dispose();
  }

  void _inputChanged() {
    if (!mounted) return;
    setState(() {});
    _queueValidation();
  }

  void _setInput(String raw) {
    _input.value = TextEditingValue(
      text: raw,
      selection: TextSelection.collapsed(offset: raw.length),
    );
  }

  void _selectSample(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _index = index;
      _checks = const {};
    });
    _setInput(unicodeSamples[index].text);
    _queueValidation();
  }

  void _queueValidation() {
    if (_validationQueued) return;
    _validationQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validationQueued = false;
      if (mounted) _validate();
    });
  }

  // Escape only Markdown syntax in a display-only wrapper. The original input,
  // fixtures and code units are never rewritten. A/Z keep leading whitespace
  // combining clusters away from Markdown's paragraph/strong delimiters.
  String _markdown(String raw) {
    final literal = raw.replaceAllMapped(
        RegExp(r'[\\`*_{}\[\]()#+\-.!<>~|]'), (match) => '\\${match[0]}');
    return '**A${literal}Z**';
  }

  String? _renderedText(GlobalKey key, {bool editable = false}) {
    final context = key.currentContext;
    if (context is! Element) return null;
    final runs = <String>[];
    void visit(Element element) {
      if (element is RenderObjectElement) {
        final renderObject = element.renderObject;
        // extended_text_field owns a copied editable implementation. Its
        // renderer is exported by the package, not a Flutter RenderEditable.
        if (editable && renderObject is ExtendedRenderEditable) {
          runs.add(renderObject.text?.toPlainText() ?? '');
        } else if (editable && renderObject is RenderEditable) {
          runs.add(renderObject.text?.toPlainText() ?? '');
        } else if (!editable && renderObject is RenderParagraph) {
          runs.add(renderObject.text.toPlainText());
        }
      }
      element.visitChildElements(visit);
    }

    visit(context);
    return runs.isEmpty ? null : runs.join();
  }

  bool _sameUnits(String? actual, String expected) =>
      actual != null && listEquals(actual.codeUnits, expected.codeUnits);

  Future<void> _runBatch() async {
    final directory = Directory('${Directory.systemTemp.path}/unicode-probe');
    await directory.create(recursive: true);
    for (final dark in [false, true]) {
      for (var index = 0; index < unicodeSamples.length; index++) {
        if (!mounted) return;
        setState(() => _dark = dark);
        _selectSample(index);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        _validate();
        await WidgetsBinding.instance.endOfFrame;
        final boundary = _captureKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final capture = await boundary.toImage(pixelRatio: 2);
        try {
          final data = await capture.toByteData(format: ui.ImageByteFormat.png);
          if (data != null) {
            await File(
                    '${directory.path}/${dark ? 'dark' : 'light'}-$index.png')
                .writeAsBytes(data.buffer.asUint8List());
          }
        } finally {
          capture.dispose();
        }
      }
    }
    debugPrint('UNICODE_NATIVE_PROBE_BATCH_COMPLETE ${directory.path}');
  }

  void _validate() {
    final raw = _input.text;
    final markdown = _markdown(raw);
    final checks = <String, bool>{
      'EditableText': _sameUnits(_renderedText(_inputKey, editable: true), raw),
      'Text': _sameUnits(_renderedText(_rawKey), raw),
      'TextView': _sameUnits(_renderedText(_commonKey), raw),
      'MatchTextView': _sameUnits(_renderedText(_matchKey), raw),
      'Match callback': _sameUnits(_matchVisible, raw),
      'Markdown display': _sameUnits(_renderedText(_markdownKey), 'A${raw}Z'),
      'Markdown source': _sameUnits(_markdownSource, markdown),
      'JSON round trip': _sameUnits(jsonDecode(jsonEncode(raw)) as String, raw),
    };
    debugPrint('UNICODE_NATIVE_PROBE ${jsonEncode({
          'sampleIndex': _index,
          'sample': unicodeSamples[_index].name,
          'theme': _dark ? 'dark' : 'light',
          'platform': defaultTargetPlatform.name,
          'rawText': raw,
          'rawCodeUnits': raw.codeUnits,
          'seedUnchanged': _sameUnits(raw, unicodeSamples[_index].text),
          'selection': {
            'base': _input.selection.baseOffset,
            'extent': _input.selection.extentOffset,
          },
          'composing': {
            'start': _input.value.composing.start,
            'end': _input.value.composing.end,
          },
          'checks': checks,
          // A raw-sequence pass does not imply that the OS font has the glyph.
          'glyphShape':
              'requires screenshot inspection; not automatically verified',
        })}');
    setState(() => _checks = checks);
  }

  @override
  Widget build(BuildContext context) => ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.light),
          darkTheme: ThemeData(brightness: Brightness.dark),
          themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
          home: Builder(builder: (context) {
            final theme = Theme.of(context);
            final style = theme.textTheme.bodyLarge!.copyWith(fontSize: 20);
            final raw = _input.text;
            return Scaffold(
              appBar: AppBar(
                title: const Text('Unicode native probe'),
                actions: [
                  IconButton(
                    tooltip: 'Toggle light/dark',
                    onPressed: () {
                      setState(() => _dark = !_dark);
                      _queueValidation();
                    },
                    icon: Icon(_dark ? Icons.light_mode : Icons.dark_mode),
                  ),
                ],
              ),
              body: RepaintBoundary(
                key: _captureKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        IconButton(
                          tooltip: 'Previous sample',
                          onPressed: () => _selectSample(
                              (_index - 1 + unicodeSamples.length) %
                                  unicodeSamples.length),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: DropdownButton<int>(
                            key: const ValueKey('probe-sample-picker'),
                            isExpanded: true,
                            value: _index,
                            items: [
                              for (var i = 0; i < unicodeSamples.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                      '${i + 1}: ${unicodeSamples[i].name}',
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (index) {
                              if (index != null) _selectSample(index);
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next sample',
                          onPressed: () => _selectSample(
                              (_index + 1) % unicodeSamples.length),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ]),
                      Text(
                        _checks.isEmpty
                            ? 'Waiting for native layout'
                            : _checks.values.every((value) => value)
                                ? 'Raw sequence checks: PASS (${_checks.length})'
                                : 'Raw sequence checks: FAIL '
                                    '${_checks.entries.where((e) => !e.value).map((e) => e.key).join(', ')}',
                        key: const ValueKey('probe-sequence-report'),
                        style: theme.textTheme.bodySmall,
                      ),
                      Text('Glyph shapes require screenshot inspection.',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      _panel(
                        context,
                        'ChatTextField / IME (live input)',
                        KeyedSubtree(
                          key: _inputKey,
                          child: ChatTextField(
                            controller: _input,
                            style: chatComposerTextStyle(context),
                            autocorrect: false,
                          ),
                        ),
                      ),
                      _panel(context, 'System Text (reference)',
                          Text(raw, key: _rawKey, style: style)),
                      _panel(context, 'Common TextView',
                          TextView(key: _commonKey, data: raw, style: style)),
                      _panel(
                        context,
                        'MatchTextView (custom match, complete clusters)',
                        MatchTextView(
                          key: _matchKey,
                          text: raw,
                          textStyle: style,
                          textScaler: MediaQuery.textScalerOf(context),
                          maximumWidth: double.infinity,
                          patterns: [
                            MatchPattern(
                              type: PatternType.custom,
                              pattern: r'\S',
                              style: style.copyWith(
                                  color: theme.colorScheme.primary),
                            ),
                          ],
                          onVisibleTrulyText: (value) => _matchVisible = value,
                        ),
                      ),
                      _panel(
                        context,
                        'Markdown bold (A/raw/Z literal wrapper)',
                        ChatMarkdownText(
                          key: _markdownKey,
                          text: _markdown(raw),
                          textStyle: style,
                          textScaler: MediaQuery.textScalerOf(context),
                          onVisibleTrulyText: (value) =>
                              _markdownSource = value,
                        ),
                      ),
                      Text('UTF-16 units: ${raw.codeUnits.join(' ')}',
                          style: theme.textTheme.bodySmall),
                      TextButton.icon(
                        onPressed: _queueValidation,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Verify rendered sequences'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      );

  Widget _panel(BuildContext context, String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                child,
              ],
            ),
          ),
        ),
      );
}
