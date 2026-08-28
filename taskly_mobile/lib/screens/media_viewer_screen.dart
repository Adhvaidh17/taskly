import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/message.dart';

enum MediaViewerAction { forward }

class MediaViewerScreen extends StatelessWidget {
  const MediaViewerScreen({
    super.key,
    required this.message,
    required this.localPath,
    required this.unavailable,
  });

  final MessageItem message;
  final String? localPath;
  final bool unavailable;

  bool get _available => !unavailable &&
      localPath != null &&
      localPath!.trim().isNotEmpty &&
      File(localPath!).existsSync();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.sender.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              DateFormat('dd MMM, h:mm a').format(message.createdAt),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Forward',
            onPressed: () => Navigator.pop(context, MediaViewerAction.forward),
            icon: const Icon(Icons.forward_rounded),
          ),
          if (_available)
            IconButton(
              tooltip: 'Share',
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                  files: [XFile(localPath!)],
                  text: message.body == message.attachmentName ? null : message.body,
                ),
              ),
              icon: const Icon(Icons.share_outlined),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_available)
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                clipBehavior: Clip.none,
                child: Center(
                  child: Image.file(
                    File(localPath!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const _UnavailableMedia(),
                  ),
                ),
              )
            else
              const _UnavailableMedia(),
            if (_available &&
                message.body.trim().isNotEmpty &&
                message.body.trim() != (message.attachmentName ?? '').trim())
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    message.body,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnavailableMedia extends StatelessWidget {
  const _UnavailableMedia();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D2430), Color(0xFF3A4352), Color(0xFF171B24)],
        ),
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 290),
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined, color: Colors.white70, size: 34),
              SizedBox(height: 9),
              Text(
                'This image is not available on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
