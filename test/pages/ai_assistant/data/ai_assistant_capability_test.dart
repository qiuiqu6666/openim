import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/composer/ai_assistant_capability.dart';
import 'package:openim/pages/ai_assistant/models/ai_assistant_models.dart';

void main() {
  const pdf = AiAssistantFileRef(name: 'report.pdf', sizeLabel: '1 KB', kind: AiAssistantFileKind.pdf, sizeBytes: 1024);
  const card = AiAssistantCardRef(kind: AiAssistantCardKind.group, id: 'real-group', name: '工作群');
  test('cards resolve to server-owned chat analysis, PDF to file analysis', () {
    final summarize = AiAssistantSendPlanner.plan(tool: null, text: '', cards: [card], files: []) as AiAssistantSendPlan;
    expect(summarize.capability, 'summarize');
    expect(summarize.analyze!.toJson(), {'type': 'group', 'groupId': 'real-group'});
    final file = AiAssistantSendPlanner.plan(tool: null, text: '', cards: [], files: [pdf]) as AiAssistantSendPlan;
    expect(file.capability, 'file');
    expect(file.content, isEmpty);
  });
  test('mixed tools, duplicate attachments and excessive content cannot send', () {
    expect(AiAssistantSendPlanner.plan(tool: 'summarize', text: '', cards: [card], files: [pdf]), isA<AiAssistantSendError>());
    expect(AiAssistantSendPlanner.plan(tool: 'image', text: 'draw', cards: [], files: [pdf]), isA<AiAssistantSendError>());
    expect(AiAssistantSendPlanner.plan(tool: 'analyze', text: '', cards: [], files: [pdf, pdf]), isA<AiAssistantSendError>());
    expect(AiAssistantSendPlanner.plan(tool: null, text: '中' * 8001, cards: [], files: []), isA<AiAssistantSendError>());
  });
}
