import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/ai_palette.dart';
import '../../localization/ai_assistant_i18n.dart';

class AiQuickChipBar extends StatelessWidget {
  const AiQuickChipBar({
    super.key,
    required this.dark,
    required this.i18n,
    required this.selectedId,
    required this.onSelected,
    this.enabled = true,
  });

  final bool dark;
  final AiAssistantI18n i18n;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final chips = <({String id, IconData icon, String label})>[
      (
        id: 'summarize',
        icon: Icons.notes_outlined,
        label: i18n.t(
          zhHans: '总结聊天',
          zhHant: '總結聊天',
          en: 'Summarize chat',
          ja: 'チャットを要約',
          ko: '채팅 요약',
        ),
      ),
      (
        id: 'image',
        icon: Icons.image_outlined,
        label: i18n.t(
          zhHans: '生成图片',
          zhHant: '生成圖片',
          en: 'Generate image',
          ja: '画像を生成',
          ko: '이미지 생성',
        ),
      ),
      (
        id: 'analyze',
        icon: Icons.description_outlined,
        label: i18n.t(
          zhHans: '分析文件',
          zhHant: '分析檔案',
          en: 'Analyze file',
          ja: 'ファイルを分析',
          ko: '파일 분석',
        ),
      ),
      (
        id: 'write',
        icon: Icons.edit_outlined,
        label: i18n.t(
          zhHans: '写文案',
          zhHant: '寫文案',
          en: 'Write copy',
          ja: 'コピーを作成',
          ko: '문구 작성',
        ),
      ),
    ];
    return SizedBox(
      height: math.max(
        AiMetrics.dimension56,
        MediaQuery.textScalerOf(context).scale(AiMetrics.font13) *
                AiMetrics.inputLineHeight +
            AiMetrics.space28,
      ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(AiMetrics.space16, AiMetrics.space4,
            AiMetrics.space16, AiMetrics.space8),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AiMetrics.dimension8),
        itemBuilder: (context, index) {
          final chip = chips[index];
          final selected = selectedId == chip.id;
          final fg = selected ? AiPalette.brand(dark) : AiPalette.primary(dark);
          final bg = selected
              ? AiPalette.brand(dark).withValues(alpha: dark ? 0.18 : 0.12)
              : AiPalette.cardBg(dark);
          final border = selected
              ? AiPalette.brand(dark).withValues(alpha: 0.45)
              : AiPalette.line(dark);
          return Material(
            color: bg,
            borderRadius: BorderRadius.circular(AiMetrics.radius20),
            child: InkWell(
              onTap: enabled ? () => onSelected(chip.id) : null,
              borderRadius: BorderRadius.circular(AiMetrics.radius20),
              child: Container(
                constraints:
                    const BoxConstraints(minHeight: AiMetrics.dimension44),
                padding: EdgeInsets.only(
                  left: AiMetrics.space12,
                  right: selected ? AiMetrics.space6 : AiMetrics.space12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AiMetrics.radius20),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Icon(chip.icon, size: AiMetrics.dimension16, color: fg),
                    const SizedBox(width: AiMetrics.dimension6),
                    Text(
                      chip.label,
                      style: TextStyle(
                        color: fg,
                        fontSize: AiMetrics.font13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: AiMetrics.dimension2),
                      InkWell(
                        onTap: enabled ? () => onSelected(chip.id) : null,
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(AiMetrics.space4),
                          child: Icon(
                            Icons.close_rounded,
                            size: AiMetrics.dimension14,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class AiInputBar extends StatelessWidget {
  const AiInputBar({
    super.key,
    required this.dark,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.onAdd,
    required this.onImage,
    required this.onAttach,
    required this.onSubmit,
    required this.onStop,
    required this.replying,
    this.enabled = true,
    this.maxLines = 1,
    this.addLabel,
    this.imageLabel,
    this.attachLabel,
    this.submitLabel,
    this.loading = false,
  });

  final bool dark;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onAdd;
  final VoidCallback onImage;
  final VoidCallback onAttach;
  final VoidCallback onSubmit;
  final VoidCallback onStop;
  final bool replying;
  final bool enabled;
  final int maxLines;
  final String? addLabel, imageLabel, attachLabel, submitLabel;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final iconColor = AiPalette.primary(dark);
    final inputHeight = math.max(
        AiMetrics.dimension48,
        MediaQuery.textScalerOf(context).scale(AiMetrics.font14) *
                AiMetrics.inputLineHeight +
            AiMetrics.space24);
    return Row(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AiPalette.inputBg(dark),
              borderRadius: BorderRadius.circular(
                  math.max(AiMetrics.radius28, inputHeight / 2)),
              border: Border.all(
                color: AiPalette.line(dark),
              ),
              boxShadow: dark
                  ? const <BoxShadow>[]
                  : const <BoxShadow>[
                      BoxShadow(
                        color: AiPalette.inputShadow,
                        blurRadius: AiMetrics.dimension10,
                        offset: Offset(AiMetrics.space0, AiMetrics.space2),
                      ),
                    ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: inputHeight),
              child: Row(
                children: [
                  AiInputIconButton(
                    icon: Icons.add,
                    color: iconColor,
                    onPressed: enabled ? onAdd : null,
                    tooltip: addLabel,
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: maxLines,
                      textInputAction: maxLines == 1
                          ? TextInputAction.send
                          : TextInputAction.newline,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      onSubmitted: (_) {
                        if (enabled && !replying) {
                          onSubmit();
                        }
                      },
                      style: TextStyle(
                        color: AiPalette.primary(dark),
                        fontSize: AiMetrics.font14,
                        height: AiMetrics.inputLineHeight,
                      ),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: TextStyle(
                          color: AiPalette.secondary(dark),
                          fontSize: AiMetrics.font14,
                          height: AiMetrics.inputLineHeight,
                        ),
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: AiMetrics.space12,
                        ),
                      ),
                    ),
                  ),
                  AiInputIconButton(
                    icon: Icons.image_outlined,
                    color: iconColor,
                    onPressed: enabled ? onImage : null,
                    tooltip: imageLabel,
                  ),
                  AiInputIconButton(
                    icon: Icons.description_outlined,
                    color: iconColor,
                    onPressed: enabled ? onAttach : null,
                    tooltip: attachLabel,
                  ),
                  const SizedBox(width: AiMetrics.dimension4),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AiMetrics.dimension8),
        Semantics(
          button: true,
          enabled: enabled,
          label: submitLabel,
          child: Material(
            color: AiPalette.transparent,
            child: InkWell(
              onTap: enabled ? (replying ? onStop : onSubmit) : null,
              customBorder: const CircleBorder(),
              child: Ink(
                width: AiMetrics.dimension48,
                height: AiMetrics.dimension48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      AiPalette.accent,
                      AiPalette.userBubble,
                    ],
                  ),
                ),
                child: loading
                    ? const Center(
                        child: SizedBox(
                          width: AiMetrics.dimension18,
                          height: AiMetrics.dimension18,
                          child: CircularProgressIndicator(
                              strokeWidth: AiMetrics.dimension2,
                              color: AiPalette.onAccent),
                        ),
                      )
                    : Icon(
                        replying ? Icons.stop_rounded : Icons.send_rounded,
                        size: AiMetrics.dimension18,
                        color: AiPalette.onAccent,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AiInputIconButton extends StatelessWidget {
  const AiInputIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(AiMetrics.space8),
      constraints: const BoxConstraints(
          minWidth: AiMetrics.dimension48, minHeight: AiMetrics.dimension48),
      icon: Icon(icon, size: AiMetrics.dimension22, color: color),
    );
  }
}
