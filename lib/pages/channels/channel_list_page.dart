import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'create/channel_create_flow.dart';
import '../contacts/select_contacts/contact_card/contact_card_picker_tokens.dart';
import 'presentation/channel_directory.dart';
import 'create/channel_intro_page.dart';
import 'presentation/channel_tokens.dart';
import 'detail/channel_detail_page.dart';
import 'models/channel_preview.dart';
import 'presentation/channel_ui.dart';

class ChannelListPage extends StatefulWidget {
  const ChannelListPage({super.key, this.initialCreate = false});
  final bool initialCreate;
  @override
  State<ChannelListPage> createState() => _ChannelListPageState();
}

class _ChannelListPageState extends State<ChannelListPage> {
  final _channels = <ChannelPreview>[];
  String _query = '';
  final _search = TextEditingController();
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    if (widget.initialCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _create();
      });
    }
  }

  Future<void> _create() async {
    final proceed = await _sheet<bool>(const ChannelIntroPage());
    if (!mounted || proceed != true) return;
    final channel = await _sheet<ChannelPreview>(const ChannelCreateFlow());
    if (!mounted) {
      channel?.dispose();
      return;
    }
    if (channel == null) return;
    setState(() => _channels.insert(0, channel));
    await _open(channel);
  }

  Future<void> _open(ChannelPreview channel) async {
    await channelRoute<void>(context, ChannelDetailPage(channel: channel));
    if (mounted) {
      setState(() {
        if (channel.deleted) {
          _channels.remove(channel);
          channel.dispose();
        }
      });
    }
  }

  Future<T?> _sheet<T>(Widget page) => showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      barrierColor: const Color(0x800A1526),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ChannelTokens.sheetRadius))),
      builder: (context) => SizedBox(
          height:
              MediaQuery.sizeOf(context).height * ChannelTokens.sheetFraction,
          child: page));

  @override
  void dispose() {
    _search.dispose();
    for (final channel in _channels) {
      channel.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _channels
        .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Scaffold(
      backgroundColor: Styles.c_F8F9FA,
      appBar: TitleBar.back(
          title: channelText(context, '频道', 'Channels'),
          backIconColor: Styles.c_0089FF),
      body: Column(children: [
        SearchBox(
          controller: _search,
          enabled: true,
          height: ContactCardPickerTokens.searchHeight(context),
          margin: ContactCardPickerTokens.searchPadding,
          borderRadius:
              BorderRadius.circular(ContactCardPickerTokens.searchRadius),
          surfaceColor: Styles.c_FFFFFF,
          backgroundColor: Styles.c_F4F5F7,
          textStyle: ContactCardPickerTokens.searchStyle(context),
          hintStyle: ContactCardPickerTokens.searchStyle(context, hint: true),
          searchIconColor: ContactCardPickerTokens.secondary(context),
          onChanged: _filter,
          onCleared: () => _filter(''),
          onSubmitted: (value) {
            _filter(value);
            FocusScope.of(context).unfocus();
          },
        ),
        Expanded(
            child: ChannelDirectory(
                channels: filtered,
                searching: _query.isNotEmpty,
                onTap: _open)),
      ]),
    );
  }

  void _filter(String value) => setState(() => _query = value.trim());
}
