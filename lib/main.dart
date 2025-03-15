import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  bool _isSearchingAllDates = false;

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

    if (_searchQuery.isNotEmpty) {
      logs = logs.where((log) {
        final text = log.text.toLowerCase();
        final query = _searchQuery.toLowerCase();
        return text.contains(query);
      }).toList();
    }

    if (!_isSearchingAllDates && _selectedDate != null) {
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

    return logs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        title: Text(
          _selectedDate != null
              ? DateFormat('MM月dd日的日志').format(_selectedDate!)
              : '所有日志',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
            color: Colors.black87,
            shadows: [
              Shadow(
                offset: Offset(1, 1),
                blurRadius: 2.0,
                color: Colors.white24,
              ),
            ],
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder),
            iconSize: 24,
            padding: const EdgeInsets.all(12),
            onPressed: () => _showStorageSettings(context),
            tooltip: '存储位置设置',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            iconSize: 24,
            padding: const EdgeInsets.all(12),
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
          IconButton(
            icon: const Icon(Icons.date_range),
            iconSize: 30,
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: DateListDialog(
                      dates: _getUniqueDates(),
                      onSelectDate: (date) {
                        setState(() {
                          _selectedDate = date;
                        });
                        Navigator.pop(context);
                      },
                      getLogCount: _getLogCountForDate,
                    ),
                  );
                },
              );
            },
            tooltip: '所有日期',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56.0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: _isSearchingAllDates
                              ? '搜索全部日志...'
                              : '搜索当前日期的日志...',
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
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color:
                            _isSearchingAllDates ? Colors.blue : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.blue,
                          width: 1,
                        ),
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.all_inclusive,
                          color:
                              _isSearchingAllDates ? Colors.white : Colors.blue,
                        ),
                        tooltip: _isSearchingAllDates ? '仅搜索当前日期' : '搜索全部日期',
                        onPressed: () {
                          setState(() {
                            _isSearchingAllDates = !_isSearchingAllDates;
                            if (!_isSearchingAllDates) {
                              _searchController.clear();
                              _searchQuery = '';
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isSearchingAllDates && _searchQuery.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '请输入搜索内容',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : _filteredLogs.isEmpty
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
                await _addNewLog(context);
              },
              child: const Icon(Icons.edit_note),
            ),
            const SizedBox(height: 16),
            FloatingActionButton(
              heroTag: 'gallery',
              onPressed: () async {
                final ImagePicker picker = ImagePicker();
                final XFile? video = await picker.pickVideo(
                  source: ImageSource.camera,
                  maxDuration: const Duration(minutes: 10), // 限制视频最大时长为10分钟
                );
                if (video != null) {
                  final File videoFile = File(video.path);
                  final int fileSize = await videoFile.length();
                  final double fileSizeInMB = fileSize / (1024 * 1024);

                  if (fileSizeInMB > 500) {
                    if (context.mounted) {
                      final bool shouldContinue = await showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('文件过大'),
                              content: Text(
                                  '录制的视频文件大小为 ${fileSizeInMB.toStringAsFixed(2)}MB，建议录制较短的视频以获得更好的性能。是否继续？'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('继续'),
                                ),
                              ],
                            ),
                          ) ??
                          false;
                      if (!shouldContinue) return;
                    }
                  }

                  final videoPath = await _copyVideoToLocal(video.path);
                  if (videoPath != null) {
                    String text = '';
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (BuildContext context) {
                        return Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    const Text(
                                      '添加描述',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text(
                                        '取消',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Container(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.grey.shade200,
                                          width: 1,
                                        ),
                                      ),
                                      child: TextField(
                                        decoration: InputDecoration(
                                          hintText: '为这段视频添加描述...',
                                          hintStyle: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 16,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding:
                                              const EdgeInsets.all(16),
                                        ),
                                        maxLines: null,
                                        minLines: 3,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          height: 1.5,
                                          color: Colors.black87,
                                        ),
                                        onChanged: (value) => text = value,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: ValueListenableBuilder<String>(
                                        valueListenable:
                                            ValueNotifier<String>(text),
                                        builder: (context, value, child) {
                                          return Text(
                                            '${text.length} 字',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 14,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
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
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text(
                                          '保存',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }
                }
              },
              child: const Icon(Icons.videocam),
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
                      backgroundColor: Colors.transparent,
                      builder: (BuildContext context) {
                        return Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 顶部拖动条
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              // 标题栏
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    const Text(
                                      '添加描述',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text(
                                        '取消',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              // 内容区域
                              Container(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 输入框
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.grey.shade200,
                                          width: 1,
                                        ),
                                      ),
                                      child: TextField(
                                        decoration: InputDecoration(
                                          hintText: '为这张照片添加描述...',
                                          hintStyle: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 16,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding:
                                              const EdgeInsets.all(16),
                                        ),
                                        maxLines: null,
                                        minLines: 3,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          height: 1.5,
                                          color: Colors.black87,
                                        ),
                                        onChanged: (value) => text = value,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // 字数统计
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: ValueListenableBuilder<String>(
                                        valueListenable:
                                            ValueNotifier<String>(text),
                                        builder: (context, value, child) {
                                          return Text(
                                            '${text.length} 字',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 14,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    // 保存按钮
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
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
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text(
                                          '保存',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
    String text = '';
    final currentTime = DateTime.now();
    final timeTitle = DateFormat('MM月dd日 HH:mm').format(currentTime);

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          )),
          child: Material(
            color: Colors.transparent,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              resizeToAvoidBottomInset: true,
              body: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(-2, 0),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              offset: const Offset(0, 1),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                Navigator.pop(context);
                              },
                              color: Colors.grey[700],
                            ),
                            const Expanded(
                              child: Text(
                                '写日记',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                if (text.isNotEmpty) {
                                  FocusScope.of(context).unfocus();
                                  Future.delayed(
                                      const Duration(milliseconds: 100), () {
                                    Navigator.pop(context);
                                    setState(() {
                                      _logs.add(LogEntry(
                                        text: '[$timeTitle]\n$text',
                                        timestamp: currentTime,
                                      ));
                                    });
                                    _saveLogs();
                                  });
                                }
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: const Text(
                                '保存',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          color: Colors.grey[50],
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.03),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 时间标题部分
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 18,
                                            color: Colors.blue.shade700,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            timeTitle,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.blue.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    // 输入框部分
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.grey.shade200,
                                          width: 1,
                                        ),
                                      ),
                                      child: TextField(
                                        decoration: InputDecoration(
                                          hintText: '写下此刻的想法...',
                                          hintStyle: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 16,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding:
                                              const EdgeInsets.all(16),
                                        ),
                                        maxLines: null,
                                        minLines: 5,
                                        autofocus: true,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          height: 1.5,
                                          color: Colors.black87,
                                        ),
                                        onChanged: (value) => text = value,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // 字数统计
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: ValueListenableBuilder<String>(
                                        valueListenable:
                                            ValueNotifier<String>(text),
                                        builder: (context, value, child) {
                                          return Text(
                                            '${text.length} 字',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 14,
                                            ),
                                          );
                                        },
                                      ),
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
              ),
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
    final String? audioPath = log.audioPath;
    final timeTitle = DateFormat('MM月dd日 HH:mm').format(log.timestamp);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖动条
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题栏
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text(
                      '编辑日志',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 内容区域
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 时间标题
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 18,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeTitle,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 输入框
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: '写下此刻的想法...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        maxLines: null,
                        minLines: 5,
                        controller: TextEditingController(text: text),
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: Colors.black87,
                        ),
                        onChanged: (value) => text = value,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 字数统计
                    Align(
                      alignment: Alignment.centerRight,
                      child: ValueListenableBuilder<String>(
                        valueListenable: ValueNotifier<String>(text),
                        builder: (context, value, child) {
                          return Text(
                            '${text.length} 字',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 保存按钮
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (text.isNotEmpty ||
                              imagePath != null ||
                              videoPath != null ||
                              audioPath != null) {
                            setState(() {
                              _logs[index] = LogEntry(
                                text: text,
                                imagePath: imagePath,
                                videoPath: videoPath,
                                audioPath: audioPath,
                                timestamp: log.timestamp,
                              );
                            });
                            await _saveLogs();
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '保存修改',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteLog(int index) async {
    final imagePath = _logs[index].imagePath;
    final videoPath = _logs[index].videoPath;
    final audioPath = _logs[index].audioPath;
    setState(() {
      _logs.removeAt(index);
    });
    await _deleteImage(imagePath);
    await _deleteVideo(videoPath);
    await _deleteAudio(audioPath);
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

  Future<String> get _audiosDirectory async {
    if (_customStoragePath == null) {
      throw Exception('存储路径未设置');
    }
    final audiosDir = Directory('$_customStoragePath/audios');
    if (!await audiosDir.exists()) {
      await audiosDir.create(recursive: true);
    }
    return audiosDir.path;
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

  Future<String?> _copyAudioToLocal(String sourcePath) async {
    try {
      if (_customStoragePath == null) return null;

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}${path.extension(sourcePath)}';
      final audiosDir = await _audiosDirectory;
      final targetPath = '$audiosDir/$fileName';

      await File(sourcePath).copy(targetPath);
      return fileName; // 只返回文件名，不返回完整路径
    } catch (e) {
      print('Error copying audio: $e');
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

  Future<void> _deleteAudio(String? fileName) async {
    if (fileName == null) return;
    try {
      final audiosDir = await _audiosDirectory;
      final file = File('$audiosDir/$fileName');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('删除音频失败: $e');
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

  Future<String> getFullAudioPath(String fileName) async {
    final audiosDir = await _audiosDirectory;
    return '$audiosDir/$fileName';
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

  List<DateTime> _getUniqueDates() {
    final dates = _logs
        .map((log) => DateTime(
              log.timestamp.year,
              log.timestamp.month,
              log.timestamp.day,
            ))
        .toSet()
        .toList();

    dates.sort((a, b) => b.compareTo(a)); // 按日期降序排序
    return dates;
  }

  int _getLogCountForDate(DateTime date) {
    return _logs.where((log) {
      final logDate = DateTime(
        log.timestamp.year,
        log.timestamp.month,
        log.timestamp.day,
      );
      return logDate.isAtSameMomentAs(date);
    }).length;
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
}

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
          width: 80,
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
                    // 时间线竖线
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 39,
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.blue.shade300,
                              Colors.blue.shade400,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.2),
                              blurRadius: 3,
                              offset: const Offset(1, 0),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 时间点圆圈
                    Positioned(
                      top: widget.log.imagePath != null ||
                              widget.log.videoPath != null
                          ? 90 // 有图片或视频时圆点的位置
                          : 45, // 只有文本时圆点的位置
                      left: 15,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.blue.shade400,
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(2, 2),
                            ),
                            BoxShadow(
                              color: Colors.white,
                              blurRadius: 4,
                              offset: const Offset(-2, -2),
                            ),
                          ],
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              _getTimePeriod(widget.log.timestamp),
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 顶部连接线
                    if (widget.isFirst)
                      Positioned(
                        top: 0,
                        left: 39,
                        child: Container(
                          width: 2,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white,
                                Colors.blue.shade300,
                              ],
                            ),
                          ),
                        ),
                      ),
                    // 底部连接线
                    if (widget.isLast)
                      Positioned(
                        bottom: 0,
                        left: 39,
                        child: Container(
                          width: 2,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.blue.shade400,
                                Colors.white,
                              ],
                            ),
                          ),
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
                  } catch (e) {
                    print('Error getting full image path: $e');
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
                  } catch (e) {
                    print('Error getting full video path: $e');
                  }
                } else if (widget.log.audioPath != null) {
                  final logListState =
                      context.findAncestorStateOfType<_LogListPageState>();
                  if (logListState == null) {
                    print('Error: Could not find _LogListPageState');
                    return;
                  }

                  try {
                    final fullPath = await logListState
                        .getFullAudioPath(widget.log.audioPath!);
                    print('Full audio path: $fullPath');

                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AudioPreviewPage(
                            audioPath: fullPath,
                            timestamp: widget.log.timestamp,
                            text: widget.log.text,
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    print('Error getting full audio path: $e');
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
                        )
                      else if (widget.log.audioPath != null)
                        Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                          ),
                          child: Stack(
                            children: [
                              Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.mic,
                                      color: Colors.purple.shade300,
                                      size: 32,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '语音记录',
                                      style: TextStyle(
                                        color: Colors.purple.shade300,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                                        Colors.black.withOpacity(0.1),
                                      ],
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    DateFormat('MM月dd日 HH:mm')
                                        .format(widget.log.timestamp),
                                    style: TextStyle(
                                      color: Colors.purple.shade700,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ClipRRect(
                        borderRadius: BorderRadius.vertical(
                          top: widget.log.imagePath == null &&
                                  widget.log.videoPath == null &&
                                  widget.log.audioPath == null
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
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        throw Exception('视频文件不存在');
      }

      Future<void> _initializeWithLargeFile(File file) async {
        try {
          // 确保在初始化新控制器前释放旧资源
          if (_initialized) {
            await _videoPlayerController.dispose();
            _chewieController.dispose();
            _initialized = false;
          }

          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });

          _videoPlayerController = VideoPlayerController.file(file);
          await _videoPlayerController.initialize().timeout(
                const Duration(seconds: 60),
                onTimeout: () =>
                    throw TimeoutException('视频加载超时，请检查网络连接或选择较小的文件'),
              );

          _chewieController = ChewieController(
            videoPlayerController: _videoPlayerController,
            autoPlay: true,
            looping: false,
            aspectRatio: _videoPlayerController.value.aspectRatio,
            showControls: true,
            allowFullScreen: true,
            errorBuilder: (context, errorMessage) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, color: Colors.white, size: 42),
                    const SizedBox(height: 16),
                    Text(
                      errorMessage,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        // 重试前先释放资源
                        _videoPlayerController.pause();
                        _videoPlayerController.seekTo(Duration.zero);
                        _initializePlayer();
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            },
          );

          // 添加视频播放状态监听
          _videoPlayerController.addListener(() {
            if (_videoPlayerController.value.hasError) {
              setState(() {
                _errorMessage =
                    '视频播放出错：${_videoPlayerController.value.errorDescription}';
                _isLoading = false;
              });
            }
          });

          setState(() {
            _initialized = true;
            _isLoading = false;
          });
        } catch (e) {
          debugPrint('Error initializing large video file: $e');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = e is TimeoutException
                  ? '视频加载超时，请检查网络连接'
                  : '视频加载失败，请检查文件是否损坏或格式是否支持';
            });
          }
        }
      }

      final fileSize = await file.length();
      final fileSizeInMB = fileSize / (1024 * 1024);

      if (fileSizeInMB > 100) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('文件过大'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      '视频文件大小为 ${fileSizeInMB.toStringAsFixed(2)}MB，超过100MB可能导致播放不流畅。'),
                  const SizedBox(height: 8),
                  const Text('建议：\n1. 选择较小的视频文件\n2. 压缩视频后再试\n3. 确保设备有足够的内存'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _initializeWithLargeFile(file);
                  },
                  child: const Text('仍然播放'),
                ),
              ],
            ),
          );
        }
        setState(() {
          _isLoading = false;
          _errorMessage = '文件过大，请选择较小的视频文件';
        });
        return;
      }

      _videoPlayerController = VideoPlayerController.file(file);
      await _videoPlayerController.initialize().timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('视频加载超时'),
          );

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController.value.aspectRatio,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.white, size: 42),
                const SizedBox(height: 16),
                Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _initializePlayer,
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        },
      );

      setState(() {
        _initialized = true;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error initializing video player: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              e is TimeoutException ? '视频加载超时' : '视频加载失败，请检查文件是否损坏或格式是否支持';
        });
      }
    }
  }

  @override
  void dispose() {
    // 确保在组件销毁时完全释放所有资源
    if (_initialized) {
      _videoPlayerController.removeListener(() {});
      _videoPlayerController.pause();
      _videoPlayerController.dispose();
      _chewieController.dispose();
      _initialized = false;
    }
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
              DateFormat('yyyy-MM-dd HH:mm:ss').format(widget.timestamp),
              style: const TextStyle(fontSize: 14),
            ),
            if (widget.text.isNotEmpty)
              Text(
                widget.text,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      body: Center(
        child: _isLoading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    '视频加载中...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              )
            : _errorMessage != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.white, size: 42),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _initializePlayer,
                        child: const Text('重试'),
                      ),
                    ],
                  )
                : Chewie(controller: _chewieController),
      ),
    );
  }
}

class AudioPreviewPage extends StatefulWidget {
  final String audioPath;
  final DateTime timestamp;
  final String text;

  const AudioPreviewPage({
    super.key,
    required this.audioPath,
    required this.timestamp,
    required this.text,
  });

  @override
  State<AudioPreviewPage> createState() => _AudioPreviewPageState();
}

class _AudioPreviewPageState extends State<AudioPreviewPage> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _playerSubscription;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    await _player.setSubscriptionDuration(const Duration(milliseconds: 100));
    _playerSubscription = _player.onProgress!.listen((event) {
      setState(() {
        _position = event.position;
        _duration = event.duration;
      });
    });
  }

  @override
  void dispose() {
    _playerSubscription?.cancel();
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    } else {
      await _player.startPlayer(
        fromURI: widget.audioPath,
        whenFinished: () => setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        }),
      );
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _seekTo(Duration position) async {
    await _player.seekToPlayer(position);
    setState(() {
      _position = position;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy年MM月dd日').format(widget.timestamp),
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              DateFormat('HH:mm').format(widget.timestamp),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 32),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.stop : Icons.play_arrow,
                      size: 40,
                      color: Colors.purple.shade400,
                    ),
                    onPressed: _togglePlay,
                  ),
                ),
                const SizedBox(height: 24),
                // 添加进度条
                Column(
                  children: [
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        activeTrackColor: Colors.purple.shade300,
                        inactiveTrackColor: Colors.purple.shade50,
                        thumbColor: Colors.purple.shade400,
                        overlayColor: Colors.purple.shade100,
                      ),
                      child: Slider(
                        value: _position.inMilliseconds.toDouble(),
                        max: _duration.inMilliseconds > 0
                            ? _duration.inMilliseconds.toDouble()
                            : 1.0, // 避免除以零错误
                        onChanged: (value) {
                          final position =
                              Duration(milliseconds: value.toInt());
                          _seekTo(position);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_position),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatDuration(_duration),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (widget.text.isNotEmpty)
                  Text(
                    widget.text,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DateListDialog extends StatefulWidget {
  final List<DateTime> dates;
  final Function(DateTime) onSelectDate;
  final int Function(DateTime) getLogCount;

  const DateListDialog({
    super.key,
    required this.dates,
    required this.onSelectDate,
    required this.getLogCount,
  });

  @override
  State<DateListDialog> createState() => _DateListDialogState();
}

class _DateListDialogState extends State<DateListDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 按月份对日期进行分组
  Map<String, List<DateTime>> _getGroupedDates() {
    final Map<String, List<DateTime>> grouped = {};

    for (var date in widget.dates) {
      if (_searchQuery.isNotEmpty) {
        final dateStr = DateFormat('yyyy年MM月dd日').format(date);
        if (!dateStr.contains(_searchQuery)) {
          continue;
        }
      }

      final monthKey = DateFormat('yyyy年MM月').format(date);
      grouped.putIfAbsent(monthKey, () => []).add(date);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final groupedDates = _getGroupedDates();
    final months = groupedDates.keys.toList()..sort((a, b) => b.compareTo(a));

    return Container(
      constraints: const BoxConstraints(maxHeight: 600),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  '所有日期',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索日期...',
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
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
          const Divider(height: 1),
          Expanded(
            child: groupedDates.isEmpty
                ? Center(
                    child: Text(
                      '没有找到匹配的日期',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: months.length,
                    itemBuilder: (context, monthIndex) {
                      final month = months[monthIndex];
                      final dates = groupedDates[month]!;

                      return ExpansionTile(
                        initiallyExpanded: _searchQuery.isNotEmpty,
                        title: Row(
                          children: [
                            Text(
                              month,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${dates.length}天',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        children: dates.map((date) {
                          final count = widget.getLogCount(date);
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              DateFormat('dd日 EEEE').format(date),
                              style: const TextStyle(fontSize: 15),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$count条',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            onTap: () => widget.onSelectDate(date),
                          );
                        }).toList(),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
