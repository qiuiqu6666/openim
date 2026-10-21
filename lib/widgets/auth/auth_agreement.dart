import 'package:flutter/material.dart';
import '../../routes/swipe_back/app_page_route.dart';
import '../../pages/mine/settings/pages/legal_document_page.dart';
import 'auth_copy.dart';
import 'auth_reference.dart';

class AuthAgreement extends StatelessWidget {
  const AuthAgreement({super.key, required this.accepted, required this.onChanged});
  final bool accepted;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      height: 1.5,
      color: AuthReferenceTokens.color(context, AuthReferenceTokens.ink400),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: Alignment.center,
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              value: accepted,
              activeColor: AuthReferenceTokens.brand500,
              checkColor: Colors.white,
              side: const BorderSide(color: AuthReferenceTokens.brand500, width: 2),
              onChanged: onChanged == null ? null : (value) => onChanged!(value ?? false),
              semanticLabel: authText('同意用户协议', 'Agree to the User Agreement'),
            ),
            Text(authText('我已阅读并同意', 'I have read and agree to'),
                style: style),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                  AppMaterialPageRoute<void>(
                      builder: (_) => const LegalDocumentPage(
                          kind: LegalDocumentKind.terms))),
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(authText('《用户协议》', '《User Agreement》'),
                    style: style.copyWith(
                      color: AuthReferenceTokens.brand500,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
