import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class LogEntry {
  final String text;
  final String? imagePath;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? address;

  LogEntry({
    required this.text,
    this.imagePath,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.address,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'imagePath': imagePath != null ? path.basename(imagePath!) : null,
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        text: json['text'] as String,
        imagePath:
            json['imagePath'] != null ? json['imagePath'] as String : null,
        timestamp: DateTime.parse(json['timestamp'] as String),
        latitude: json['latitude'] as double?,
        longitude: json['longitude'] as double?,
        address: json['address'] as String?,
      );
}
