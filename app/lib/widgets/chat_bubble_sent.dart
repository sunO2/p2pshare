import 'package:flutter/material.dart';
import '../data/models/chat_message_model.dart';
import '../core/theme/app_theme.dart';

class ChatBubbleSent extends StatelessWidget {
  final ChatMessageData message;

  const ChatBubbleSent({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = context.customTheme;

    // 判断是否为文件类型消息（图片、视频、文件、音频）
    final isFileMessage = message.isImage || message.isVideo || message.isFile || message.isAudio;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 气泡 - 文件类型消息去掉外层容器
        if (isFileMessage)
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: _buildFileMessageCard(context),
          )
        else
          Container(
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: theme.statusGreen,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
            ),
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(right: 8),
            child: _buildMessageContent(context),
          ),
        // 头像
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.dividerColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(Icons.person, size: 20, color: theme.iconColorLight),
          ),
        ),
      ],
    );
  }

  /// 构建文件消息卡片（无外层气泡）
  Widget _buildFileMessageCard(BuildContext context) {
    // 图片消息
    if (message.isImage) {
      return _buildImageMessage(context);
    }

    // 视频消息
    if (message.isVideo) {
      return _buildVideoMessage(context);
    }

    // 文件消息
    if (message.isFile) {
      return _buildFileMessage(context);
    }

    // 音频消息
    if (message.isAudio) {
      return _buildAudioMessage(context);
    }

    return const SizedBox.shrink();
  }

  /// 构建消息内容（文本消息）
  Widget _buildMessageContent(BuildContext context) {
    return Text(
      message.content,
      style: const TextStyle(fontSize: 16, color: Colors.black, height: 1.4),
    );
  }

  /// 构建图片消息
  Widget _buildImageMessage(BuildContext context) {
    final theme = context.customTheme;
    final fileName = message.extra?.fileName ?? '图片.jpg';
    final fileSize = _formatFileSize(message.extra?.fileSize);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 图片预览区域
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              width: 200,
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.statusGreen.withOpacity(0.3),
                    theme.statusGreen.withOpacity(0.1),
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 图片图标
                  Icon(
                    Icons.image_outlined,
                    size: 48,
                    color: theme.statusGreen.withOpacity(0.8),
                  ),
                  // 图片类型标签
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'JPG',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 文件信息
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fileName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fileSize,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.download_outlined,
                  size: 18,
                  color: theme.statusGreen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建视频消息
  Widget _buildVideoMessage(BuildContext context) {
    final fileName = message.extra?.fileName ?? '视频.mp4';
    final fileSize = _formatFileSize(message.extra?.fileSize);
    final duration = message.extra?.duration ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 视频预览区域
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              width: 220,
              height: 130,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.purple.withOpacity(0.3),
                    Colors.blue.withOpacity(0.2),
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 视频图标
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      size: 28,
                      color: Colors.purple,
                    ),
                  ),
                  // 时长标签
                  if (duration > 0)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatDuration(duration),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  // 视频类型标签
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'MP4',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 文件信息
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fileName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            fileSize,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black.withOpacity(0.5),
                            ),
                          ),
                          if (duration > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 1,
                              height: 10,
                              color: Colors.black.withOpacity(0.2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDuration(duration),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.download_outlined,
                  size: 18,
                  color: Colors.purple,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建文件消息
  Widget _buildFileMessage(BuildContext context) {
    final fileName = message.extra?.fileName ?? '文档.pdf';
    final fileSize = _formatFileSize(message.extra?.fileSize);
    final mimeType = message.extra?.mimeType ?? 'application/pdf';
    final fileIcon = _getFileIconData(mimeType);
    final fileColor = _getFileColor(mimeType);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 文件图标
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: fileColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              fileIcon,
              size: 26,
              color: fileColor,
            ),
          ),
          const SizedBox(width: 12),
          // 文件信息
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileSize,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 1,
                    height: 10,
                    color: Colors.black.withOpacity(0.2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _getFileExtension(fileName),
                    style: TextStyle(
                      fontSize: 11,
                      color: fileColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.download_outlined,
            size: 20,
            color: fileColor,
          ),
        ],
      ),
    );
  }

  /// 构建音频消息
  Widget _buildAudioMessage(BuildContext context) {
    final duration = message.extra?.duration ?? 0;
    final fileName = message.extra?.fileName ?? '语音.mp3';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 播放按钮
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.play_arrow,
              size: 20,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          // 波形和时长
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fileName,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 模拟音频波形
                  SizedBox(
                    width: 100,
                    height: 24,
                    child: Stack(
                      alignment: Alignment.center,
                      children: List.generate(20, (index) {
                        final height = 8.0 + (index % 5) * 4.0;
                        return Positioned(
                          left: index * 5.0,
                          child: Container(
                            width: 3,
                            height: height,
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  if (duration > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(duration),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black.withOpacity(0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 获取文件图标
  IconData _getFileIconData(String mimeType) {
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    if (mimeType.contains('excel') || mimeType.contains('sheet')) {
      return Icons.table_chart;
    }
    if (mimeType.contains('powerpoint') || mimeType.contains('presentation')) {
      return Icons.slideshow;
    }
    if (mimeType.contains('zip') || mimeType.contains('rar') || mimeType.contains('archive')) {
      return Icons.archive;
    }
    if (mimeType.contains('text')) return Icons.text_snippet;
    return Icons.insert_drive_file;
  }

  /// 获取文件颜色
  Color _getFileColor(String mimeType) {
    if (mimeType.contains('pdf')) return const Color(0xFFD32F2F);
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return const Color(0xFF1976D2);
    }
    if (mimeType.contains('excel') || mimeType.contains('sheet')) {
      return const Color(0xFF388E3C);
    }
    if (mimeType.contains('powerpoint') || mimeType.contains('presentation')) {
      return const Color(0xFFE64A19);
    }
    if (mimeType.contains('zip') || mimeType.contains('rar') || mimeType.contains('archive')) {
      return const Color(0xFF7B1FA2);
    }
    if (mimeType.contains('text')) return const Color(0xFF757575);
    return const Color(0xFF607D8B);
  }

  /// 获取文件扩展名
  String _getFileExtension(String fileName) {
    final parts = fileName.split('.');
    if (parts.length > 1) {
      return parts.last.toUpperCase();
    }
    return 'FILE';
  }

  /// 格式化文件大小
  String _formatFileSize(int? bytes) {
    if (bytes == null) return '未知大小';

    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// 格式化时长
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
