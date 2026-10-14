import 'dart:async';

import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../feedback/network_recovery_progress.dart';

/// Prepares the route inside the mounted app, before the first SDK init.
/// Retries only network preparation: local stores, bindings and routes survive.
class StartupNetworkPreparation extends GetxService {
  StartupNetworkPreparation({
    required this.prepareNetwork,
    NetworkRecoveryProgress? progress,
    this.retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ],
  }) : progress = progress ?? NetworkRecoveryProgress.instance;

  final Future<void> Function(void Function() onShieldStarting) prepareNetwork;
  final NetworkRecoveryProgress progress;
  final List<Duration> retryDelays;
  Future<void>? _pending;
  Timer? _retry;
  Completer<void>? _retryWait;
  NetworkRecoveryOperation? _feedback;
  bool _closed = false;
  bool ready = false;

  Future<void> prepare() => _pending ??= _prepare();

  Future<void> _prepare() async {
    if (_closed) return;
    final feedback = _feedback = progress.begin(NetworkRecoveryStage.checking,
        context: NetworkRecoveryContext.startup);
    var failures = 0;
    try {
      while (!_closed) {
        try {
          await prepareNetwork(() {
            if (!_closed) feedback.update(NetworkRecoveryStage.startingShield);
          });
          if (_closed) return;
          // HttpUtil's interceptors were installed once during local bootstrap.
          dio.options.baseUrl = Config.imApiUrl;
          ready = true;
          return;
        } catch (error) {
          if (_closed) return;
          Logger.print('Startup route preparation: ${error.runtimeType}');
          feedback.update(NetworkRecoveryStage.retrying);
          final wait = _retryWait = Completer<void>();
          _retry = Timer(retryDelays[failures], wait.complete);
          if (failures < retryDelays.length - 1) failures++;
          await wait.future;
          _retryWait = null;
        }
      }
    } finally {
      feedback.close();
    }
  }

  @override
  void onClose() {
    _closed = true;
    _retry?.cancel();
    final wait = _retryWait;
    if (wait != null && !wait.isCompleted) wait.complete();
    _feedback?.close();
    super.onClose();
  }
}
