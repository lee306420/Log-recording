import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:video_player/video_player.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../models/log_entry.dart';
import '../widgets/timeline_entry.dart';
import '../widgets/date_list_dialog.dart';
import '../utils/storage_utils.dart';

class LogListPage extends StatefulWidget {
  const LogListPage({super.key});

  @override
  State<LogListPage> createState() => LogListPageState();
}

class LogListPageState extends State<LogListPage> {
  final List<LogEntry> _logs = [];
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  DateTime? _selectedDate;
  String? _customStoragePath;
  bool _isSearchingAllDates = false;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 10;
  int _currentPage = 1;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(_onSearchFocusChange);

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
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreLogs();
    }
  }

  Future<void> _loadMoreLogs() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    // 模拟加载延迟
    await Future.delayed(const Duration(milliseconds: 300));

    final startIndex = _currentPage * _pageSize;
    final endIndex = (startIndex + _pageSize).clamp(0, _filteredLogs.length);

    if (startIndex < _filteredLogs.length) {
      setState(() {
        _currentPage++;
      });
    }

    setState(() {
      _isLoadingMore = false;
    });
  }

  List<LogEntry> get _filteredLogs {
    List<LogEntry> logs = List.from(_logs);
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

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

  List<LogEntry> get _paginatedLogs {
    final endIndex = (_currentPage * _pageSize).clamp(0, _filteredLogs.length);
    return _filteredLogs.sublist(0, endIndex);
  }

  void _onSearchFocusChange() {
    if (_searchFocusNode.hasFocus) {
      setState(() {
        _isSearchingAllDates = true;
      });
    }
  }

  Future<void> _requestAllFilePermissions() async {
    await StorageUtils.requestAllFilePermissions();
  }

  Future<void> _loadStoragePath() async {
    _customStoragePath = await StorageUtils.loadStoragePath();
    if (_customStoragePath == null) {
      _customStoragePath = await StorageUtils.getDefaultStoragePath();
    }
    await StorageUtils.ensureDirectoryExists(_customStoragePath!);
  }

  Future<bool> _showInitialStorageDialog(BuildContext context) async {
    return await StorageUtils.showInitialStorageDialog(context);
  }

  Future<void> _showStorageSettings(BuildContext context) async {
    await StorageUtils.showStorageSettings(context);
    await _loadStoragePath();
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: '搜索日志...',
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
                fillColor: Colors.grey.shade100,
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
                  if (value.isNotEmpty) {
                    _isSearchingAllDates = true;
                  } else {
                    _isSearchingAllDates = false;
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: _isSearchingAllDates ? Colors.blue : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.blue,
                width: 1.5,
              ),
              boxShadow: [
                if (_isSearchingAllDates)
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                _isSearchingAllDates
                    ? Icons.all_inclusive
                    : Icons.calendar_today,
                size: 20,
                color: _isSearchingAllDates ? Colors.white : Colors.blue,
              ),
              onPressed: () {
                setState(() {
                  _isSearchingAllDates = !_isSearchingAllDates;
                });
              },
              tooltip: _isSearchingAllDates ? '切换到当前日期' : '切换到所有日期',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadLogs() async {
    if (_customStoragePath == null) return;

    try {
      final logsFile = File(path.join(_customStoragePath!, 'logs.json'));
      if (await logsFile.exists()) {
        final jsonString = await logsFile.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);
        final logs = jsonList.map((json) => LogEntry.fromJson(json)).toList();

        setState(() {
          _logs.clear();
          _logs.addAll(logs);
        });
      }
    } catch (e) {
      debugPrint('Error loading logs: $e');
    }
  }

  Future<void> _saveLogs() async {
    if (_customStoragePath == null) return;

    try {
      final logsFile = File(path.join(_customStoragePath!, 'logs.json'));
      final jsonList = _logs.map((log) => log.toJson()).toList();
      final jsonString = json.encode(jsonList);
      await logsFile.writeAsString(jsonString);
    } catch (e) {
      debugPrint('Error saving logs: $e');
    }
  }

  Future<void> _deleteLog(int index) async {
    setState(() {
      _logs.removeAt(index);
    });
    await _saveLogs();
  }

  Future<String> getFullImagePath(String fileName) async {
    if (_customStoragePath == null) {
      _customStoragePath = await StorageUtils.getDefaultStoragePath();
    }
    return path.join(_customStoragePath!, 'images', fileName);
  }

  Future<String> getFullVideoPath(String fileName) async {
    if (_customStoragePath == null) {
      _customStoragePath = await StorageUtils.getDefaultStoragePath();
    }
    return path.join(_customStoragePath!, 'videos', fileName);
  }

  Future<String> getFullAudioPath(String fileName) async {
    if (_customStoragePath == null) {
      _customStoragePath = await StorageUtils.getDefaultStoragePath();
    }
    return path.join(_customStoragePath!, 'audios', fileName);
  }

  Future<String?> _copyImageToLocal(String sourcePath) async {
    if (_customStoragePath == null) return null;
    return StorageUtils.copyImageToLocal(sourcePath, _customStoragePath!);
  }

  Future<String?> _copyVideoToLocal(String sourcePath) async {
    if (_customStoragePath == null) return null;
    return StorageUtils.copyVideoToLocal(sourcePath, _customStoragePath!);
  }

  Future<String?> _copyAudioToLocal(String sourcePath) async {
    if (_customStoragePath == null) return null;
    return StorageUtils.copyAudioToLocal(sourcePath, _customStoragePath!);
  }

  List<DateTime> _getUniqueDates() {
    final Map<String, DateTime> uniqueDates = {};

    for (var log in _logs) {
      final date = DateTime(
        log.timestamp.year,
        log.timestamp.month,
        log.timestamp.day,
      );
      final dateStr = date.toIso8601String().split('T').first;
      uniqueDates[dateStr] = date;
    }

    final result = uniqueDates.values.toList();
    result.sort((a, b) => b.compareTo(a)); // 逆序排列，最新的日期在前
    return result;
  }

  int _getLogCountForDate(DateTime date) {
    final targetDate = DateTime(
      date.year,
      date.month,
      date.day,
    );

    return _logs.where((log) {
      final logDate = DateTime(
        log.timestamp.year,
        log.timestamp.month,
        log.timestamp.day,
      );
      return logDate.isAtSameMomentAs(targetDate);
    }).length;
  }

  Future<void> _addNewLog(BuildContext context) async {
    final textController = TextEditingController();
    String text = '';

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text(
                      '添加日志',
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
                        controller: textController,
                        decoration: InputDecoration(
                          hintText: '在这里记录今天的事情...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        maxLines: null,
                        minLines: 6,
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
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: textController,
                        builder: (context, value, child) {
                          return Text(
                            '${value.text.length} 字',
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
                        onPressed: () async {
                          if (text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('日志内容不能为空')),
                            );
                            return;
                          }

                          Navigator.pop(context);

                          // 获取位置信息
                          Position? position;
                          String? address;
                          try {
                            position = await Geolocator.getCurrentPosition(
                              desiredAccuracy: LocationAccuracy.high,
                              timeLimit: const Duration(seconds: 5),
                            );
                          } catch (e) {
                            debugPrint('无法获取位置: $e');
                          }

                          setState(() {
                            _logs.add(LogEntry(
                              text: text,
                              timestamp: DateTime.now(),
                              latitude: position?.latitude,
                              longitude: position?.longitude,
                              address: address,
                            ));
                          });
                          _saveLogs();
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

  Future<void> _editLog(
      BuildContext context, int index, LogEntry oldLog) async {
    final textController = TextEditingController(text: oldLog.text);
    String text = oldLog.text;

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
                        controller: textController,
                        decoration: InputDecoration(
                          hintText: '在这里记录今天的事情...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        maxLines: null,
                        minLines: 6,
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
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: textController,
                        builder: (context, value, child) {
                          return Text(
                            '${value.text.length} 字',
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
                        onPressed: () async {
                          if (text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('日志内容不能为空')),
                            );
                            return;
                          }

                          Navigator.pop(context);

                          setState(() {
                            _logs[index] = LogEntry(
                              text: text,
                              imagePath: oldLog.imagePath,
                              videoPath: oldLog.videoPath,
                              audioPath: oldLog.audioPath,
                              timestamp: oldLog.timestamp,
                              latitude: oldLog.latitude,
                              longitude: oldLog.longitude,
                              address: oldLog.address,
                            );
                          });
                          _saveLogs();
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
              _buildSearchBar(),
            ],
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () {
          // 点击空白区域时，让搜索框失去焦点
          _searchFocusNode.unfocus();
        },
        child: _filteredLogs.isEmpty
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
                controller: _scrollController,
                itemCount: _paginatedLogs.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _paginatedLogs.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final log = _paginatedLogs[index];
                  // 获取前一条日志的时间戳（因为日志是按时间倒序排列的，索引小的是较新的日志）
                  final DateTime? previousTimestamp =
                      index > 0 ? _paginatedLogs[index - 1].timestamp : null;

                  return TimelineEntry(
                    key: ValueKey(log.timestamp.toString()),
                    log: log,
                    isFirst: index == 0,
                    isLast: index == _paginatedLogs.length - 1,
                    onEdit: () => _editLog(
                      context,
                      _logs.indexOf(log),
                      log,
                    ),
                    onDelete: () => _deleteLog(_logs.indexOf(log)),
                    previousLogTimestamp: previousTimestamp, // 添加前一条日志的时间戳
                  );
                },
              ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'text',
              onPressed: () async {
                await _addNewLog(context);
              },
              child: const Icon(Icons.edit_note),
            ),
            const SizedBox(height: 16),
            FloatingActionButton(
              heroTag: 'galleryPicker',
              onPressed: () async {
                final List<AssetEntity>? result = await AssetPicker.pickAssets(
                  context,
                  pickerConfig: AssetPickerConfig(
                    maxAssets: 1, // 单选模式
                    requestType: RequestType.common, // 同时支持图片和视频
                    limitedPermissionOverlayPredicate:
                        (PermissionState state) => true, // 显示权限提示
                    specialPickerType:
                        SpecialPickerType.wechatMoment, // 使用朋友圈样式UI
                    filterOptions: FilterOptionGroup(
                      videoOption: FilterOption(
                        durationConstraint: const DurationConstraint(
                          max: Duration(seconds: 30), // 限制视频最大时长30秒
                        ),
                      ),
                    ),
                  ),
                );

                if (result != null && result.isNotEmpty && context.mounted) {
                  final AssetEntity asset = result.first;
                  await _handleAssetPick(context, asset);
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
                  imageQuality: 80,
                );

                if (photo != null && context.mounted) {
                  final imagePath = await _copyImageToLocal(photo.path);
                  if (imagePath != null) {
                    await _showMediaDescriptionDialog(
                      context,
                      isVideo: false,
                      mediaPath: imagePath,
                    );
                  }
                }
              },
              child: const Icon(Icons.camera_alt),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAssetPick(BuildContext context, AssetEntity asset) async {
    if (asset.type == AssetType.video) {
      // 处理视频
      final File? videoFile = await asset.file;
      if (videoFile == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法获取视频文件')),
          );
        }
        return;
      }

      final int fileSize = await videoFile.length();
      final double fileSizeInMB = fileSize / (1024 * 1024);

      // 检查视频时长
      if (asset.duration > 30) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('视频过长'),
              content: const Text('选择的视频超过30秒，请选择更短的视频。'),
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

      if (fileSizeInMB > 500) {
        if (context.mounted) {
          final bool shouldContinue = await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('文件过大'),
                  content: Text(
                      '选择的视频文件大小为 ${fileSizeInMB.toStringAsFixed(2)}MB，建议选择较小的视频以获得更好的性能。是否继续？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
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

      final videoPath = await _copyVideoToLocal(videoFile.path);
      if (videoPath != null && context.mounted) {
        await _showMediaDescriptionDialog(
          context,
          isVideo: true,
          mediaPath: videoPath,
        );
      }
    } else if (asset.type == AssetType.image) {
      // 处理图片
      final File? imageFile = await asset.file;
      if (imageFile == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法获取图片文件')),
          );
        }
        return;
      }

      final imagePath = await _copyImageToLocal(imageFile.path);
      if (imagePath != null && context.mounted) {
        await _showMediaDescriptionDialog(
          context,
          isVideo: false,
          mediaPath: imagePath,
        );
      }
    }
  }

  Future<void> _showMediaDescriptionDialog(
    BuildContext context, {
    required bool isVideo,
    required String mediaPath,
  }) async {
    String text = '';
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: isVideo ? '为这段视频添加描述...' : '为这张照片添加描述...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
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
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() {
                            _logs.add(LogEntry(
                              text: text,
                              imagePath: isVideo ? null : mediaPath,
                              videoPath: isVideo ? mediaPath : null,
                              timestamp: DateTime.now(),
                            ));
                          });
                          _saveLogs();
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
