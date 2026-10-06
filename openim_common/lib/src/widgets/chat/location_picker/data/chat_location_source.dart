import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

enum ChatLocationFailure {
  disabled,
  denied,
  deniedForever,
  timeout,
  unavailable
}

class ChatLocationException implements Exception {
  const ChatLocationException(this.failure);

  final ChatLocationFailure failure;

  @override
  String toString() => 'ChatLocationException(${failure.name})';
}

abstract interface class ChatLocationSource {
  /// Returns null when automatic lookup does not already have permission.
  Future<LatLng?> locate({required bool requestPermission});
}

class GeolocatorChatLocationSource implements ChatLocationSource {
  const GeolocatorChatLocationSource();

  @override
  Future<LatLng?> locate({required bool requestPermission}) async {
    try {
      LocationPermission permission;
      if (requestPermission) {
        await _ensureServiceEnabled();
        permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
      } else {
        permission = await Geolocator.checkPermission();
        if (!_hasPermission(permission)) return null;
        await _ensureServiceEnabled();
      }

      if (permission == LocationPermission.deniedForever) {
        throw const ChatLocationException(ChatLocationFailure.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        throw const ChatLocationException(ChatLocationFailure.denied);
      }
      if (!_hasPermission(permission)) {
        throw const ChatLocationException(ChatLocationFailure.unavailable);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 20),
        ),
      );
      final latitude = position.latitude;
      final longitude = position.longitude;
      if (!latitude.isFinite ||
          !longitude.isFinite ||
          latitude.abs() > 90 ||
          longitude.abs() > 180) {
        throw const ChatLocationException(ChatLocationFailure.unavailable);
      }
      return LatLng(latitude, longitude);
    } on ChatLocationException {
      rethrow;
    } on LocationServiceDisabledException {
      throw const ChatLocationException(ChatLocationFailure.disabled);
    } on PermissionDeniedException {
      throw const ChatLocationException(ChatLocationFailure.denied);
    } on TimeoutException {
      throw const ChatLocationException(ChatLocationFailure.timeout);
    } on PlatformException catch (error) {
      final failure = switch (error.code) {
        'LOCATION_SERVICES_DISABLED' => ChatLocationFailure.disabled,
        'PERMISSION_DENIED' => ChatLocationFailure.denied,
        _ => ChatLocationFailure.unavailable,
      };
      throw ChatLocationException(failure);
    } catch (_) {
      throw const ChatLocationException(ChatLocationFailure.unavailable);
    }
  }

  static bool _hasPermission(LocationPermission permission) =>
      permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;

  static Future<void> _ensureServiceEnabled() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ChatLocationException(ChatLocationFailure.disabled);
    }
  }
}
