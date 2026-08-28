import 'dart:io';

import 'package:sqflite/sqflite.dart';

/// Taskly v6.1 attachment rule:
///
/// * the physical attachment is deleted from this phone;
/// * no "removed from device" tombstone/list is retained;
/// * if the message also has useful text/caption, keep the text and clear only
///   the attachment columns;
/// * if the message was attachment-only, delete the whole local message row.
abstract final class RemovedAttachmentCleanupV61 {
  static const _legacyTables = <String>[
    'removed_attachments',
    'deleted_attachments',
    'attachment_tombstones',
    'removed_message_attachments',
  ];

  static const _textColumns = <String>[
    'body',
    'text',
    'content',
    'caption',
  ];

  static const _attachmentColumns = <String>[
    'attachment_bucket',
    'attachment_path',
    'attachment_name',
    'attachment_mime_type',
    'attachment_size_bytes',
    'media_path',
    'media_name',
    'media_mime_type',
    'media_size_bytes',
    'thumbnail_path',
  ];

  /// Removes old SQLite tombstone/list rows left by previous builds.
  static Future<void> purgeLegacyTombstones(Database db) async {
    final tables = await _tables(db);
    for (final table in _legacyTables) {
      if (tables.contains(table)) {
        await db.delete(table);
      }
    }
  }

  /// Finds local messages pointing at attachment files that no longer exist.
  ///
  /// Text/caption messages survive with their attachment metadata cleared.
  /// Attachment-only rows disappear completely. No placeholder is created.
  static Future<int> purgeMissingAttachmentMessages(
    Database db, {
    String messageTable = 'messages',
  }) async {
    final schema = await _messageSchema(db, messageTable);
    if (schema == null || !schema.columns.contains('attachment_path')) return 0;

    final selected = <String>{
      schema.idColumn,
      'attachment_path',
      ..._textColumns.where(schema.columns.contains),
    }.toList();

    final rows = await db.query(
      messageTable,
      columns: selected,
      where: "attachment_path is not null and trim(attachment_path) <> ''",
    );

    var changed = 0;
    for (final row in rows) {
      final path = '${row['attachment_path'] ?? ''}'.trim();
      if (path.isEmpty || await File(path).exists()) continue;

      changed += await _removeAttachmentReference(
        db: db,
        table: messageTable,
        schema: schema,
        row: row,
      );
    }
    return changed;
  }

  /// Deletes an attachment without leaving any database tombstone.
  ///
  /// If [rowId] belongs to a text+attachment message, only attachment metadata
  /// is cleared. If it is attachment-only, the local message row is deleted.
  static Future<void> hardDeleteAttachment({
    required Database db,
    required Object rowId,
    required String attachmentPath,
    String messageTable = 'messages',
    String? idColumn,
  }) async {
    final file = File(attachmentPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } on FileSystemException {
        // We still remove the local DB attachment reference. This prevents a
        // phantom "removed from device" tile even if the OS already removed
        // the file or denied the final unlink operation.
      }
    }

    final schema = await _messageSchema(db, messageTable, idColumn: idColumn);
    if (schema == null) return;

    final selected = <String>{
      schema.idColumn,
      ..._textColumns.where(schema.columns.contains),
      ..._attachmentColumns.where(schema.columns.contains),
    }.toList();

    final rows = await db.query(
      messageTable,
      columns: selected,
      where: '${schema.idColumn} = ?',
      whereArgs: [rowId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    await _removeAttachmentReference(
      db: db,
      table: messageTable,
      schema: schema,
      row: rows.first,
    );
  }

  static Future<int> _removeAttachmentReference({
    required Database db,
    required String table,
    required _MessageSchema schema,
    required Map<String, Object?> row,
  }) async {
    final hasText = _textColumns
        .where(schema.columns.contains)
        .map((column) => '${row[column] ?? ''}'.trim())
        .any((value) => value.isNotEmpty);

    if (!hasText) {
      return db.delete(
        table,
        where: '${schema.idColumn} = ?',
        whereArgs: [row[schema.idColumn]],
      );
    }

    final clearValues = <String, Object?>{};
    for (final column in _attachmentColumns) {
      if (schema.columns.contains(column)) clearValues[column] = null;
    }

    // Older local schemas may have deletion flags. They must never be used to
    // render a removed-media state in v6.1, so reset them while keeping text.
    for (final column in const [
      'removed_from_device',
      'attachment_removed',
      'is_removed',
      'is_deleted_attachment',
    ]) {
      if (schema.columns.contains(column)) clearValues[column] = 0;
    }

    if (clearValues.isEmpty) {
      return db.delete(
        table,
        where: '${schema.idColumn} = ?',
        whereArgs: [row[schema.idColumn]],
      );
    }

    return db.update(
      table,
      clearValues,
      where: '${schema.idColumn} = ?',
      whereArgs: [row[schema.idColumn]],
    );
  }

  static Future<_MessageSchema?> _messageSchema(
    Database db,
    String table, {
    String? idColumn,
  }) async {
    final tables = await _tables(db);
    if (!tables.contains(table)) return null;

    final rows = await db.rawQuery('pragma table_info($table)');
    final columns = rows.map((row) => '${row['name']}').toSet();
    final resolvedId = idColumn != null && columns.contains(idColumn)
        ? idColumn
        : columns.contains('local_id')
            ? 'local_id'
            : columns.contains('id')
                ? 'id'
                : null;
    if (resolvedId == null) return null;
    return _MessageSchema(columns: columns, idColumn: resolvedId);
  }

  static Future<Set<String>> _tables(Database db) async {
    final rows = await db.rawQuery(
      "select name from sqlite_master where type='table' and name not like 'sqlite_%'",
    );
    return rows.map((row) => '${row['name']}').toSet();
  }
}

class _MessageSchema {
  const _MessageSchema({required this.columns, required this.idColumn});

  final Set<String> columns;
  final String idColumn;
}
