class CallPermissionDenied implements Exception {
  const CallPermissionDenied(this.permission);
  final String permission;
}

class CallBusy implements Exception {
  const CallBusy();
}

class InvalidCallCertificate implements Exception {
  const InvalidCallCertificate();
}
