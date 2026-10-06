import 'ai_assistant_i18n.dart';

/// Composer wording from the actual 99chat assistant page.
String aiAssistantComposerHint(AiAssistantI18n i18n, String? tool) => switch (tool) {
      'summarize' => i18n.t(
          zhHans: '补充希望在总结中突出的内容…',
          zhHant: '補充希望在總結中突出的內容…',
          en: 'Add what to highlight in the summary...',
          ja: '要約で強調したい点を追加…',
          ko: '요약에서 강조할 내용을 추가하세요…'),
      'image' => i18n.t(
          zhHans: '描述你想生成的图片…',
          zhHant: '描述你想生成的圖片…',
          en: 'Describe the image you want...',
          ja: '作りたい画像を説明してください…',
          ko: '만들고 싶은 이미지를 설명해 주세요…'),
      'analyze' => i18n.t(
          zhHans: '补充希望在文件中查找的内容…',
          zhHant: '補充希望在檔案中查找的內容…',
          en: 'Add what to look for in the file...',
          ja: 'ファイルで探したい内容を追加…',
          ko: '파일에서 찾을 내용을 추가하세요…'),
      'write' => i18n.t(
          zhHans: '主题、语气和用途…',
          zhHant: '主題、語氣和用途…',
          en: 'Topic, tone, and where it will be used...',
          ja: 'テーマ、トーン、使用場面…',
          ko: '주제, 말투, 사용처…'),
      _ => i18n.t(
          zhHans: '问 99ChatAI …',
          zhHant: '問 99ChatAI …',
          en: 'Ask 99ChatAI ...',
          ja: '99ChatAI に質問…',
          ko: '99ChatAI에게 물어보세요…'),
    };
