// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:dio/dio.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';

/// 三公运营接口错误文案（按业务场景细分）。
class SangongAdminErrorMessage {
  SangongAdminErrorMessage._();

  static String fromDebit(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final code = _readCode(map)?.toUpperCase();
        final message = _readMessage(map);
        final balance = map['balance'];
        final periodNo = map['periodNo'] ?? map['period_no'];

        switch (code) {
          case 'INSUFFICIENT_BALANCE':
            if (message != null &&
                message.contains('下分') &&
                message.contains('余额不足')) {
              return DioErrorMessage.sanitizeUserText(
                message,
                fallback: _insufficientForDebit(balance),
              );
            }
            return _insufficientForDebit(balance);
          case 'DEBIT_BLOCKED_BANKER':
            if (message != null && message.trim().isNotEmpty) {
              return DioErrorMessage.sanitizeUserText(
                message,
                fallback: _debitBlockedByBanker(periodNo),
              );
            }
            return _debitBlockedByBanker(periodNo);
        }

        if (message != null && message.trim().isNotEmpty) {
          return DioErrorMessage.sanitizeUserText(
            message,
            fallback: DioErrorMessage.forApp(error),
          );
        }
      }
    }
    return DioErrorMessage.forApp(error);
  }

  static String fromBetting(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final code = _readCode(map)?.toUpperCase();
        final message = _readMessage(map);

        switch (code) {
          case 'NO_IM_MESSAGES':
          case 'NO_ROUND_MESSAGES':
          case 'NO_MESSAGES':
            return _noImMessages();
        }

        if (message != null && message.trim().isNotEmpty) {
          if (message.contains('尚无 IM 消息') ||
              message.contains('尚無 IM 訊息') ||
              message.toLowerCase().contains('no im message')) {
            return _noImMessages();
          }
          return DioErrorMessage.sanitizeUserText(
            message,
            fallback: DioErrorMessage.forApp(error),
          );
        }
      }
    }
    return DioErrorMessage.forApp(error);
  }

  static String _noImMessages() {
    return AppI18n.current.t(
      zhHans: '本局尚无 IM 消息，请先等待下注消息或长按指定截止消息',
      zhHant: '本局尚無 IM 訊息，請先等待下注訊息或長按指定截止訊息',
      en: 'No IM messages in this round. Wait for bets or long-press a message',
    );
  }

  static String _insufficientForDebit(Object? balance) {
    final i18n = AppI18n.current;
    final parsed = _readInt(balance);
    if (parsed != null) {
      return i18n.format(
        zhHans: '余额不足，无法下分（当前可下分 $parsed）',
        zhHant: '餘額不足，無法下分（當前可下分 $parsed）',
        en: 'Insufficient balance for debit (available: $parsed)',
        ja: '残高不足のため下分できません（利用可能: $parsed）',
        ko: '잔액 부족으로 하분할 수 없습니다（가능: $parsed）',
        vars: {'balance': '$parsed'},
      );
    }
    return i18n.t(
      zhHans: '余额不足，无法下分',
      zhHant: '餘額不足，無法下分',
      en: 'Insufficient balance for debit',
      ja: '残高不足のため下分できません',
      ko: '잔액 부족으로 하분할 수 없습니다',
    );
  }

  static String _debitBlockedByBanker(Object? periodNo) {
    final i18n = AppI18n.current;
    final period = _readInt(periodNo);
    if (period != null && period > 0) {
      return i18n.format(
        zhHans: '第 $period 期庄/合庄对局未结算，暂不可下分',
        zhHant: '第 $period 期莊/合莊對局未結算，暫不可下分',
        en: 'Unsettled banker/co-bank round (period $period). Debit blocked',
        ja: '第 $period 期の庄/合庄が未精算のため下分できません',
        ko: '제 $period 회 차庄/합장 미정산으로 하분할 수 없습니다',
        vars: {'period': '$period'},
      );
    }
    return i18n.t(
      zhHans: '当前有未结算的庄/合庄对局，暂不可下分',
      zhHant: '當前有未結算的莊/合莊對局，暫不可下分',
      en: 'Unsettled banker/co-bank round. Debit blocked',
      ja: '未精算の庄/合庄対局があるため下分できません',
      ko: '미정산 차庄/합장 대국이 있어 하분할 수 없습니다',
    );
  }

  static String? _readCode(Map<String, dynamic> map) {
    for (final key in const ['code', 'errorCode', 'errCode']) {
      final value = map[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    final inner = map['data'];
    if (inner is Map) {
      return _readCode(Map<String, dynamic>.from(inner));
    }
    return null;
  }

  static String? _readMessage(Map<String, dynamic> map) {
    for (final key in const ['message', 'msg', 'error', 'desc', 'detail']) {
      final value = map[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    final inner = map['data'];
    if (inner is Map) {
      return _readMessage(Map<String, dynamic>.from(inner));
    }
    return null;
  }

  static int? _readInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return int.tryParse(raw?.toString() ?? '');
  }
}
