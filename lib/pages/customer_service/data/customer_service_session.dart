class CustomerServiceSession {
  const CustomerServiceSession({
    required this.identifier,
    required this.sourceId,
    required this.pubsubToken,
    required this.conversationId,
  });

  final String identifier;
  final String sourceId;
  final String pubsubToken;
  final String conversationId;
}
