import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cross_file/cross_file.dart';

import '../models/log_entry.dart';
import '../screens/log_list_page.dart';

class TimelineEntry extends StatefulWidget {
  final LogEntry log;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final DateTime? previousLogTimestamp;

  const TimelineEntry({
    super.key,
    required this.log,
    this.isFirst = false,
    this.isLast = false,
    required this.onEdit,
    required this.onDelete,
    this.previousLogTimestamp,
  });

  @override
  State<TimelineEntry> createState() => _TimelineEntryState();
}

class _TimelineEntryState extends State<TimelineEntry> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  static final Map<String, VideoPlayerController> _controllerCache = {};
  static final Map<String, ImageProvider> _imageCache = {};
  static const int _maxCachedControllers = 3;

  @override
  void initState() {
    super.initState();
    if (widget.log.videoPath != null) {
      _initializeVideoController();
    }
    if (widget.log.imagePath != null) {
      _preloadImage();
    }
  }

  Future<void> _preloadImage() async {
    if (widget.log.imagePath == null) return;

    final logListState = context.findAncestorStateOfType<LogListPageState>();
    if (logListState == null) return;

    try {
      final fullPath =
          await logListState.getFullImagePath(widget.log.imagePath!);
      if (!_imageCache.containsKey(fullPath)) {
        final file = File(fullPath);
        if (await file.exists()) {
          _imageCache[fullPath] = FileImage(file);
          // 预加载图片
          (_imageCache[fullPath] as FileImage).evict().then((_) {
            (_imageCache[fullPath] as FileImage)
                .resolve(ImageConfiguration.empty);
          });
        }
      }
    } catch (e) {
      debugPrint('Error preloading image: $e');
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
      final logListState = context.findAncestorStateOfType<LogListPageState>();
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

      // 限制缓存数量
      if (_controllerCache.length > _maxCachedControllers) {
        final oldestKey = _controllerCache.keys.first;
        final oldestController = _controllerCache.remove(oldestKey);
        oldestController?.dispose();
      }

      if (!mounted) {
        controller.dispose();
        return;
      }

      _videoController = controller;
      _isVideoInitialized = true;
      setState(() {});
    } catch (e) {
      debugPrint('Error initializing video controller: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 根据日志类型确定时间点的颜色
    final Color timelineColor = widget.log.videoPath != null
        ? Colors.red.shade400
        : widget.log.imagePath != null
            ? Colors.green.shade400
            : Colors.blue.shade400;

    // 根据内容类型计算时间点的垂直位置
    final bool hasMedia =
        widget.log.imagePath != null || widget.log.videoPath != null;
    final double timelineDotPosition = hasMedia ? 130.0 : 70.0; // 根据卡片高度计算中间位置

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
                    // 时间线竖线 - 改进样式
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 44, // 调整左侧位置，与圆圈居中对齐
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              widget.isFirst
                                  ? Colors.transparent
                                  : Colors.grey.shade300,
                              timelineColor,
                              widget.isLast
                                  ? Colors.transparent
                                  : Colors.grey.shade300,
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 2,
                              offset: const Offset(1, 0),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 时间点圆圈 - 美化设计，移到中间位置
                    Positioned(
                      top: timelineDotPosition,
                      left: 22, // 调整左侧位置使圆圈能够居中在时间线上
                      child: _buildTimelineDot(timelineColor),
                    ),
                    // 添加时间间隔标签
                    if (!widget.isFirst) _buildTimeIntervalLabel(),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 内容部分
        Expanded(
          child: Dismissible(
            key: ValueKey('${widget.log.timestamp.toString()}_dismissible'),
            direction: DismissDirection.endToStart, // 只允许从右向左滑动
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.white,
                    Colors.blue.shade50,
                    Colors.red.shade50,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 75,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.2),
                          blurRadius: 3,
                          spreadRadius: 0,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.3),
                                blurRadius: 3,
                                spreadRadius: 0,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.edit,
                            color: Colors.blue.shade700,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '编辑',
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 75,
                    margin: const EdgeInsets.only(left: 5, right: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.2),
                          blurRadius: 3,
                          spreadRadius: 0,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.3),
                                blurRadius: 3,
                                spreadRadius: 0,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '删除',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            confirmDismiss: (direction) async {
              // 显示操作选择底部菜单
              final action = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: Colors.transparent,
                elevation: 0,
                builder: (context) => Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          '请选择操作',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                      const Divider(thickness: 1.0),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, 'edit'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.edit,
                                    color: Colors.blue.shade700),
                              ),
                              title: Text(
                                '编辑日志',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                              subtitle: Text(
                                '修改这条记录的内容',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              trailing: Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 70),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, 'delete'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child:
                                    const Icon(Icons.delete, color: Colors.red),
                              ),
                              title: const Text(
                                '删除日志',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red,
                                ),
                              ),
                              subtitle: Text(
                                '从列表中移除这条记录',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              trailing: Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              );

              if (action == 'edit') {
                widget.onEdit();
              } else if (action == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text('删除确认'),
                      ],
                    ),
                    content: const Text(
                      '确定要删除这条记录吗？\n删除后将无法恢复。',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    actions: [
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Colors.grey.shade100,
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          '取消',
                          style: TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text(
                          '确认删除',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  widget.onDelete();
                }
              }

              // 始终返回false以防止实际的dismissible行为
              return false;
            },
            child: Card(
              margin: const EdgeInsets.fromLTRB(4, 16, 16, 12),
              elevation: 4, // 增加阴影深度
              shadowColor: Colors.black.withOpacity(0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20), // 增加圆角
                side: BorderSide(
                  color: Colors.black,
                  width: 1.2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white,
                      Colors.grey.shade50,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 添加日期和时间显示在卡片顶部
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: timelineColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  DateFormat('MM月dd日')
                                      .format(widget.log.timestamp),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: timelineColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  DateFormat('HH:mm')
                                      .format(widget.log.timestamp),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            _getTimePeriod(widget.log.timestamp),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: timelineColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 添加第一条分割线
                    Divider(
                      height: 1,
                      thickness: 1.5,
                      color: Colors.black,
                      indent: 18,
                      endIndent: 18,
                    ),
                    if (widget.log.imagePath != null)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: _buildImagePreview(),
                        ),
                      ),
                    if (widget.log.videoPath != null)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: _buildVideoPreview(),
                        ),
                      ),
                    // 添加第二条分割线 (在图片/视频后)
                    if (widget.log.imagePath != null ||
                        widget.log.videoPath != null)
                      Divider(
                        height: 1,
                        thickness: 1.5,
                        color: Colors.black,
                        indent: 18,
                        endIndent: 18,
                      ),
                    if (widget.log.text.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                        child: Text(
                          widget.log.text,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    // 添加第三条分割线 (在文本后)
                    if (widget.log.text.isNotEmpty)
                      Divider(
                        height: 1,
                        thickness: 1.5,
                        color: Colors.black,
                        indent: 18,
                        endIndent: 18,
                      ),
                    _buildFooter(showButtons: false),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return FutureBuilder<String>(
      future: context
          .findAncestorStateOfType<LogListPageState>()
          ?.getFullImagePath(widget.log.imagePath!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final fullPath = snapshot.data!;
        final file = File(fullPath);

        return Stack(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      backgroundColor: Colors.black,
                      appBar: AppBar(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        actions: [
                          IconButton(
                            icon: const Icon(
                              Icons.share,
                              color: Colors.white,
                            ),
                            onPressed: () => _shareImage(fullPath),
                          ),
                        ],
                      ),
                      body: Center(
                        child: InteractiveViewer(
                          child: Image.file(
                            file,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: Hero(
                tag: 'image_${widget.log.timestamp}',
                child: Container(
                  constraints: const BoxConstraints(
                    maxHeight: 200,
                  ),
                  width: double.infinity,
                  child: Image.file(
                    file,
                    fit: BoxFit.cover,
                    frameBuilder:
                        (context, child, frame, wasSynchronouslyLoaded) {
                      if (frame == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return child;
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 200,
                        color: Colors.grey.shade200,
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
                ),
              ),
            ),
            // 添加分享按钮
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => _shareImage(fullPath),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.share,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVideoPreview() {
    if (!_isVideoInitialized || _videoController == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return FutureBuilder<String>(
      future: context
          .findAncestorStateOfType<LogListPageState>()
          ?.getFullVideoPath(widget.log.videoPath!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final fullPath = snapshot.data!;

        return Stack(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      backgroundColor: Colors.black,
                      appBar: AppBar(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        actions: [
                          IconButton(
                            icon: const Icon(
                              Icons.share,
                              color: Colors.white,
                            ),
                            onPressed: () => _shareVideo(fullPath),
                          ),
                        ],
                      ),
                      body: Center(
                        child: AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: Chewie(
                            controller: ChewieController(
                              videoPlayerController: _videoController!,
                              autoPlay: true,
                              looping: false,
                              allowMuting: true,
                              allowPlaybackSpeedChanging: true,
                              showControls: true,
                              errorBuilder: (context, errorMessage) {
                                return Center(
                                  child: Text(
                                    '加载视频时出错: $errorMessage',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    constraints: const BoxConstraints(
                      maxHeight: 200,
                    ),
                    width: double.infinity,
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ],
              ),
            ),
            // 添加分享按钮
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => _shareVideo(fullPath),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.share,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFooter({bool showButtons = true}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 2,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (widget.log.address != null && widget.log.address!.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 2,
                        spreadRadius: 0.5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.log.address!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (showButtons)
            Row(
              children: [
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: widget.onEdit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit,
                            size: 16,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '编辑',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('删除确认'),
                          content: const Text('确定要删除这条记录吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onDelete();
                              },
                              child: const Text('删除',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete,
                            size: 16,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '删除',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // 新增方法：创建时间点的圆点
  Widget _buildTimelineDot(Color color) {
    // 获取时间段文本
    final String timeText = _getTimePeriod(widget.log.timestamp);

    return Container(
      width: 46, // 增大外圆尺寸
      height: 46, // 增大外圆尺寸
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 6,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 38, // 增大内圆尺寸
          height: 38, // 增大内圆尺寸
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
          ),
          child: Center(
            child: Text(
              timeText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13, // 增大字体尺寸
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 新增方法：根据时间获取时间段文本
  String _getTimePeriod(DateTime time) {
    final hour = time.hour;

    if (hour >= 0 && hour < 6) {
      return '凌晨';
    } else if (hour >= 6 && hour < 12) {
      return '早上';
    } else if (hour >= 12 && hour < 18) {
      return '下午';
    } else {
      return '晚上';
    }
  }

  // 添加分享图片的方法
  void _shareImage(String imagePath) async {
    try {
      // 显示分享菜单
      await _showShareOptions(imagePath, isImage: true);
    } catch (e) {
      _showErrorSnackBar('分享图片失败: $e');
    }
  }

  // 添加分享视频的方法
  void _shareVideo(String videoPath) async {
    try {
      // 显示分享菜单
      await _showShareOptions(videoPath, isImage: false);
    } catch (e) {
      _showErrorSnackBar('分享视频失败: $e');
    }
  }

  // 显示分享选项
  Future<void> _showShareOptions(String filePath,
      {required bool isImage}) async {
    final type = isImage ? '图片' : '视频';
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '分享$type',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            const Divider(thickness: 1.0),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.share, color: Colors.blue.shade700),
              ),
              title: Text(
                '系统分享',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade800,
                ),
              ),
              subtitle: Text(
                '使用系统分享菜单分享$type',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              onTap: () => Navigator.pop(context, 'system'),
            ),
            const Divider(height: 1, indent: 70),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.copy, color: Colors.green.shade700),
              ),
              title: Text(
                '复制到剪贴板',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800,
                ),
              ),
              subtitle: Text(
                '复制$type路径到剪贴板',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );

    if (result == 'system') {
      // 实现系统分享
      _shareFile(filePath);
    } else if (result == 'copy') {
      // 复制路径到剪贴板
      await Clipboard.setData(ClipboardData(text: filePath));
      _showSuccessSnackBar('已复制路径到剪贴板');
    }
  }

  // 分享文件
  Future<void> _shareFile(String filePath) async {
    try {
      await Share.shareXFiles([XFile(filePath)]);
    } catch (e) {
      _showErrorSnackBar('分享失败: $e');
    }
  }

  // 显示错误提示
  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 显示成功提示
  void _showSuccessSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 计算时间间隔的方法
  Map<String, dynamic> _getTimeInterval() {
    if (widget.previousLogTimestamp == null || widget.isFirst) {
      return {'type': '', 'value': ''};
    }

    // 因为日志是按时间戳倒序排列的，所以前一条日志的时间戳比当前日志更近
    final difference =
        widget.previousLogTimestamp!.difference(widget.log.timestamp);

    if (difference.inSeconds < 60) {
      return {'type': '秒', 'value': '${difference.inSeconds}'};
    } else if (difference.inMinutes < 60) {
      return {'type': '分钟', 'value': '${difference.inMinutes}'};
    } else if (difference.inHours < 24) {
      // 计算小时和剩余的分钟
      final int hours = difference.inHours;
      final int minutes = difference.inMinutes % 60;
      return {
        'type': '小时',
        'value': '$hours',
        'hasMinutes': true,
        'minutes': '$minutes'
      };
    } else if (difference.inDays < 30) {
      return {'type': '天', 'value': '${difference.inDays}'};
    } else if (difference.inDays < 365) {
      return {'type': '个月', 'value': '${(difference.inDays / 30).round()}'};
    } else {
      return {'type': '年', 'value': '${(difference.inDays / 365).round()}'};
    }
  }

  // 显示时间间隔的Widget
  Widget _buildTimeIntervalLabel() {
    final timeData = _getTimeInterval();
    if (timeData['type'] == '') {
      return const SizedBox.shrink();
    }

    // 标签应该位于时间轴线上，时间轴线的x坐标是44
    const double timeLineX = 44.0;

    // 增加标签宽度以适应更多内容
    const double labelWidth = 62.0;
    const double labelLeft = timeLineX - labelWidth / 2;

    // 标签位置
    const double labelTopPosition = 5.0;

    // 根据时间类型选择颜色
    MaterialColor baseColor;
    IconData timeIcon;

    if (timeData['type'] == '秒' || timeData['type'] == '分钟') {
      baseColor = Colors.blue;
      timeIcon = Icons.access_time;
    } else if (timeData['type'] == '小时') {
      baseColor = Colors.purple;
      timeIcon = Icons.hourglass_top;
    } else if (timeData['type'] == '天') {
      baseColor = Colors.green;
      timeIcon = Icons.calendar_today;
    } else {
      baseColor = Colors.orange;
      timeIcon = Icons.date_range;
    }

    return Positioned(
      top: labelTopPosition,
      left: labelLeft,
      child: Container(
        width: labelWidth,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              baseColor.shade50,
              Colors.white,
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: baseColor.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: baseColor.withOpacity(0.2),
              blurRadius: 5,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    baseColor.shade300,
                    baseColor.shade200,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(9),
                  topRight: Radius.circular(9),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    timeIcon,
                    size: 10,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '间隔',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${timeData['value']}${timeData['type']}',
                style: TextStyle(
                  fontSize: 11,
                  color: baseColor.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // 如果有分钟，添加额外一行
            if (timeData['hasMinutes'] == true)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(bottom: 4, top: 2),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      baseColor.shade100,
                      baseColor.shade50,
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(9),
                    bottomRight: Radius.circular(9),
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 8,
                      color: baseColor.shade700,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${timeData['minutes']}分钟',
                      style: TextStyle(
                        fontSize: 10,
                        color: baseColor.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
