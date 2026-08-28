import 'package:sqflite/sqflite.dart';

/// Local-only task-language learning for v6.1.
///
/// This replaces the old server tables that retained user-specific source
/// phrases/message examples. Store only short normalized action phrases and
/// acceptance counters on this phone; never sync this table to Supabase.
class LocalAiPersonalizationV61 {
  const LocalAiPersonalizationV61(this.db);

  final Database db;

  static const table = 'ai_local_aliases_v61';

  static Future<void> ensureSchema(Database db) async {
    await db.execute('''
      create table if not exists $table (
        source_phrase text not null,
        canonical_action text not null,
        accepted_count integer not null default 0,
        rejected_count integer not null default 0,
        last_used_at text not null,
        primary key(source_phrase, canonical_action)
      )
    ''');
    await db.execute('''
      create index if not exists ai_local_aliases_v61_score_idx
      on $table(accepted_count desc, last_used_at desc)
    ''');
  }

  /// Record only the concise phrase that helped identify an action, not the
  /// full chat message. Example: "send pannidu" -> "send".
  Future<void> record({
    required String sourcePhrase,
    required String canonicalAction,
    required bool accepted,
  }) async {
    final source = _clean(sourcePhrase, max: 48);
    final action = _clean(canonicalAction, max: 40);
    if (source.length < 2 || action.length < 2) return;

    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert('''
      insert into $table(
        source_phrase, canonical_action, accepted_count, rejected_count, last_used_at
      ) values(?, ?, ?, ?, ?)
      on conflict(source_phrase, canonical_action) do update set
        accepted_count = accepted_count + excluded.accepted_count,
        rejected_count = rejected_count + excluded.rejected_count,
        last_used_at = excluded.last_used_at
    ''', [source, action, accepted ? 1 : 0, accepted ? 0 : 1, now]);
  }

  /// Compact aliases may be sent as transient AI context for the current
  /// analysis request. Do not persist the returned list server-side.
  Future<List<Map<String, Object?>>> topAliases({int limit = 20}) async {
    final safeLimit = limit.clamp(1, 40);
    final rows = await db.rawQuery('''
      select source_phrase, canonical_action, accepted_count, rejected_count
      from $table
      where accepted_count > rejected_count
      order by accepted_count desc, last_used_at desc
      limit ?
    ''', [safeLimit]);
    return rows;
  }

  Future<void> clear() => db.delete(table);

  static String _clean(String value, {required int max}) {
    final compact = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (compact.length <= max) return compact;
    return compact.substring(0, max).trim();
  }
}
