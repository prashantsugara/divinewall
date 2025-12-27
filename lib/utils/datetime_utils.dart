import 'package:cloud_firestore/cloud_firestore.dart';

/// Utilities for safely converting Firestore date-like values into DateTime.
class DateTimeUtils {
  /// Accepts Firestore Timestamp, ISO8601 String, int (ms since epoch), or DateTime.
  /// Returns [fallback] (or DateTime.now) if value is null or unrecognized.
  static DateTime fromFirestore(dynamic value, {DateTime? fallback}) {
    if (value == null) return fallback ?? DateTime.now();
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    // Some environments may deliver a map-like timestamp shape
    // e.g. {seconds: 1714593650, nanoseconds: 0} or {_seconds: ..., _nanoseconds: ...}
    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanos = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000 + (nanos is int ? (nanos ~/ 1000000) : 0));
      }
    }
    if (value is int) {
      // Assume milliseconds since epoch
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return fallback ?? DateTime.now();
      }
    }
    return fallback ?? DateTime.now();
  }
}
