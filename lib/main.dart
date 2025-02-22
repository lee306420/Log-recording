import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '日志记录',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      home: const LogListPage(),
    );
  }
}

class LogListPage extends StatefulWidget {
  const LogListPage({super.key});

  @override
  State<LogListPage> createState() => _LogListPageState();
}

class _LogListPageState extends State<LogListPage> {
  final List<LogEntry> _logs = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  DateTime? _selectedDate;
  String? _customStoragePath;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestAllFilePermissions();
      await _loadStoragePath();
      if (_customStoragePath == null) {
        await _showInitialStorageDialog(context);
      }
      await _loadLogs();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<LogEntry> get _filteredLogs {
    List<LogEntry> logs = _logs;

    if (_selectedDate != null) {
      logs = logs.where((log) {
        final logDate = DateTime(
          log.timestamp.year,
          log.timestamp.month,
          log.timestamp.day,
        );
        final selectedDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
        );
        return logDate.isAtSameMomentAs(selectedDate);
      }).toList();
    }

    if (_searchQuery.isEmpty) {
      return logs;
    }
    return logs.where((log) {
      final text = log.text.toLowerCase();
      final query = _searchQuery.toLowerCase();
      return text.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的日记'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder),
            onPressed: () => _showStorageSettings(context),
            tooltip: '存储位置设置',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                locale: const Locale('zh'),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: Colors.blue,
                            surface: Colors.white,
                          ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() {
                  _selectedDate = picked;
                });
              }
            },
            tooltip: '选择日期',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56.0),
          child: Column(
            children: [
              if (_selectedDate != null)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${DateFormat('yyyy年MM月dd日').format(_selectedDate!)} 的日志',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索日志内容...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: _filteredLogs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _logs.isEmpty ? '还没有日志记录' : '没有找到相关日志',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _filteredLogs.length,
              itemBuilder: (context, index) {
                final log = _filteredLogs[index];
                return TimelineEntry(
                  log: log,
                  isFirst: index == 0,
                  isLast: index == _filteredLogs.length - 1,
                  onEdit: () => _editLog(
                    context,
                    _logs.indexOf(log),
                    log,
                  ),
                  onDelete: () => _deleteLog(_logs.indexOf(log)),
                );
              },
            ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'text',
              onPressed: () async {
                String text = '';
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (BuildContext context) {
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              decoration: const InputDecoration(
                                hintText: '写下此刻的想法...',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 3,
                              onChanged: (value) => text = value,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                if (text.isNotEmpty) {
                                  Navigator.pop(context);
                                  setState(() {
                                    _logs.add(LogEntry(
                                      text: text,
                                      timestamp: DateTime.now(),
                                    ));
                                  });
                                  _saveLogs();
                                }
                              },
                              child: const Text('保存'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              child: const Icon(Icons.edit_note),
            ),
            const SizedBox(height: 16),
            FloatingActionButton(
              heroTag: 'gallery',
              onPressed: () async {
                // 显示选择对话框
                final choice = await showDialog<String>(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text(
                        '选择类型',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.photo,
                                color: Colors.blue,
                                size: 28,
                              ),
                            ),
                            title: const Text(
                              '选择图片',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onTap: () => Navigator.pop(context, 'image'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            hoverColor: Colors.blue.shade50,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.video_library,
                                color: Colors.purple,
                                size: 28,
                              ),
                            ),
                            title: const Text(
                              '选择视频',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onTap: () => Navigator.pop(context, 'video'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            hoverColor: Colors.purple.shade50,
                          ),
                        ],
                      ),
                    );
                  },
                );

                if (choice == null) return;

                final ImagePicker picker = ImagePicker();
                if (choice == 'image') {
                  final XFile? photo = await picker.pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 100,
                  );
                  if (photo != null) {
                    final imagePath = await _copyImageToLocal(photo.path);
                    if (imagePath != null) {
                      String text = '';
                      await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (BuildContext context) {
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).viewInsets.bottom,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    decoration: const InputDecoration(
                                      hintText: '为这张照片添加描述...',
                                      border: OutlineInputBorder(),
                                    ),
                                    maxLines: 3,
                                    onChanged: (value) => text = value,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      setState(() {
                                        _logs.add(LogEntry(
                                          text: text,
                                          imagePath: imagePath,
                                          timestamp: DateTime.now(),
                                        ));
                                      });
                                      _saveLogs();
                                    },
                                    child: const Text('保存'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }
                  }
                } else if (choice == 'video') {
                  final XFile? video = await picker.pickVideo(
                    source: ImageSource.gallery,
                    maxDuration: const Duration(minutes: 10),
                  );
                  if (video != null) {
                    final videoPath = await _copyVideoToLocal(video.path);
                    if (videoPath != null) {
                      String text = '';
                      await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (BuildContext context) {
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).viewInsets.bottom,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    decoration: const InputDecoration(
                                      hintText: '为这段视频添加描述...',
                                      border: OutlineInputBorder(),
                                    ),
                                    maxLines: 3,
                                    onChanged: (value) => text = value,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      setState(() {
                                        _logs.add(LogEntry(
                                          text: text,
                                          videoPath: videoPath,
                                          timestamp: DateTime.now(),
                                        ));
                                      });
                                      _saveLogs();
                                    },
                                    child: const Text('保存'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }
                  }
                }
              },
              child: const Icon(Icons.photo_library),
            ),
            const SizedBox(height: 16),
            FloatingActionButton(
              heroTag: 'camera',
              onPressed: () async {
                final ImagePicker picker = ImagePicker();
                final XFile? photo = await picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 100,
                  preferredCameraDevice: CameraDevice.rear,
                );
                if (photo != null) {
                  final imagePath = await _copyImageToLocal(photo.path);
                  if (imagePath != null) {
                    String text = '';
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (BuildContext context) {
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  decoration: const InputDecoration(
                                    hintText: '为这张照片添加描述...',
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLines: 3,
                                  onChanged: (value) => text = value,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    setState(() {
                                      _logs.add(LogEntry(
                                        text: text,
                                        imagePath: imagePath,
                                        timestamp: DateTime.now(),
                                      ));
                                    });
                                    _saveLogs();
                                  },
                                  child: const Text('保存'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }
                }
              },
              child: const Icon(Icons.camera_alt),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Future<void> _addNewLog(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    String? imagePath;
    String? videoPath;
    String text = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: '写下此刻的想法...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  onChanged: (value) => text = value,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    SizedBox(
                      width: 100,
                      child: PopupMenuButton<ImageSource>(
                        onSelected: (ImageSource source) async {
                          final XFile? photo = await picker.pickImage(
                            source: source,
                            imageQuality: 100,
                            preferredCameraDevice: CameraDevice.rear,
                          );
                          if (photo != null) {
                            imagePath = await _copyImageToLocal(photo.path);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: ImageSource.camera,
                            child: Row(
                              children: [
                                Icon(Icons.camera_alt),
                                SizedBox(width: 10),
                                Text('拍照'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: ImageSource.gallery,
                            child: Row(
                              children: [
                                Icon(Icons.photo_library),
                                SizedBox(width: 10),
                                Text('从相册选择'),
                              ],
                            ),
                          ),
                        ],
                        child: ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('添加图片'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: PopupMenuButton<ImageSource>(
                        onSelected: (ImageSource source) async {
                          final XFile? video = await picker.pickVideo(
                            source: source,
                            maxDuration: const Duration(minutes: 10),
                            preferredCameraDevice: CameraDevice.rear,
                          );
                          if (video != null) {
                            videoPath = await _copyVideoToLocal(video.path);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: ImageSource.camera,
                            child: Row(
                              children: [
                                Icon(Icons.videocam),
                                SizedBox(width: 10),
                                Text('录制视频'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: ImageSource.gallery,
                            child: Row(
                              children: [
                                Icon(Icons.video_library),
                                SizedBox(width: 10),
                                Text('从相册选择'),
                              ],
                            ),
                          ),
                        ],
                        child: ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.video_library),
                          label: const Text('添加视频'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (text.isNotEmpty ||
                              imagePath != null ||
                              videoPath != null) {
                            setState(() {
                              _logs.add(LogEntry(
                                text: text,
                                imagePath: imagePath,
                                videoPath: videoPath,
                                timestamp: DateTime.now(),
                              ));
                            });
                            await _saveLogs();
                            Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('完成'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(40),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editLog(BuildContext context, int index, LogEntry log) async {
    String text = log.text;
    final String? imagePath = log.imagePath;
    final String? videoPath = log.videoPath;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: '写下此刻的想法...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  controller: TextEditingController(text: text),
                  onChanged: (value) => text = value,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    if (text.isNotEmpty ||
                        imagePath != null ||
                        videoPath != null) {
                      setState(() {
                        _logs[index] = LogEntry(
                          text: text,
                          imagePath: imagePath,
                          videoPath: videoPath,
                          timestamp: log.timestamp,
                        );
                      });
                      await _saveLogs();
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('保存'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteLog(int index) async {
    final imagePath = _logs[index].imagePath;
    final videoPath = _logs[index].videoPath;
    setState(() {
      _logs.removeAt(index);
    });
    await _deleteImage(imagePath);
    await _deleteVideo(videoPath);
    await _saveLogs();
  }

  Future<String> get _logsFilePath async {
    if (_customStoragePath == null) {
      throw Exception('存储路径未设置');
    }
    return '$_customStoragePath/logs.json';
  }

  Future<String> get _imagesDirectory async {
    if (_customStoragePath == null) {
      throw Exception('存储路径未设置');
    }
    final imagesDir = Directory('$_customStoragePath/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir.path;
  }

  Future<String> get _videosDirectory async {
    if (_customStoragePath == null) {
      throw Exception('存储路径未设置');
    }
    final videosDir = Directory('$_customStoragePath/videos');
    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
    }
    return videosDir.path;
  }

  Future<void> _loadLogs() async {
    try {
      final file = File(await _logsFilePath);
      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> jsonList = json.decode(contents);
        setState(() {
          _logs.clear();
          _logs.addAll(
            jsonList.map((json) => LogEntry.fromJson(json)).toList(),
          );
        });
      }
    } catch (e) {
      debugPrint('加载日志失败: $e');
    }
  }

  Future<void> _saveLogs() async {
    try {
      final file = File(await _logsFilePath);
      final jsonList = _logs.map((log) => log.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));
    } catch (e) {
      debugPrint('保存日志失败: $e');
    }
  }

  Future<String?> _copyImageToLocal(String originalPath) async {
    try {
      final imagesDir = await _imagesDirectory;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final newPath = '$imagesDir/$fileName';
      await File(originalPath).copy(newPath);
      return fileName;
    } catch (e) {
      debugPrint('复制图片失败: $e');
      return null;
    }
  }

  Future<String?> _copyVideoToLocal(String originalPath) async {
    try {
      final videosDir = await _videosDirectory;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.mp4';
      final newPath = '$videosDir/$fileName';
      await File(originalPath).copy(newPath);
      return fileName;
    } catch (e) {
      debugPrint('复制视频失败: $e');
      return null;
    }
  }

  Future<void> _deleteImage(String? fileName) async {
    if (fileName == null) return;
    try {
      final imagesDir = await _imagesDirectory;
      final file = File('$imagesDir/$fileName');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('删除图片失败: $e');
    }
  }

  Future<void> _deleteVideo(String? fileName) async {
    if (fileName == null) return;
    try {
      final videosDir = await _videosDirectory;
      final file = File('$videosDir/$fileName');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('删除视频失败: $e');
    }
  }

  Future<String> getFullImagePath(String fileName) async {
    final imagesDir = await _imagesDirectory;
    return '$imagesDir/$fileName';
  }

  Future<String> getFullVideoPath(String fileName) async {
    final videosDir = await _videosDirectory;
    return '$videosDir/$fileName';
  }

  Future<void> _requestAllFilePermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        if (context.mounted) {
          final shouldRequest = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('需要存储权限'),
              content: const Text('为了保存照片和视频，应用需要访问存储空间的权限。请在接下来的系统对话框中授予权限。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确定'),
                ),
              ],
            ),
          );

          if (shouldRequest ?? false) {
            await Permission.manageExternalStorage.request();

            if (!await Permission.manageExternalStorage.isGranted) {
              if (context.mounted) {
                final openSettings = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('权限被拒绝'),
                    content: const Text('没有存储权限，应用可能无法正常工作。是否前往设置页面开启权限？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('去设置'),
                      ),
                    ],
                  ),
                );

                if (openSettings ?? false) {
                  await openAppSettings();
                }
              }
            }
          }
        }
      }
    }
  }

  Future<void> _showStorageSettings(BuildContext context) async {
    final String? selectedDirectory = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('存储位置设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前位置: $_customStoragePath'),
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('更改位置'),
                onPressed: () async {
                  await _requestAllFilePermissions();
                  String? selectedDirectory =
                      await FilePicker.platform.getDirectoryPath();
                  if (selectedDirectory != null && context.mounted) {
                    Navigator.of(context).pop(selectedDirectory);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    if (selectedDirectory != null && selectedDirectory != _customStoragePath) {
      setState(() {
        _customStoragePath = selectedDirectory;
        _logs.clear();
      });
      await _saveStoragePath();
      await _loadLogs();
    }
  }

  Future<void> _saveStoragePath() async {
    final prefs = await SharedPreferences.getInstance();
    if (_customStoragePath != null) {
      await prefs.setString('storage_path', _customStoragePath!);
    } else {
      await prefs.remove('storage_path');
    }
  }

  Future<void> _loadStoragePath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString('storage_path');

      if (savedPath != null) {
        final directory = Directory(savedPath);
        if (await directory.exists()) {
          setState(() {
            _customStoragePath = savedPath;
          });
          return;
        }
      }

      setState(() {
        _customStoragePath = null;
      });
      await prefs.remove('storage_path');
    } catch (e) {
      debugPrint('加载存储路径失败: $e');
      setState(() {
        _customStoragePath = null;
      });
    }
  }

  Future<void> _showInitialStorageDialog(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: const Text('选择存储位置'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('请选择日志和图片的存储位置'),
                const SizedBox(height: 16),
                TextButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('选择位置'),
                  onPressed: () async {
                    await _requestAllFilePermissions();
                    String? selectedDirectory =
                        await FilePicker.platform.getDirectoryPath();
                    if (selectedDirectory != null && context.mounted) {
                      setState(() {
                        _customStoragePath = selectedDirectory;
                      });
                      await _saveStoragePath();
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('定位服务未开启'),
            content: const Text('请在系统设置中开启定位服务'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('定位权限被永久拒绝'),
            content: const Text('请在系统设置中开启定位权限'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  await Geolocator.openAppSettings();
                  Navigator.pop(context);
                },
                child: const Text('去设置'),
              ),
            ],
          ),
        );
      }
      return;
    }
  }

  Future<Position?> _getCurrentLocation() async {
    try {
      await _requestLocationPermission();
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('获取位置失败: $e');
      return null;
    }
  }

  Future<void> _addLogWithLocation({
    required String text,
    String? imagePath,
    String? videoPath,
  }) async {
    final position = await _getCurrentLocation();
    setState(() {
      _logs.add(LogEntry(
        text: text,
        imagePath: imagePath,
        videoPath: videoPath,
        timestamp: DateTime.now(),
        latitude: position?.latitude,
        longitude: position?.longitude,
      ));
    });
    await _saveLogs();
  }
}

class TimelineEntry extends StatefulWidget {
  final LogEntry log;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TimelineEntry({
    super.key,
    required this.log,
    this.isFirst = false,
    this.isLast = false,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<TimelineEntry> createState() => _TimelineEntryState();
}

class _TimelineEntryState extends State<TimelineEntry> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  static final Map<String, VideoPlayerController> _controllerCache = {};

  @override
  void initState() {
    super.initState();
    if (widget.log.videoPath != null) {
      _initializeVideoController();
    }
  }

  @override
  void didUpdateWidget(TimelineEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.log.videoPath != oldWidget.log.videoPath) {
      _disposeController();
      if (widget.log.videoPath != null) {
        _initializeVideoController();
      }
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    if (_videoController != null) {
      if (!_controllerCache.containsValue(_videoController)) {
        _videoController!.dispose();
      }
      _videoController = null;
      _isVideoInitialized = false;
    }
  }

  Future<void> _initializeVideoController() async {
    if (widget.log.videoPath == null) return;

    try {
      final logListState = context.findAncestorStateOfType<_LogListPageState>();
      if (logListState == null) return;

      final fullPath =
          await logListState.getFullVideoPath(widget.log.videoPath!);

      // 检查缓存
      if (_controllerCache.containsKey(fullPath)) {
        _videoController = _controllerCache[fullPath];
        _isVideoInitialized = true;
        if (mounted) setState(() {});
        return;
      }

      // 创建新控制器
      final controller = VideoPlayerController.file(File(fullPath));
      await controller.initialize();
      await controller.setVolume(0.0);
      await controller.seekTo(Duration.zero);

      // 缓存控制器
      _controllerCache[fullPath] = controller;

      if (!mounted) {
        controller.dispose();
        return;
      }

      _videoController = controller;
      _isVideoInitialized = true;
      setState(() {});

      // 清理旧的缓存
      if (_controllerCache.length > 5) {
        final oldestKey = _controllerCache.keys.first;
        final oldestController = _controllerCache.remove(oldestKey);
        oldestController?.dispose();
      }
    } catch (e) {
      debugPrint('Error initializing video controller: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 60,
          margin: const EdgeInsets.only(left: 8),
          child: Stack(
            children: [
              SizedBox(
                height:
                    widget.log.imagePath != null || widget.log.videoPath != null
                        ? 280 // 有图片或视频时的高度
                        : 140, // 只有文本时的高度
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 29,
                      child: Container(
                        width: 2,
                        color: Colors.blue,
                      ),
                    ),
                    Positioned(
                      top: widget.log.imagePath != null ||
                              widget.log.videoPath != null
                          ? 90 // 有图片或视频时圆点的位置
                          : 45, // 只有文本时圆点的位置
                      left: 5,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.blue,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _getTimePeriod(widget.log.timestamp),
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.isFirst)
                      const Positioned(
                        top: 0,
                        left: 29,
                        child: SizedBox(
                          width: 2,
                          height: 50,
                          child: ColoredBox(color: Colors.white),
                        ),
                      ),
                    if (widget.isLast)
                      Positioned(
                        bottom: 0,
                        left: 29,
                        child: SizedBox(
                          width: 2,
                          height: 50,
                          child: ColoredBox(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Dismissible(
            key: ValueKey(widget.log.timestamp.toString()),
            direction: DismissDirection.endToStart,
            confirmDismiss: (direction) async {
              await showModalBottomSheet(
                context: context,
                builder: (BuildContext context) {
                  return Container(
                    height: 120,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  color: Colors.blue, size: 32),
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onEdit();
                              },
                            ),
                            const Text('编辑',
                                style: TextStyle(color: Colors.blue)),
                          ],
                        ),
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.red, size: 32),
                              onPressed: () {
                                Navigator.pop(context);
                                _showDeleteConfirmation(context);
                              },
                            ),
                            const Text('删除',
                                style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
              return false;
            },
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20.0),
              color: Colors.red[100],
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.swipe_left,
                    color: Colors.red,
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '左滑操作',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            child: GestureDetector(
              onDoubleTap: () async {
                if (widget.log.imagePath != null) {
                  final logListState =
                      context.findAncestorStateOfType<_LogListPageState>();
                  if (logListState == null) {
                    print('Error: Could not find _LogListPageState');
                    return;
                  }

                  try {
                    final fullPath = await logListState
                        .getFullImagePath(widget.log.imagePath!);
                    print('Full image path: $fullPath');

                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ImagePreviewPage(
                            imagePath: fullPath,
                            timestamp: widget.log.timestamp,
                            text: widget.log.text,
                          ),
                        ),
                      );
                    }
                  } catch (error) {
                    print('Error getting full image path: $error');
                  }
                } else if (widget.log.videoPath != null) {
                  final logListState =
                      context.findAncestorStateOfType<_LogListPageState>();
                  if (logListState == null) {
                    print('Error: Could not find _LogListPageState');
                    return;
                  }

                  try {
                    final fullPath = await logListState
                        .getFullVideoPath(widget.log.videoPath!);
                    print('Full video path: $fullPath');

                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VideoPreviewPage(
                            videoPath: fullPath,
                            timestamp: widget.log.timestamp,
                            text: widget.log.text,
                          ),
                        ),
                      );
                    }
                  } catch (error) {
                    print('Error getting full video path: $error');
                  }
                }
              },
              child: Card(
                margin: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                elevation: 8,
                shadowColor: Colors.blue.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        Colors.blue.shade50.withOpacity(0.5),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.9),
                        blurRadius: 15,
                        offset: const Offset(-5, -5),
                      ),
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(5, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.log.imagePath != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                          child: Stack(
                            children: [
                              _buildImage(context),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withOpacity(0.3),
                                      ],
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    DateFormat('MM月dd日 HH:mm')
                                        .format(widget.log.timestamp),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                          offset: Offset(1, 1),
                                          blurRadius: 2,
                                          color: Colors.black26,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (widget.log.videoPath != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                          child: Stack(
                            children: [
                              _buildVideoThumbnail(context),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withOpacity(0.3),
                                      ],
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.videocam,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        DateFormat('MM月dd日 HH:mm')
                                            .format(widget.log.timestamp),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          shadows: [
                                            Shadow(
                                              offset: Offset(1, 1),
                                              blurRadius: 2,
                                              color: Colors.black26,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ClipRRect(
                        borderRadius: BorderRadius.vertical(
                          top: widget.log.imagePath == null &&
                                  widget.log.videoPath == null
                              ? const Radius.circular(16)
                              : Radius.zero,
                          bottom: const Radius.circular(16),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white,
                                Colors.grey.shade50,
                              ],
                            ),
                          ),
                          child: Text(
                            widget.log.text,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage(BuildContext context) {
    return FutureBuilder<String>(
      future: context
          .findAncestorStateOfType<_LogListPageState>()!
          .getFullImagePath(widget.log.imagePath!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            height: 200,
            color: Colors.grey[100],
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        return Hero(
          tag: widget.log.imagePath!,
          child: Image.file(
            File(snapshot.data!),
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 200,
                color: Colors.grey[200],
                child: const Center(
                  child: Icon(
                    Icons.broken_image,
                    size: 48,
                    color: Colors.grey,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildVideoThumbnail(BuildContext context) {
    if (!_isVideoInitialized || _videoController == null) {
      return Container(
        height: 200,
        color: Colors.grey[100],
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Stack(
      children: [
        SizedBox(
          height: 200,
          width: double.infinity,
          child: VideoPlayer(_videoController!),
        ),
        Container(
          height: 200,
          width: double.infinity,
          color: Colors.black.withOpacity(0.3),
          child: const Center(
            child: Icon(
              Icons.play_circle_outline,
              color: Colors.white,
              size: 64,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: const Text('确定要删除这条日志吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onDelete();
              },
              child: const Text(
                '删除',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  String _getTimePeriod(DateTime time) {
    final hour = time.hour;
    if (hour >= 5 && hour < 12) {
      return '早上';
    } else if (hour >= 12 && hour < 18) {
      return '下午';
    } else if (hour >= 18 && hour < 23) {
      return '晚上';
    } else {
      return '凌晨';
    }
  }
}

class LogEntry {
  final String text;
  final String? imagePath;
  final String? videoPath;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? address;

  LogEntry({
    required this.text,
    this.imagePath,
    this.videoPath,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.address,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'imagePath': imagePath != null ? path.basename(imagePath!) : null,
        'videoPath': videoPath != null ? path.basename(videoPath!) : null,
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
        timestamp: DateTime.parse(json['timestamp'] as String),
        latitude: json['latitude'] as double?,
        longitude: json['longitude'] as double?,
        address: json['address'] as String?,
      );
}

class ImagePreviewPage extends StatelessWidget {
  final String imagePath;
  final DateTime timestamp;
  final String text;

  const ImagePreviewPage({
    super.key,
    required this.imagePath,
    required this.timestamp,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    print('ImagePreviewPage imagePath: $imagePath');
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy年MM月dd日').format(timestamp),
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              DateFormat('HH:mm').format(timestamp),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Hero(
                  tag: imagePath,
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          if (text.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.black.withOpacity(0.7),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class VideoPreviewPage extends StatefulWidget {
  final String videoPath;
  final DateTime timestamp;
  final String text;

  const VideoPreviewPage({
    super.key,
    required this.videoPath,
    required this.timestamp,
    required this.text,
  });

  @override
  State<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<VideoPreviewPage> {
  late VideoPlayerController _videoPlayerController;
  late ChewieController _chewieController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoPlayerController = VideoPlayerController.file(File(widget.videoPath));
    await _videoPlayerController.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController.value.aspectRatio,
    );
    setState(() {
      _initialized = true;
    });
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy年MM月dd日').format(widget.timestamp),
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              DateFormat('HH:mm').format(widget.timestamp),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _initialized
                ? Chewie(controller: _chewieController)
                : const Center(child: CircularProgressIndicator()),
          ),
          if (widget.text.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.black.withOpacity(0.7),
              child: Text(
                widget.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
