import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class StorageUtils {
  static const String customStoragePathKey = 'custom_storage_path';

  static Future<String?> loadStoragePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(customStoragePathKey);
  }

  static Future<void> saveStoragePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(customStoragePathKey, path);
  }

  static Future<String> getDefaultStoragePath() async {
    Directory? directory;
    try {
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      return path.join(directory!.path, 'LogRecordApp');
    } catch (e) {
      // 如果无法获取外部存储,回退到应用数据目录
      directory = await getApplicationDocumentsDirectory();
      return path.join(directory.path, 'LogRecordApp');
    }
  }

  static Future<bool> requestAllFilePermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      Permission.camera,
      Permission.microphone,
      Permission.photos,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  static Future<bool> ensureDirectoryExists(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!(await dir.exists())) {
        await dir.create(recursive: true);
      }
      // 创建子目录
      await Directory(path.join(dirPath, 'images')).create(recursive: true);
      // 移除音频目录
      return true;
    } catch (e) {
      debugPrint('Error creating directory: $e');
      return false;
    }
  }

  static Future<String?> copyImageToLocal(
      String sourcePath, String storagePath) async {
    try {
      final dir = Directory(path.join(storagePath, 'images'));
      if (!(await dir.exists())) {
        await dir.create(recursive: true);
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final targetPath = path.join(dir.path, fileName);

      final sourceFile = File(sourcePath);
      await sourceFile.copy(targetPath);

      return fileName;
    } catch (e) {
      debugPrint('Error copying image: $e');
      return null;
    }
  }

  static Future<String> getFullImagePath(
      String fileName, String storagePath) async {
    return path.join(storagePath, 'images', fileName);
  }

  static Future<bool> showInitialStorageDialog(BuildContext context) async {
    final defaultPath = await getDefaultStoragePath();
    final shouldContinue = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('存储位置设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('您需要设置日志存储位置。默认路径为:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  defaultPath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('您可以使用默认路径或设置自定义路径。'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('退出'),
            ),
            TextButton(
              onPressed: () async {
                await saveStoragePath(defaultPath);
                await ensureDirectoryExists(defaultPath);
                if (context.mounted) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('使用默认路径'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context, false);
                if (context.mounted) {
                  await showStorageSettings(context);
                }
              },
              child: const Text('自定义路径'),
            ),
          ],
        );
      },
    );

    return shouldContinue ?? false;
  }

  static Future<void> showStorageSettings(BuildContext context) async {
    final storagePath = await loadStoragePath();
    final defaultPath = await getDefaultStoragePath();
    final currentPath = storagePath ?? defaultPath;
    String newPath = currentPath;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('存储位置设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('当前存储路径:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  currentPath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('选择新的存储路径:'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: newPath),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        newPath = value;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: () async {
                      String? selectedDirectory =
                          await FilePicker.platform.getDirectoryPath();
                      if (selectedDirectory != null) {
                        newPath = selectedDirectory;
                        // 更新TextField
                        if (context.mounted) {
                          (context.findRenderObject() as RenderBox)
                              .markNeedsPaint();
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                await saveStoragePath(defaultPath);
                await ensureDirectoryExists(defaultPath);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('恢复默认'),
            ),
            TextButton(
              onPressed: () async {
                if (newPath.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('存储路径不能为空')),
                  );
                  return;
                }

                final success = await ensureDirectoryExists(newPath);
                if (!success) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('无法创建目录,请检查路径或权限')),
                    );
                  }
                  return;
                }

                await saveStoragePath(newPath);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('存储位置已更新')),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }
}
