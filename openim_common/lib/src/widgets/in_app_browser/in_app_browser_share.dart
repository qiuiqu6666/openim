/// App-owned recipient selection and message delivery.
class InAppBrowserShare {
  InAppBrowserShare._();
  static Future<int> Function(Uri uri, String? title)? send;
}
