import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

import '../../services/platform_config_service.dart';
import 'data/data.dart';
import 'models/customer_service_chat_entry.dart';
import 'history/customer_service_history_merge.dart';

typedef CustomerServiceCableFactory = CustomerServiceCable Function(
    void Function(CustomerServiceMessage) onMessage,
    void Function(bool) onTyping,
    VoidCallback onConnected,
    VoidCallback onDisconnected);

/// One sheet owns its transport, visitor session and pending sends.
class CustomerServiceController extends ChangeNotifier {
  CustomerServiceController({
    required this.api,
    required this.sessionStore,
    required this.isActive,
    required this.name,
    this.avatarUrl = '',
    CustomerServiceCableFactory? cableFactory,
    Future<String> Function()? officialURLLoader,
  }) : _officialURLLoader = officialURLLoader ?? _loadOfficialURL {
    _cable = cableFactory?.call(
            _onMessage, _onTyping, _onConnected, _onDisconnected) ??
        CustomerServiceCable(
          config: api.config,
          onMessage: _onMessage,
          onTyping: _onTyping,
          onConnected: _onConnected,
          onDisconnected: _onDisconnected,
        );
  }

  factory CustomerServiceController.forCurrentAccount({bool guest = false}) {
    final account = DataSp.userID ?? '';
    final token = DataSp.chatToken;
    bool active() =>
        (DataSp.userID ?? '') == account && DataSp.chatToken == token;
    UserInfo? profile;
    if (!guest && account.isNotEmpty) {
      try {
        profile = OpenIM.iMManager.userInfo;
      } catch (_) {}
    }
    final hasProfile = profile?.userID == account && account.isNotEmpty;
    final api = CustomerServiceApi();
    return CustomerServiceController(
      api: api,
      sessionStore: CustomerServiceSessionStore(
        api: api,
        accountId: guest ? '' : account,
        isActive: active,
      ),
      isActive: active,
      name: hasProfile && profile?.nickname?.trim().isNotEmpty == true
          ? profile!.nickname!.trim()
          : (account.isNotEmpty && !guest ? account : '访客'),
      avatarUrl: hasProfile ? profile?.faceURL ?? '' : '',
    );
  }

  final CustomerServiceApi api;
  final CustomerServiceSessionStore sessionStore;
  final bool Function() isActive;
  final String name, avatarUrl;
  final Future<String> Function() _officialURLLoader;
  late final CustomerServiceCable _cable;
  final _entries = <CustomerServiceChatEntry>[];
  final _posting = <String>{};
  CustomerServiceSession? _session;
  Future<void>? _initializing, _refreshing;
  Future<CustomerServiceSession>? _recoveringSession;
  Timer? _typingExpiry, _historyPolling;
  static const historyPollingInterval = Duration(seconds: 15);
  bool _disposed = false, _foreground = true, _cableAttached = false;
  int _generation = 0, _connectionRevision = 0;

  bool loading = true, historyReady = false, agentTyping = false;
  String? error;
  String officialURL = '';
  bool faqOpen = true;
  String selectedCategoryId = 'faq';
  String? questionId;
  List<CustomerServiceChatEntry> get entries => List.unmodifiable(_entries);
  bool get showFaq => faqOpen || (historyReady && _entries.isEmpty);
  bool get canSend => _live;
  bool get _live => !_disposed && isActive();

  static Future<String> _loadOfficialURL() async =>
      (await PlatformConfigService.fetch()).officialURL;

  Future<void> initialize() {
    if (!_live) return Future.value();
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initialize() async {
    final generation = _generation;
    loading = true;
    error = null;
    notifyListeners();
    unawaited(_fetchOfficialURL(generation));
    try {
      final session = await _ensureSession();
      if (!_current(generation)) return;
      _attachCable(session);
      await refresh();
      if (!_current(generation)) return;
      historyReady = true;
      faqOpen = _entries.isEmpty;
    } catch (_) {
      if (!_current(generation)) return;
      historyReady = true;
      error = 'connection';
    } finally {
      if (_current(generation)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _fetchOfficialURL(int generation) async {
    try {
      final value = await _officialURLLoader();
      if (_current(generation)) {
        officialURL = value.trim();
        notifyListeners();
      }
    } catch (_) {
      // FAQ remains usable when the public platform endpoint is unavailable.
    }
  }

  bool _current(int generation) => _live && _generation == generation;

  Future<CustomerServiceSession> _ensureSession() async {
    if (!_live) throw StateError('Customer service account ended');
    final recovery = _recoveringSession;
    final session = recovery != null
        ? await recovery
        : _session ??
            await sessionStore.ensure(name: name, avatarUrl: avatarUrl);
    if (!_live) throw StateError('Customer service account ended');
    _session = session;
    return session;
  }

  void _attachCable(CustomerServiceSession session) {
    if (!_live || !_foreground || _cableAttached) return;
    _cableAttached = true;
    _connectionRevision++;
    _startHistoryPolling();
    _cable.connect(
        pubsubToken: session.pubsubToken,
        conversationId: session.conversationId);
  }

  Future<void> refresh() {
    if (!_live) return Future.value();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final generation = _generation;
    var session = await _ensureSession();
    List<CustomerServiceMessage> messages;
    try {
      messages = await api.listMessages(
          contactId: session.sourceId, conversationId: session.conversationId);
    } catch (failure) {
      if (!CustomerServiceApi.isNotFound(failure) || !_current(generation)) {
        rethrow;
      }
      _cable.suspend();
      _cableAttached = false;
      _connectionRevision++;
      _historyPolling?.cancel();
      _historyPolling = null;
      _session = null;
      final work =
          sessionStore.recover(session, name: name, avatarUrl: avatarUrl);
      _recoveringSession = work;
      try {
        session = await work;
      } finally {
        if (identical(_recoveringSession, work)) _recoveringSession = null;
      }
      if (!_current(generation)) return;
      _session = session;
      // Old server history belongs to the rejected conversation. Keep drafts
      // and unsent entries, but do not automatically replay user messages.
      _entries.removeWhere((entry) => entry.message != null);
      notifyListeners();
      messages = await api.listMessages(
          contactId: session.sourceId, conversationId: session.conversationId);
      if (!_current(generation)) return;
      _attachCable(session);
    }
    if (!_current(generation)) return;
    final changed = _mergeBatch(messages);
    final hadError = error != null;
    error = null;
    if (changed || hadError) notifyListeners();
  }

  void _onConnected() {
    if (!_live || !_foreground) return;
    _historyPolling?.cancel();
    _historyPolling = null;
    final revision = _connectionRevision;
    final running = _refreshing;
    unawaited(Future<void>(() async {
      if (running != null) {
        try {
          await running;
        } catch (_) {}
      }
      if (!_live || !_foreground || revision != _connectionRevision) return;
      await refresh();
    }).catchError((Object _) {
      if (_live) {
        error = 'connection';
        notifyListeners();
      }
    }));
  }

  void _onDisconnected() {
    if (_live && _foreground) _startHistoryPolling();
  }

  void _startHistoryPolling() {
    if (_historyPolling != null || !_live || !_foreground) return;
    // Keep replies available when the approved deployment cannot upgrade its
    // realtime endpoint. A confirmed subscription disables this fallback.
    _historyPolling = Timer.periodic(historyPollingInterval, (_) {
      if (!_live || !_foreground) {
        _historyPolling?.cancel();
        _historyPolling = null;
        return;
      }
      unawaited(refresh().catchError((Object _) {
        if (_live && _foreground) {
          error = 'connection';
          notifyListeners();
        }
      }));
    });
  }

  void _onMessage(CustomerServiceMessage message) {
    if (!_live) {
      suspend();
      return;
    }
    if (_recoveringSession != null || _session == null) return;
    if (_merge(message)) notifyListeners();
  }

  bool _merge(CustomerServiceMessage message, {String? echoId}) =>
      _mergeBatch([message], echoId: echoId);

  bool _mergeBatch(Iterable<CustomerServiceMessage> messages,
      {String? echoId}) {
    final merged = mergeCustomerServiceHistory(_entries, messages,
        conversationId: _session?.conversationId, echoId: echoId);
    if (merged == null) return false;
    _entries
      ..clear()
      ..addAll(merged);
    return true;
  }

  void _onTyping(bool value) {
    if (!_live || !_foreground) return;
    _typingExpiry?.cancel();
    agentTyping = value;
    if (value) {
      _typingExpiry = Timer(const Duration(seconds: 8), () => _onTyping(false));
    }
    notifyListeners();
  }

  void selectCategory(String id) {
    if (!_live) return;
    selectedCategoryId = id;
    questionId = null;
    faqOpen = true;
    notifyListeners();
  }

  void selectQuestion(String? id) {
    if (!_live) return;
    questionId = id;
    notifyListeners();
  }

  void showQuestions(bool value) {
    if (!_live || faqOpen == value) return;
    faqOpen = value;
    notifyListeners();
  }

  Future<void> sendText(String raw) async {
    final text = raw;
    if (!_live || text.trim().isEmpty) return;
    final entry = CustomerServiceChatEntry(
        echoId: const Uuid().v4(),
        text: text,
        state: CustomerServiceSendState.sending);
    _enqueue(entry);
    await _post(entry);
  }

  Future<void> sendUpload(CustomerServiceUpload upload) async {
    if (!_live) return;
    final length = await File(upload.path).length();
    if (!_live) return;
    if (length <= 0 || length > CustomerServiceApi.maxAttachmentBytes) {
      throw StateError('Attachment must be between 1 byte and 40 MB');
    }
    final entry = CustomerServiceChatEntry(
        echoId: const Uuid().v4(),
        upload: upload,
        state: CustomerServiceSendState.sending);
    _enqueue(entry);
    await _post(entry);
  }

  void _enqueue(CustomerServiceChatEntry entry) {
    _entries.add(entry);
    faqOpen = false;
    notifyListeners();
  }

  Future<void> retry(CustomerServiceChatEntry entry) async {
    final current = _entries.where((item) => item.echoId == entry.echoId);
    if (!_live ||
        current.isEmpty ||
        current.first.state != CustomerServiceSendState.failed) {
      return;
    }
    _changeState(entry.echoId, CustomerServiceSendState.sending);
    await _post(entry);
  }

  void _changeState(String echoId, CustomerServiceSendState state) {
    final index = _entries.indexWhere((item) => item.echoId == echoId);
    if (index < 0 || _entries[index].message != null) return;
    _entries[index] = _entries[index].withState(state);
    notifyListeners();
  }

  Future<void> _post(CustomerServiceChatEntry entry) async {
    if (!_posting.add(entry.echoId)) return;
    final generation = _generation;
    try {
      final session = await _ensureSession();
      if (!_current(generation)) return;
      _attachCable(session);
      final upload = entry.upload;
      final message = upload == null
          ? await api.sendText(
              contactId: session.sourceId,
              conversationId: session.conversationId,
              content: entry.text,
              echoId: entry.echoId)
          : await api.sendAttachment(
              contactId: session.sourceId,
              conversationId: session.conversationId,
              echoId: entry.echoId,
              filename: upload.filename,
              path: upload.path,
              width: upload.width,
              height: upload.height,
              thumbnailPath: upload.thumbnailPath);
      if (!_current(generation)) return;
      final changed = _merge(message, echoId: entry.echoId);
      final hadError = error != null;
      error = null;
      if (changed || hadError) notifyListeners();
    } catch (failure) {
      if (!_current(generation)) return;
      if (CustomerServiceApi.isNotFound(failure)) {
        try {
          await refresh();
        } catch (_) {}
        if (!_current(generation)) return;
      }
      _changeState(entry.echoId, CustomerServiceSendState.failed);
    } finally {
      _posting.remove(entry.echoId);
    }
  }

  void suspend() {
    if (_disposed) return;
    _foreground = false;
    _cableAttached = false;
    _connectionRevision++;
    _cable.suspend();
    _typingExpiry?.cancel();
    _historyPolling?.cancel();
    _historyPolling = null;
    final changed = agentTyping;
    agentTyping = false;
    if (changed && _live) notifyListeners();
  }

  void resume() {
    if (!_live) return;
    _foreground = true;
    if (_session != null) _attachCable(_session!);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _typingExpiry?.cancel();
    _historyPolling?.cancel();
    _cable.dispose();
    sessionStore.dispose();
    api.dispose();
    super.dispose();
  }
}
