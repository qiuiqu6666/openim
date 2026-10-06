class DeviceSyncPreferences {
  // Inactive snapshot; signed-in account defaults are resolved by fromJson.
  const DeviceSyncPreferences({
    this.accountID = '',
    this.photos = false,
    this.videos = false,
    this.location = false,
    this.wifiOnly = true,
  });

  final String accountID;
  final bool photos, videos, location, wifiOnly;

  bool get enabled => photos || location;

  DeviceSyncPreferences copyWith({
    bool? photos,
    bool? videos,
    bool? location,
    bool? wifiOnly,
  }) =>
      DeviceSyncPreferences(
        accountID: accountID,
        photos: photos ?? this.photos,
        videos: videos ?? this.videos,
        location: location ?? this.location,
        wifiOnly: wifiOnly ?? this.wifiOnly,
      );

  Map<String, dynamic> toJson() => {
        'photos': photos,
        'videos': videos,
        'location': location,
        'wifiOnly': wifiOnly,
        // Keep the legacy marker so previously saved switch choices survive.
        'consentDecided': true,
        'version': 1,
      };

  factory DeviceSyncPreferences.fromJson(String accountID, dynamic value) {
    final json = value is Map ? value : const {};
    final hasSavedChoices =
        json['version'] == 1 && json['consentDecided'] == true;
    return DeviceSyncPreferences(
      accountID: accountID,
      photos: !hasSavedChoices || json['photos'] != false,
      videos: !hasSavedChoices || json['videos'] != false,
      location: !hasSavedChoices || json['location'] != false,
      wifiOnly: !hasSavedChoices || json['wifiOnly'] != false,
    );
  }
}

enum DeviceSyncStatus {
  inactive,
  waitingPermission,
  idle,
  scanning,
  uploading,
  paused,
  retrying,
}
