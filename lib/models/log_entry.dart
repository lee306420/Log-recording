import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class LogEntry {
  final String text;
  final String? imagePath;
  final String? videoPath;
  final String? audioPath;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? address;

  LogEntry({
    required this.text,
    this.imagePath,
    this.videoPath,
    this.audioPath,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.address,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'imagePath': imagePath != null ? path.basename(imagePath!) : null,
        'videoPath': videoPath != null ? path.basename(videoPath!) : null,
        'audioPath': audioPath != null ? path.basename(audioPath!) : null,
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        text: json['text'] as String,
        imagePath:
            json['imagePath'] != null ? json['imagePath'] as String : null,
        videoPath:
            json['videoPath'] != null ? json['videoPath'] as String : null,
        audioPath:
            json['audioPath'] != null ? json['audioPath'] as String : null,
        timestamp: DateTime.parse(json['timestamp'] as String),
        latitude: json['latitude'] as double?,
        longitude: json['longitude'] as double?,
        address: json['address'] as String?,
      );
}
