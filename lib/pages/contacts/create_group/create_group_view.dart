import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../mine/settings/pages/legal_document_page.dart';
import 'create_group_logic.dart';
import 'create_group_strings.dart';
import 'create_group_tokens.dart';
import 'widgets/create_group_members.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  late final logic = Get.find<CreateGroupLogic>();
  bool _saving = false;

  Future<void> _create() async {
    if (_saving) return;
    final failureText = CreateGroupStrings.of(context).createFailed;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await logic.completeCreation();
    } catch (_) {
      if (mounted) IMViews.showToast(failureText);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CreateGroupTokens.of(context);
    final strings = CreateGroupStrings.of(context);
    return AppSystemBars(
      background: tokens.background,
      child: TouchCloseSoftKeyboard(
        child: Scaffold(
          backgroundColor: tokens.background,
          appBar: GlassAppBar(
            opaque: true,
            backgroundColor: tokens.background,
            toolbarHeight: kToolbarHeight,
            centerTitle: true,
            automaticallyImplyLeading: false,
            leading: IconButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).maybePop(),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              color: tokens.accent,
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            title: Text(
              strings.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.title,
                fontSize: CreateGroupTokens.toolbarTitleSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('create-group-create'),
                onPressed: _saving ? null : _create,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.accent,
                  minimumSize: const Size(CreateGroupTokens.actionTarget,
                      CreateGroupTokens.actionTarget),
                  textStyle: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontSize: CreateGroupTokens.actionSize),
                ),
                child: _saving
                    ? SizedBox.square(
                        dimension: CreateGroupTokens.progressSize,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: tokens.accent),
                      )
                    : Text(strings.create),
              ),
              const SizedBox(width: AppTokens.s3),
            ],
          ),
          body: SafeArea(
            top: false,
            child: AbsorbPointer(
              absorbing: _saving,
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                    CreateGroupTokens.cardPadding,
                    AppTokens.s2,
                    CreateGroupTokens.cardPadding,
                    AppTokens.s7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _card(tokens, _avatar(tokens, strings)),
                    _card(tokens, _name(tokens, strings)),
                    _card(
                      tokens,
                      Obx(() => CreateGroupMembers(
                            members: logic.allList.toList(),
                            onAddMembers: logic.opMember,
                            onOpenTerms: () {
                              FocusScope.of(context).unfocus();
                              Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => const LegalDocumentPage(
                                          kind: LegalDocumentKind.terms)));
                            },
                          )),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(CreateGroupTokens tokens, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: CreateGroupTokens.cardGap),
        child: Material(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(CreateGroupTokens.cardRadius),
          clipBehavior: Clip.antiAlias,
          child: Padding(
              padding: const EdgeInsets.all(CreateGroupTokens.cardPadding),
              child: child),
        ),
      );

  TextStyle _titleStyle(CreateGroupTokens tokens) => TextStyle(
      color: tokens.title,
      fontSize: CreateGroupTokens.sectionTitleSize,
      fontWeight: FontWeight.w700);

  Widget _avatar(CreateGroupTokens tokens, CreateGroupStrings strings) =>
      InkWell(
        key: const ValueKey('create-group-avatar'),
        onTap: logic.selectAvatar,
        borderRadius: BorderRadius.circular(CreateGroupTokens.cardRadius),
        child: Semantics(
          button: true,
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.avatar, style: _titleStyle(tokens)),
                  const SizedBox(height: CreateGroupTokens.subtitleGap),
                  Text(strings.avatarHint,
                      style: TextStyle(
                          fontSize: CreateGroupTokens.subtitleSize,
                          color: tokens.secondary)),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.s3),
            ExcludeSemantics(
              child: Obx(() => AvatarView(
                    width: CreateGroupTokens.avatarSize,
                    height: CreateGroupTokens.avatarSize,
                    isGroup: true,
                    isCircle: true,
                    url: logic.faceURL.value,
                    builder: logic.faceURL.isEmpty
                        ? () => SvgPicture.asset(
                            CreateGroupTokens.defaultAvatarAsset,
                            width: CreateGroupTokens.avatarSize,
                            height: CreateGroupTokens.avatarSize)
                        : null,
                  )),
            ),
            const SizedBox(width: CreateGroupTokens.avatarChevronGap),
            Icon(Icons.chevron_right_rounded,
                color: tokens.secondary, size: CreateGroupTokens.chevronSize),
          ]),
        ),
      );

  Widget _name(CreateGroupTokens tokens, CreateGroupStrings strings) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.name, style: _titleStyle(tokens)),
          const SizedBox(height: CreateGroupTokens.nameGap),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: CreateGroupTokens.nameInputPadding),
            decoration: BoxDecoration(
                color: tokens.inset,
                borderRadius:
                    BorderRadius.circular(CreateGroupTokens.insetRadius)),
            child: Row(children: [
              Expanded(
                child: Obx(() => TextField(
                      key: const ValueKey('create-group-name-input'),
                      controller: logic.nameCtrl,
                      enabled: !_saving,
                      maxLength: CreateGroupTokens.maxNameLength,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(
                          color: tokens.title,
                          fontSize: CreateGroupTokens.nameInputSize),
                      decoration: InputDecoration(
                        hintText: logic.defaultGroupName.isEmpty
                            ? strings.nameHint
                            : logic.defaultGroupName,
                        hintStyle: TextStyle(color: tokens.secondary),
                        counterText: '',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    )),
              ),
              const SizedBox(width: AppTokens.s3),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: logic.nameCtrl,
                builder: (_, value, __) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (value.text.isNotEmpty)
                      TextFieldTapRegion(
                        child: IconButton(
                          key: const ValueKey('create-group-name-clear'),
                          onPressed: _saving ? null : logic.nameCtrl.clear,
                          tooltip: StrRes.clearAll,
                          constraints: const BoxConstraints(
                            minWidth: CreateGroupTokens.actionTarget,
                            minHeight: CreateGroupTokens.actionTarget,
                          ),
                          visualDensity: VisualDensity.standard,
                          color: tokens.secondary,
                          icon: const Icon(Icons.cancel, size: AppTokens.s5),
                        ),
                      ),
                    Text(
                      '${value.text.characters.length}/${CreateGroupTokens.maxNameLength}',
                      key: const ValueKey('create-group-name-count'),
                      style: TextStyle(
                          color: tokens.secondary,
                          fontSize: CreateGroupTokens.nameCountSize),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      );
}
