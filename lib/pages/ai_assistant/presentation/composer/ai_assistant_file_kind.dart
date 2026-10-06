import 'package:flutter/material.dart';
import '../../models/ai_assistant_models.dart';
import '../../theme/ai_palette.dart';

class AiAssistantFileKinds {
  AiAssistantFileKinds._();

  static AiAssistantFileKind fromName(String fileName) {
    final trimmed = fileName.trim();
    final dot = trimmed.lastIndexOf('.');
    if (dot < 0 || dot == trimmed.length - 1) {
      return AiAssistantFileKind.unknown;
    }
    switch (trimmed.substring(dot + 1).toLowerCase()) {
      case 'pdf':
        return AiAssistantFileKind.pdf;
      case 'doc':
      case 'docx':
        return AiAssistantFileKind.word;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return AiAssistantFileKind.excel;
      case 'ppt':
      case 'pptx':
        return AiAssistantFileKind.ppt;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'heic':
        return AiAssistantFileKind.image;
      case 'mp4':
      case 'mov':
      case 'webm':
      case 'avi':
      case 'mkv':
        return AiAssistantFileKind.video;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'aac':
        return AiAssistantFileKind.audio;
      case 'txt':
      case 'md':
        return AiAssistantFileKind.text;
      case 'zip':
      case 'rar':
      case '7z':
        return AiAssistantFileKind.archive;
      default:
        return AiAssistantFileKind.unknown;
    }
  }

  static IconData icon(AiAssistantFileKind kind) {
    switch (kind) {
      case AiAssistantFileKind.pdf:
        return Icons.picture_as_pdf;
      case AiAssistantFileKind.word:
        return Icons.description_outlined;
      case AiAssistantFileKind.excel:
        return Icons.table_chart_outlined;
      case AiAssistantFileKind.ppt:
        return Icons.slideshow_outlined;
      case AiAssistantFileKind.image:
        return Icons.image_outlined;
      case AiAssistantFileKind.video:
        return Icons.videocam_outlined;
      case AiAssistantFileKind.audio:
        return Icons.audiotrack_outlined;
      case AiAssistantFileKind.text:
        return Icons.article_outlined;
      case AiAssistantFileKind.archive:
        return Icons.folder_zip_outlined;
      case AiAssistantFileKind.unknown:
        return Icons.insert_drive_file_outlined;
    }
  }

  static Color color(AiAssistantFileKind kind) {
    switch (kind) {
      case AiAssistantFileKind.pdf:
        return AiPalette.pdf;
      case AiAssistantFileKind.word:
        return AiPalette.word;
      case AiAssistantFileKind.excel:
        return AiPalette.excel;
      case AiAssistantFileKind.ppt:
        return AiPalette.ppt;
      case AiAssistantFileKind.image:
        return AiPalette.image;
      case AiAssistantFileKind.video:
        return AiPalette.video;
      case AiAssistantFileKind.audio:
        return AiPalette.audio;
      case AiAssistantFileKind.text:
        return AiPalette.textFile;
      case AiAssistantFileKind.archive:
        return AiPalette.archive;
      case AiAssistantFileKind.unknown:
        return AiPalette.unknownFile;
    }
  }

  static String badge(AiAssistantFileKind kind) {
    switch (kind) {
      case AiAssistantFileKind.pdf:
        return 'PDF';
      case AiAssistantFileKind.word:
        return 'DOC';
      case AiAssistantFileKind.excel:
        return 'XLS';
      case AiAssistantFileKind.ppt:
        return 'PPT';
      case AiAssistantFileKind.image:
        return 'IMG';
      case AiAssistantFileKind.video:
        return 'VID';
      case AiAssistantFileKind.audio:
        return 'AUD';
      case AiAssistantFileKind.text:
        return 'TXT';
      case AiAssistantFileKind.archive:
        return 'ZIP';
      case AiAssistantFileKind.unknown:
        return 'FILE';
    }
  }
}
