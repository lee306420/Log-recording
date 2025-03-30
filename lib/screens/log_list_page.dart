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
import 'package:geolocator/geolocator.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '日志记录',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _selectedDate != null
                  ? DateFormat('MM月dd日').format(_selectedDate!)
                  : '所有日志',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue.shade200,
                Colors.blue.shade50,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.folder_outlined),
              iconSize: 24,
              color: Colors.black87,
              padding: const EdgeInsets.all(8),
              onPressed: () => _showStorageSettings(context),
              tooltip: '存储位置设置',
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.calendar_today),
              iconSize: 22,
              color: Colors.black87,
              padding: const EdgeInsets.all(8),
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
          ),
          Container(
            margin: const EdgeInsets.only(left: 4, right: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.date_range),
              iconSize: 22,
              color: Colors.black87,
              padding: const EdgeInsets.all(8),
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
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: '搜索日志...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.blue.shade300,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                color: Colors.grey.shade400,
                              ),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        if (value.isNotEmpty) {
                          _isSearchingAllDates = true;
                        }
                        _currentPage = 1; // 重置分页
                      });
                    },
                  ),
                ),
                Container(
                  height: 36,
                  width: 36,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _isSearchingAllDates
                        ? Colors.blue.shade400
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      if (_isSearchingAllDates)
                        BoxShadow(
                          color: Colors.blue.shade200.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: Icon(
                      _isSearchingAllDates
                          ? Icons.all_inclusive
                          : Icons.calendar_today_outlined,
                      color: _isSearchingAllDates
                          ? Colors.white
                          : Colors.grey.shade700,
                    ),
                    onPressed: () {
                      setState(() {
                        _isSearchingAllDates = !_isSearchingAllDates;
                      });
                    },
                    tooltip: _isSearchingAllDates ? '切换到当前日期' : '搜索所有日期',
                  ),
                ),
              ],
            ),
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
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.blue.shade400, Colors.blue.shade300],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade200.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: FloatingActionButton(
                heroTag: 'text',
                elevation: 0,
                backgroundColor: Colors.transparent,
                onPressed: () async {
                  await _addNewLog(context);
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.edit_note, size: 28),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.green.shade500, Colors.green.shade400],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.shade200.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: FloatingActionButton(
                heroTag: 'camera',
                elevation: 0,
                backgroundColor: Colors.transparent,
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
                        mediaPath: imagePath,
                      );
                    }
                  }
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.camera_alt, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMediaDescriptionDialog(
    BuildContext context, {
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
                          hintText: '为这张照片添加描述...',
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
                            '${value.length} 字',
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
                              imagePath: mediaPath,
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
    // 返回空字符串，因为移除了视频功能
    return '';
  }

  Future<String?> _copyImageToLocal(String sourcePath) async {
    if (_customStoragePath == null) return null;
    return StorageUtils.copyImageToLocal(sourcePath, _customStoragePath!);
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
}
