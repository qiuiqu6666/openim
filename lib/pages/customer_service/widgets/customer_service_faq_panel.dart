// Adapted from 99chat's native customer-service FAQ cards (Apache-2.0).
// External callbacks retain this client's navigation and selection ownership.
import 'package:flutter/material.dart';

import '../content/customer_service_content.dart';
import '../customer_service_tokens.dart';

/// Intrinsic question/answer content for the shared customer-service canvas.
/// Selection and the official-site navigation are owned by the support page.
class CustomerServiceFaqPanel extends StatelessWidget {
  const CustomerServiceFaqPanel({
    super.key,
    required this.category,
    this.questionId,
    required this.onQuestion,
    required this.onBack,
    this.officialURL = '',
    this.onOpenOfficialURL,
  });

  final CustomerServiceCategory category;
  final String? questionId;
  final ValueChanged<String> onQuestion;
  final VoidCallback onBack;
  final String officialURL;
  final VoidCallback? onOpenOfficialURL;

  CustomerServiceQuestion? get _question {
    for (final question in category.questions) {
      if (question.id == questionId) return question;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final question = _question;
    return Padding(
      padding: const EdgeInsets.all(CustomerServiceTokens.panelInset),
      child: Material(
        color: CustomerServiceTokens.surface(context),
        borderRadius: BorderRadius.circular(CustomerServiceTokens.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: question == null
            ? _questionList(context)
            : _answer(context, question),
      ),
    );
  }

  Widget _divider(BuildContext context) => Divider(
      height: CustomerServiceTokens.dividerWidth,
      thickness: CustomerServiceTokens.dividerWidth,
      color: CustomerServiceTokens.border(context));

  Widget _questionList(BuildContext context) => Column(
        key: ValueKey('customer-service-faq-${category.id}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < category.questions.length; index++) ...[
            if (index > 0) _divider(context),
            _questionRow(context, category.questions[index]),
          ],
        ],
      );

  Widget _questionRow(BuildContext context, CustomerServiceQuestion question) =>
      InkWell(
        key: ValueKey('customer-service-question-${question.id}'),
        onTap: () => onQuestion(question.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minHeight: CustomerServiceTokens.faqRowMinHeight),
          child: Padding(
            padding: CustomerServiceTokens.faqRowPadding,
            child: Row(
              children: [
                const Icon(Icons.play_arrow_rounded,
                    color: CustomerServiceTokens.blue,
                    size: CustomerServiceTokens.faqIconSize),
                const SizedBox(width: CustomerServiceTokens.faqIconGap),
                Expanded(
                  child: Text(question.label(context),
                      style: TextStyle(
                          color: CustomerServiceTokens.text(context),
                          fontSize: CustomerServiceTokens.faqFontSize)),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: CustomerServiceTokens.secondaryText(context),
                    size: CustomerServiceTokens.chevronSize),
              ],
            ),
          ),
        ),
      );

  Widget _answer(BuildContext context, CustomerServiceQuestion question) {
    final link = officialURL.trim();
    return Column(
      key: ValueKey('customer-service-answer-${question.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: MaterialLocalizations.of(context).backButtonTooltip,
          child: InkWell(
            key: const ValueKey('customer-service-answer-back'),
            onTap: onBack,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  minHeight: CustomerServiceTokens.faqRowMinHeight),
              child: Padding(
                padding: CustomerServiceTokens.answerHeaderPadding,
                child: Row(
                  children: [
                    const SizedBox(
                      width: CustomerServiceTokens.faqRowMinHeight,
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: CustomerServiceTokens.blue,
                          size: CustomerServiceTokens.faqIconSize),
                    ),
                    Expanded(
                      child: Text(question.label(context),
                          style: TextStyle(
                              color: CustomerServiceTokens.text(context),
                              fontSize: CustomerServiceTokens.headerFontSize,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: CustomerServiceTokens.panelInset),
                  ],
                ),
              ),
            ),
          ),
        ),
        _divider(context),
        Padding(
          padding: CustomerServiceTokens.answerPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(question.answer(context, officialURL: link),
                  style: TextStyle(
                      color: CustomerServiceTokens.text(context),
                      fontSize: CustomerServiceTokens.faqFontSize,
                      height: CustomerServiceTokens.answerLineHeight)),
              if (question.isOfficialWebsite && link.isNotEmpty) ...[
                const SizedBox(height: CustomerServiceTokens.answerLinkGap),
                Semantics(
                  link: true,
                  child: TextButton(
                    key: const ValueKey('customer-service-official-link'),
                    onPressed: onOpenOfficialURL,
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.zero,
                      minimumSize:
                          const Size(0, CustomerServiceTokens.tapMinHeight),
                    ),
                    child: Text(link,
                        style: const TextStyle(
                            color: CustomerServiceTokens.blue,
                            fontSize: CustomerServiceTokens.faqFontSize,
                            height: CustomerServiceTokens.answerLineHeight,
                            decoration: TextDecoration.underline)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
