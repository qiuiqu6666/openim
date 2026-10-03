import 'package:flutter/material.dart';
import 'host/wallet_i18n.dart';
import 'host/app_empty_state.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import 'wallet_time.dart';

import 'record/wallet_record_detail_screen.dart';
import 'record/wallet_record_models.dart';
import 'wallet_repository.dart';
import 'wallet_repository_provider.dart';
import 'widgets/platform_coin_icon.dart';
import 'widgets/wallet_page_colors.dart';
import 'host/wallet_navigation.dart';
import 'widgets/wallet_99chat_scale.dart';

class WalletDepositRecordScreen extends StatelessWidget {
  const WalletDepositRecordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return _WalletAssetRecordScreen(
      title: i18n.t(
        zhHans: '充币记录',
        zhHant: '充幣記錄',
        en: 'Deposit History',
        ja: '入金履歴',
        ko: '입금 기록',
      ),
      emptyText: i18n.t(
        zhHans: '暂无充币记录',
        zhHant: '暫無充幣記錄',
        en: 'No deposit records yet.',
        ja: '入金履歴はありません。',
        ko: '입금 기록이 없습니다.',
      ),
      mode: _WalletAssetRecordMode.deposit,
    );
  }
}

class WalletWithdrawRecordScreen extends StatelessWidget {
  const WalletWithdrawRecordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return _WalletAssetRecordScreen(
      title: i18n.t(
        zhHans: '提币记录',
        zhHant: '提幣記錄',
        en: 'Withdrawal History',
        ja: '出金履歴',
        ko: '출금 기록',
      ),
      emptyText: i18n.t(
        zhHans: '暂无提币记录',
        zhHant: '暫無提幣記錄',
        en: 'No withdrawal records yet.',
        ja: '出金履歴はありません。',
        ko: '출금 기록이 없습니다.',
      ),
      mode: _WalletAssetRecordMode.withdraw,
    );
  }
}

enum _WalletAssetRecordMode { deposit, withdraw }

const String _kAllCoinsSentinel = '全部币种';

String _allCoinsDisplayLabel(AppI18n i18n) {
  return i18n.t(
    zhHans: '全部币种',
    zhHant: '全部幣種',
    en: 'All Tokens',
    ja: 'すべての通貨',
    ko: '전체 코인',
  );
}

String _displayCoinFilter(String coin, AppI18n i18n) {
  if (coin == _kAllCoinsSentinel) return _allCoinsDisplayLabel(i18n);
  return coin;
}

class _WalletAssetRecordScreen extends StatefulWidget {
  final String title;
  final String emptyText;
  final _WalletAssetRecordMode mode;

  const _WalletAssetRecordScreen({
    required this.title,
    required this.emptyText,
    required this.mode,
  });

  @override
  State<_WalletAssetRecordScreen> createState() =>
      _WalletAssetRecordScreenState();
}

class _WalletAssetRecordScreenState extends State<_WalletAssetRecordScreen> {
  final WalletRepository _repo = createWalletRepository();
  bool _loading = true;
  String _err = '';
  List<WalletRecordDto> _allList = const [];
  List<WalletRecordDto> _list = const [];
  String _selectedCoin = _kAllCoinsSentinel;
  late DateTimeRange _selectedRange;

  @override
  void initState() {
    super.initState();
    final end = DateTime.now();
    _selectedRange = DateTimeRange(
      start: DateTime(end.year, end.month, end.day).subtract(
        const Duration(days: 6),
      ),
      end: DateTime(end.year, end.month, end.day),
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = '';
    });
    try {
      final list = widget.mode == _WalletAssetRecordMode.deposit
          ? await _repo.getDepositRecords()
          : await _repo.getWithdrawRecords();
      if (!mounted) return;
      setState(() {
        _allList = list;
        _list = _applyFilters(list);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _err = AppI18n.current.t(
          zhHans: '记录加载失败，请稍后重试',
          zhHant: '記錄載入失敗，請稍後再試',
          en: 'Failed to load records. Please try again later.',
          ja: '履歴の読み込みに失敗しました。しばらくしてからもう一度お試しください。',
          ko: '기록을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
        );
        _allList = const [];
        _list = const [];
        _loading = false;
      });
    }
  }

  List<WalletRecordDto> _applyFilters(List<WalletRecordDto> source) {
    return source.where((item) {
      final coinMatch =
          _selectedCoin == _kAllCoinsSentinel ||
              item.coin.toUpperCase() == _selectedCoin;
      if (!coinMatch) return false;
      final time = _parseRecordTime(item.time);
      if (time == null) return false;
      final day = DateTime(time.year, time.month, time.day);
      return !day.isBefore(_selectedRange.start) &&
          !day.isAfter(_selectedRange.end);
    }).toList();
  }

  DateTime? _parseRecordTime(String raw) => parseWalletApiTimeToLocal(raw);

  List<String> get _coinOptions {
    final out = <String>{_kAllCoinsSentinel};
    for (final item in _allList) {
      final coin = item.coin.trim().toUpperCase();
      if (coin.isNotEmpty) out.add(coin);
    }
    return out.toList();
  }

  Future<void> _pickCoin() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CoinPickerSheet(
        options: _coinOptions,
        selectedCoin: _selectedCoin,
      ),
    );
    if (!mounted || selected == null || selected == _selectedCoin) return;
    setState(() {
      _selectedCoin = selected;
      _list = _applyFilters(_allList);
    });
  }

  Future<void> _pickDateRange() async {
    final i18n = AppI18n.of(context);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      locale: Localizations.localeOf(context),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _selectedRange,
      saveText: i18n.t(
        zhHans: '确定',
        zhHant: '確定',
        en: 'Done',
        ja: '完了',
        ko: '확인',
      ),
      helpText: i18n.t(
        zhHans: '选择时间范围',
        zhHant: '選擇時間範圍',
        en: 'Select Date Range',
        ja: '期間を選択',
        ko: '기간 선택',
      ),
      cancelText: i18n.t(
        zhHans: '取消',
        zhHant: '取消',
        en: 'Cancel',
        ja: 'キャンセル',
        ko: '취소',
      ),
      confirmText: i18n.t(
        zhHans: '确定',
        zhHant: '確定',
        en: 'Confirm',
        ja: '確認',
        ko: '확인',
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: WalletPageColors.of(context).blue,
                ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() {
      _selectedRange = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day),
      );
      _list = _applyFilters(_allList);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final appBar = WalletAppBarColors.of(context);
    return wrapWalletPage(
      context,
      Scaffold(
      backgroundColor: cs.bg,
      appBar: AppBar(
        leading: const AppBackButton(),
        centerTitle: true,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: appBar.background,
        foregroundColor: appBar.title,
        systemOverlayStyle: walletPageOverlayStyle(context),
        leadingWidth: 54,
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: appBar.title,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: _buildBody(cs),
      ),
    ),
    );
  }

  Widget _buildBody(WalletPageColors cs) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: cs.blue),
      );
    }

    final list = _err.isNotEmpty
        ? _AssetErrorBox(text: _err, onRetry: _load)
        : _list.isEmpty
            ? AppEmptyState(message: widget.emptyText)
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(24.w99, 9.h99, 24.w99, 36.h99),
                separatorBuilder: (_, __) => SizedBox(height: 0.h99),
                itemCount: _list.length,
                itemBuilder: (_, i) {
                  final item = _list[i];
                  return _AssetRecordCard(
                    item: item,
                    onTap: () {
                      openWalletPage<void>(
                        context,
                        WalletRecordDetailScreen(item: item),
                      );
                    },
                  );
                },
              );

    final i18n = AppI18n.of(context);
    return Column(
      children: [
        _WithdrawRecordFilterBar(
          coinText: _displayCoinFilter(_selectedCoin, i18n),
          dateRangeText: _dateRangeText(i18n),
          onCoinTap: _pickCoin,
          onDateTap: _pickDateRange,
        ),
        Expanded(child: list),
      ],
    );
  }

  String _dateRangeText(AppI18n i18n) {
    final fmt = DateFormat('yyyy-MM-dd');
    return i18n.format(
      zhHans: '{start} 到 {end}',
      zhHant: '{start} 到 {end}',
      en: '{start} to {end}',
      ja: '{start} ～ {end}',
      ko: '{start} ~ {end}',
      vars: {
        'start': fmt.format(_selectedRange.start),
        'end': fmt.format(_selectedRange.end),
      },
    );
  }
}

class _WithdrawRecordFilterBar extends StatelessWidget {
  final String coinText;
  final String dateRangeText;
  final VoidCallback onCoinTap;
  final VoidCallback onDateTap;

  const _WithdrawRecordFilterBar({
    required this.coinText,
    required this.dateRangeText,
    required this.onCoinTap,
    required this.onDateTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(30.w99, 18.h99, 30.w99, 6.h99),
      child: Row(
        children: [
          GestureDetector(
            onTap: onCoinTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 63.h99,
              padding: EdgeInsets.symmetric(horizontal: 24.w99),
              decoration: BoxDecoration(
                color: cs.card,
                borderRadius: BorderRadius.circular(31.5.r99),
              ),
              child: Row(
                children: [
                  Text(
                    coinText,
                    style: TextStyle(
                      fontSize: 21.sp99,
                      fontWeight: FontWeight.w500,
                      color: cs.text,
                    ),
                  ),
                  SizedBox(width: 12.w99),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 33.sp99,
                    color: cs.subText,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 18.w99),
          Expanded(
            child: GestureDetector(
              onTap: onDateTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 63.h99,
                padding: EdgeInsets.symmetric(horizontal: 24.w99),
                decoration: BoxDecoration(
                  color: cs.card,
                  borderRadius: BorderRadius.circular(31.5.r99),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dateRangeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 21.sp99,
                          fontWeight: FontWeight.w500,
                          color: cs.text,
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w99),
                    Icon(
                      Icons.access_time_filled_rounded,
                      size: 24.sp99,
                      color: cs.subText,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinPickerSheet extends StatefulWidget {
  final List<String> options;
  final String selectedCoin;

  const _CoinPickerSheet({
    required this.options,
    required this.selectedCoin,
  });

  @override
  State<_CoinPickerSheet> createState() => _CoinPickerSheetState();
}

class _CoinPickerSheetState extends State<_CoinPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _filteredCoins {
    final keyword = _query.trim().toUpperCase();
    final list = widget.options.where((e) => e != _kAllCoinsSentinel);
    if (keyword.isEmpty) return list.toList();
    return list.where((e) => e.toUpperCase().contains(keyword)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return FractionallySizedBox(
      heightFactor: 0.4,
      child: Container(
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(39.r99)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(height: 15.h99),
              Container(
                width: 111.w99,
                height: 9.h99,
                decoration: BoxDecoration(
                  color: cs.line,
                  borderRadius: BorderRadius.circular(99.r99),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(30.w99, 27.h99, 30.w99, 12.h99),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        i18n.t(
                          zhHans: '选择币种',
                          zhHant: '選擇幣種',
                          en: 'Select coin',
                          ja: '通貨を選択',
                          ko: '코인 선택',
                        ),
                        style: TextStyle(
                          fontSize: 31.5.sp99,
                          fontWeight: FontWeight.w600,
                          color: cs.text,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(30.r99),
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: EdgeInsets.all(6.w99),
                        child: Icon(
                          Icons.close_rounded,
                          size: 39.sp99,
                          color: cs.subText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(30.w99, 15.h99, 30.w99, 18.h99),
                child: Container(
                  height: 78.h99,
                  decoration: BoxDecoration(
                    color: cs.inputFill,
                    borderRadius: BorderRadius.circular(21.r99),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    cursorColor: cs.inputCursor,
                    style: TextStyle(
                      fontSize: 25.5.sp99,
                      color: cs.text,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 36.sp99,
                        color: cs.subText,
                      ),
                      hintText: i18n.t(
                        zhHans: '搜索',
                        zhHant: '搜尋',
                        en: 'Search',
                        ja: '検索',
                        ko: '검색',
                      ),
                      hintStyle: TextStyle(
                        fontSize: 25.5.sp99,
                        color: cs.inputHint,
                      ),
                      contentPadding: EdgeInsets.symmetric(vertical: 21.h99),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(30.w99, 9.h99, 30.w99, 24.h99),
                  children: [
                    _CoinSheetRow(
                      title: _allCoinsDisplayLabel(i18n),
                      selected: widget.selectedCoin == _kAllCoinsSentinel,
                      onTap: () => Navigator.of(context).pop(_kAllCoinsSentinel),
                    ),
                    ..._filteredCoins.map(
                      (coin) => _CoinSheetRow(
                        title: coin,
                        selected: coin == widget.selectedCoin,
                        icon: _CoinSheetIcon(coin: coin),
                        onTap: () => Navigator.of(context).pop(coin),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoinSheetRow extends StatelessWidget {
  final String title;
  final bool selected;
  final Widget? icon;
  final VoidCallback onTap;

  const _CoinSheetRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(21.r99),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 22.5.h99),
        child: Row(
          children: [
            if (icon != null) ...[
              icon!,
              SizedBox(width: 24.w99),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 27.sp99,
                  fontWeight: FontWeight.w500,
                  color: cs.text,
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                color: cs.blue,
              ),
          ],
        ),
      ),
    );
  }
}

class _CoinSheetIcon extends StatelessWidget {
  final String coin;

  const _CoinSheetIcon({
    required this.coin,
  });

  @override
  Widget build(BuildContext context) {
    final upper = coin.toUpperCase();
    final size = 54.w99;

    Widget child;
    if (upper == 'TRX') {
      child = SizedBox(
        width: size,
        height: size,
        child: SvgPicture.string(
          _tronLogoSvg,
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      );
    } else if (upper == 'USDT') {
      child = Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF26A17B),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: CustomPaint(
          size: Size(size * 0.62, size * 0.62),
          painter: _UsdtCoinPainter(),
        ),
      );
    } else if (upper == 'BTC') {
      child = Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFFF7931A),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          '₿',
          style: TextStyle(
            fontSize: 29.sp99,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1,
          ),
        ),
      );
    } else if (upper == 'ETH') {
      child = Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFFF1F2F6),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: CustomPaint(
          size: Size(size * 0.56, size * 0.56),
          painter: _EthCoinPainter(),
        ),
      );
    } else if (upper == 'XRP') {
      child = Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF232531),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: CustomPaint(
          size: Size(size * 0.60, size * 0.60),
          painter: _XrpCoinPainter(),
        ),
      );
    } else if (upper == 'SOL') {
      child = Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C28),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: CustomPaint(
          size: Size(size * 0.68, size * 0.68),
          painter: _SolCoinPainter(),
        ),
      );
    } else if (upper == '99') {
      child = PlatformCoinIcon(size: size);
    } else {
      child = Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF5B8CFF),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          upper.isEmpty ? '?' : upper.substring(0, 1),
          style: TextStyle(
            fontSize: 27.sp99,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1,
          ),
        ),
      );
    }

    return SizedBox(width: size, height: size, child: child);
  }
}

class _UsdtCoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.08, h * 0.12, w * 0.84, h * 0.16),
        Radius.circular(w * 0.02),
      ),
      fill,
    );

    final stem = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.41, h * 0.12, w * 0.18, h * 0.76),
      Radius.circular(w * 0.02),
    );
    canvas.drawRRect(stem, fill);

    final oval = Rect.fromCenter(
      center: Offset(w / 2, h * 0.53),
      width: w * 0.92,
      height: h * 0.28,
    );
    canvas.drawArc(oval, 0.06, 6.16, false, stroke);

    final cover = Paint()
      ..color = const Color(0xFF26A17B)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.35, h * 0.43, w * 0.30, h * 0.13),
      cover,
    );
    canvas.drawRRect(stem, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EthCoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final top = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w * 0.18, h * 0.52)
      ..lineTo(w / 2, h * 0.72)
      ..lineTo(w * 0.82, h * 0.52)
      ..close();
    final bottom = Path()
      ..moveTo(w / 2, h)
      ..lineTo(w * 0.18, h * 0.60)
      ..lineTo(w / 2, h * 0.78)
      ..lineTo(w * 0.82, h * 0.60)
      ..close();
    canvas.drawPath(top, Paint()..color = const Color(0xFF8C8FA3));
    canvas.drawPath(
      Path()
        ..moveTo(w / 2, 0)
        ..lineTo(w * 0.82, h * 0.52)
        ..lineTo(w / 2, h * 0.72)
        ..close(),
      Paint()..color = const Color(0xFFB7BACC),
    );
    canvas.drawPath(bottom, Paint()..color = const Color(0xFF9CA0B3));
    canvas.drawPath(
      Path()
        ..moveTo(w / 2, h)
        ..lineTo(w * 0.82, h * 0.60)
        ..lineTo(w / 2, h * 0.78)
        ..close(),
      Paint()..color = const Color(0xFFD1D4E0),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _XrpCoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round;
    final top = Path()
      ..moveTo(size.width * 0.12, size.height * 0.22)
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.46,
        size.width * 0.50,
        size.height * 0.46,
      )
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.46,
        size.width * 0.88,
        size.height * 0.22,
      );
    final bottom = Path()
      ..moveTo(size.width * 0.12, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.54,
        size.width * 0.50,
        size.height * 0.54,
      )
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.54,
        size.width * 0.88,
        size.height * 0.78,
      );
    canvas.drawPath(top, paint);
    canvas.drawPath(bottom, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SolCoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF14F195),
      const Color(0xFF80ECFF),
      const Color(0xFF9945FF),
    ];
    final barHeight = size.height * 0.18;
    final gap = size.height * 0.12;

    void drawBar(double top, Color color, double dx) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(dx, top, size.width - dx * 2, barHeight),
        Radius.circular(barHeight / 2),
      );
      final path = Path()
        ..addRRect(rect)
        ..transform(
          Matrix4.skewX(-0.35).storage,
        );
      canvas.drawPath(path, Paint()..color = color);
    }

    drawBar(0, colors[0], size.width * 0.16);
    drawBar(barHeight + gap, colors[1], size.width * 0.08);
    drawBar((barHeight + gap) * 2, colors[2], size.width * 0.16);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

const String _tronLogoSvg = '''
<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <path d="M512.85 511.04m-447.5 0a447.5 447.5 0 1 0 895 0 447.5 447.5 0 1 0-895 0Z" fill="#D80917"/>
  <path d="M477.1 787.2c-0.84 0-1.71-0.05-2.55-0.18a18.645 18.645 0 0 1-15.04-12.25L277.69 259.74c-2.31-6.56-0.78-13.86 3.97-18.94s11.96-7.12 18.63-5.23l366.29 102.15c2.37 0.66 4.63 1.8 6.56 3.35l68.87 54.7c7.76 6.15 9.36 17.3 3.64 25.36L492.32 779.31a18.628 18.628 0 0 1-15.22 7.89zM324.8 281.12l157.87 447.25L705 414.01l-52.08-41.37-328.12-91.52z" fill="#FFFFFF"/>
  <path d="M477.13 787.2c-0.69 0-1.35-0.04-2.04-0.11-10.23-1.11-17.63-10.31-16.53-20.54l27.42-253.89c1.09-10.27 10.6-17.48 20.54-16.53 10.23 1.11 17.63 10.31 16.53 20.54l-27.42 253.89c-1.02 9.55-9.1 16.64-18.5 16.64z" fill="#FFFFFF"/>
  <path d="M504.52 533.31c-4.73 0-9.47-1.78-13.11-5.37-7.32-7.25-7.39-19.05-0.15-26.38L648.3 342.57c7.25-7.32 19.05-7.39 26.37-0.16 7.32 7.25 7.39 19.05 0.15 26.38L517.77 527.77a18.59 18.59 0 0 1-13.25 5.54z" fill="#FFFFFF"/>
  <path d="M504.52 533.31c-7.03 0-13.77-4.01-16.93-10.83-4.3-9.34-0.22-20.43 9.1-24.75l225.9-104.28c9.4-4.32 20.43-0.24 24.76 9.12 4.3 9.34 0.22 20.43-9.1 24.75L512.35 531.6a18.857 18.857 0 0 1-7.83 1.71z" fill="#FFFFFF"/>
  <path d="M507.21 536.55c-5.46 0-10.85-2.39-14.53-6.99L280.73 265.19c-6.45-8.03-5.15-19.76 2.9-26.2 8.01-6.41 19.79-5.12 26.2 2.9l211.91 264.37c6.45 8.03 5.17 19.76-2.88 26.2a18.563 18.563 0 0 1-11.65 4.09z" fill="#FFFFFF"/>
</svg>
''';

class _AssetRecordCard extends StatelessWidget {
  final WalletRecordDto item;
  final VoidCallback onTap;

  const _AssetRecordCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final amtColor = cs.blue;
    final sign = item.income ? '+' : '-';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(21.r99),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 15.h99),
        child: Row(
          children: [
            _AssetTypeIcon(item: item),
            SizedBox(width: 21.w99),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 27.sp99,
                      color: cs.text,
                      fontWeight: FontWeight.w400,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(height: 6.h99),
                  Text(
                    _displayTime,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22.sp99,
                      color: cs.subText,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12.w99),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$sign${item.amount}',
                  style: TextStyle(
                    fontSize: 27.sp99,
                    color: amtColor,
                    fontWeight: FontWeight.w400,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 6.h99),
                Text(
                  _displayFiat,
                  style: TextStyle(
                    fontSize: 22.sp99,
                    color: cs.subText,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _displayTitle {
    final i18n = AppI18n.current;
    switch (item.status) {
      case WalletRecordStatus.success:
        return item.income
            ? i18n.t(
                zhHans: '已收到',
                zhHant: '已收到',
                en: 'Received',
                ja: '受取済み',
                ko: '수령 완료',
              )
            : i18n.t(
                zhHans: '已发送',
                zhHant: '已發送',
                en: 'Sent',
                ja: '送信済み',
                ko: '전송 완료',
              );
      case WalletRecordStatus.pending:
        return item.income
            ? i18n.t(
                zhHans: '确认中',
                zhHant: '確認中',
                en: 'Confirming',
                ja: '確認中',
                ko: '확인 중',
              )
            : i18n.t(
                zhHans: '处理中',
                zhHant: '處理中',
                en: 'Processing',
                ja: '処理中',
                ko: '처리 중',
              );
      case WalletRecordStatus.failed:
        return i18n.t(
          zhHans: '失败',
          zhHant: '失敗',
          en: 'Failed',
          ja: '失敗',
          ko: '실패',
        );
    }
  }

  String get _displayTime {
    final i18n = AppI18n.current;
    final time = parseWalletApiTimeToLocal(item.time);
    if (time == null) {
      final raw = item.time.trim();
      return raw.isEmpty ? '--' : raw;
    }
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12
        ? i18n.t(
            zhHans: '下午',
            zhHant: '下午',
            en: 'PM',
            ja: '午後',
            ko: '오후',
          )
        : i18n.t(
            zhHans: '上午',
            zhHant: '上午',
            en: 'AM',
            ja: '午前',
            ko: '오전',
          );
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute $period';
  }

  String get _displayFiat {
    final amount = double.tryParse(item.amount.replaceAll(',', '')) ?? 0;
    return '\$${amount.toStringAsFixed(2)}';
  }
}

class _AssetTypeIcon extends StatelessWidget {
  final WalletRecordDto item;

  const _AssetTypeIcon({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final isDeposit = item.income;
    final asset = isDeposit ? 'assets/img/2.svg' : 'assets/img/1.svg';

    return SvgPicture.asset(
      asset,
      width: 72.w99,
      height: 72.w99,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => SizedBox(
        width: 72.w99,
        height: 72.w99,
      ),
    );
  }
}

class _AssetErrorBox extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;

  const _AssetErrorBox({
    required this.text,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 14.sp99,
              color: cs.subText,
            ),
          ),
          SizedBox(height: 10.h99),
          TextButton(
            onPressed: onRetry,
            child: Text(
              i18n.t(
                zhHans: '重试',
                zhHant: '重試',
                en: 'Retry',
                ja: '再試行',
                ko: '다시 시도',
              ),
              style: TextStyle(color: cs.blue),
            ),
          ),
        ],
      ),
    );
  }
}
