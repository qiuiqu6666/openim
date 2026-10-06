import 'package:flutter/material.dart';
import '../../theme/ai_palette.dart';
import '../../localization/ai_assistant_i18n.dart';

class AiEmptyChatArt extends StatelessWidget {
  const AiEmptyChatArt({
    super.key,
    required this.dark,
    required this.i18n,
    required this.onStart,
    this.assistantName = '99ChatAI',
  });

  static const _asset = 'assets/ai/bg.png';

  final bool dark;
  final AiAssistantI18n i18n;
  final VoidCallback onStart;
  final String assistantName;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final artWidth = (width * AiMetrics.emptyArtWidthRatio)
        .clamp(AiMetrics.emptyArtMinWidth, AiMetrics.emptyArtMaxWidth);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AiMetrics.space32, AiMetrics.space12,
            AiMetrics.space32, AiMetrics.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              _asset,
              width: artWidth,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: AiMetrics.dimension20),
            Text(
              i18n.t(
                zhHans: '还没有聊天内容',
                zhHant: '還沒有聊天內容',
                en: 'No chats yet',
                ja: 'まだ会話がありません',
                ko: '아직 대화가 없습니다',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AiPalette.primary(dark),
                fontSize: AiMetrics.font18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AiMetrics.dimension8),
            Text(
              i18n.t(
                zhHans: '现在开始与 $assistantName 对话\n让 AI 帮你解答问题、生成内容、激发灵感',
                zhHant: '現在開始與 $assistantName 對話\n讓 AI 幫你解答問題、生成內容、激發靈感',
                en: 'Start chatting with $assistantName\nto get answers, create content, and find inspiration',
                ja: '99ChatAI と会話を始めて\n質問への回答、コンテンツ作成、アイデア出しを手伝ってもらいましょう',
                ko: '지금 99ChatAI와 대화를 시작해\n질문 해결, 콘텐츠 생성, 영감을 얻어 보세요',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AiPalette.secondary(dark),
                fontSize: AiMetrics.font13,
                height: AiMetrics.textLineHeight,
              ),
            ),
            const SizedBox(height: AiMetrics.dimension20),
            FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                backgroundColor: AiPalette.brand(dark),
                foregroundColor: AiPalette.onAccent,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: AiMetrics.space28,
                  vertical: AiMetrics.space12,
                ),
                shape: const StadiumBorder(),
              ),
              child: Text(
                i18n.t(
                  zhHans: '开始新对话',
                  zhHant: '開始新對話',
                  en: 'Start a new chat',
                  ja: '新しい会話を始める',
                  ko: '새 대화 시작',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AiWelcomeBanner extends StatelessWidget {
  const AiWelcomeBanner({
    super.key,
    required this.dark,
    required this.i18n,
    required this.onClose,
  });

  final bool dark;
  final AiAssistantI18n i18n;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AiMetrics.radius16),
          child: Image.asset(
            'assets/ai/welcome.jpg',
            width: double.infinity,
            fit: BoxFit.fitWidth,
          ),
        ),
        Positioned(
          top: AiMetrics.position0,
          right: AiMetrics.position0,
          child: IconButton(
            tooltip: i18n.t(
              zhHans: '关闭',
              zhHant: '關閉',
              en: 'Close',
              ja: '閉じる',
              ko: '닫기',
            ),
            onPressed: onClose,
            icon: Icon(
              Icons.close_rounded,
              size: AiMetrics.dimension18,
              color: AiPalette.secondary(dark),
            ),
          ),
        ),
      ],
    );
  }
}
