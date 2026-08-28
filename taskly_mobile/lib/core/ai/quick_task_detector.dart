class QuickTaskDraft {
  const QuickTaskDraft({
    required this.title,
    required this.assigneeProfileId,
  });

  final String title;
  final int assigneeProfileId;
}

class QuickTaskDetector {
  const QuickTaskDetector._();

  static final RegExp _greetingOnly = RegExp(
    r'^(hi+|hey+|hello+|thanks?|thank you|ok+|okay|good morning|good evening)[!. ]*$',
    caseSensitive: false,
  );

  static final RegExp _taskCue = RegExp(
    r"(^|\s)(task|todo|to-do|please|can you|could you|will you|need you|need to|i need to|i have to|i should|i must|remind me|remember to|don'?t forget|finish|complete|collect|send|share|prepare|make|create|update|change|fix|review|submit|call|meet|bring|pick|upload|download|mark|move|start|stop|cancel|reschedule|follow up|pay|buy|book|schedule|get|eat|read|write|check|visit|order|deliver)(\s|$|:)",
    caseSensitive: false,
  );

  /// High-recall, zero-cost hint used only for the subtle "background check"
  /// animation. It never creates a task by itself, so false positives are safe.
  static bool mightNeedTaskCheck(String body) {
    final text = body.trim();
    if (text.length < 3 || _greetingOnly.hasMatch(text)) return false;
    if (_taskCue.hasMatch(text)) return true;

    final lower = text.toLowerCase();
    final codeMixedCue = RegExp(
      r"(^|\s)(anupu|anuppu|send pannu|pannu|panra|pannunga|kondu va|eduthu va|vaangi|vangi|vangitu|kudu|kodunga|call pannu|check pannu|mudichidu|mudinju|nalaiku|naalaiku|innikku|indha|intha|bhej|bhejo|bhej do|kar do|kardo|le aao|lao|khareed|kharid|de do|dedo|kal|aaj|yaad dila|remind|submit|finish|complete)(\s|$)",
      caseSensitive: false,
      unicode: true,
    );
    if (codeMixedCue.hasMatch(lower)) return true;

    if (RegExp(r'\b(today|tomorrow|tonight|morning|evening|am|pm|by\s+\d|at\s+\d)\b', caseSensitive: false).hasMatch(text) &&
        RegExp(r'\b(send|get|buy|bring|call|pay|submit|finish|make|prepare|check|share|collect|book|schedule|update|fix|review|deliver)\b', caseSensitive: false).hasMatch(text)) {
      return true;
    }

    // Mention-led messages are frequently assignments in group chats.
    if (RegExp(r'^\s*@[^\s]+\s+\S+', unicode: true).hasMatch(text)) return true;

    // Non-Latin text is allowed to show the subtle check animation; the real
    // multilingual decision is still made by the existing local NLU/AI path.
    if (RegExp(r'[^\x00-\x7F]').hasMatch(text) && text.split(RegExp(r'\s+')).length >= 2) {
      return true;
    }
    return false;
  }

  static QuickTaskDraft? detect({
    required String body,
    required bool isGroup,
    required bool isSelfChat,
    required int currentProfileId,
    required int? otherProfileId,
    required List<int> mentionedProfileIds,
  }) {
    final text = body.trim();
    if (text.isEmpty || _greetingOnly.hasMatch(text) || !_taskCue.hasMatch(text)) {
      return null;
    }

    int? assigneeProfileId;
    if (isSelfChat) {
      assigneeProfileId = currentProfileId;
    } else if (isGroup) {
      assigneeProfileId = mentionedProfileIds.isEmpty ? null : mentionedProfileIds.first;
    } else {
      assigneeProfileId = otherProfileId;
    }

    if (assigneeProfileId == null || assigneeProfileId <= 0) return null;

    final title = _titleFrom(text);
    if (title.isEmpty) return null;

    return QuickTaskDraft(
      title: title,
      assigneeProfileId: assigneeProfileId,
    );
  }

  static String _titleFrom(String value) {
    var title = value
        .replaceAll(RegExp(r'@[\p{L}\p{N}_-]+', unicode: true), ' ')
        .trim();
    title = title
        .replaceFirst(
          RegExp(
            r"^(task\s*:?|todo\s*:?|to-do\s*:?|please\s+|can you\s+|could you\s+|will you\s+|remind me(?:\s+to)?\s+|remember to\s+|don't forget(?:\s+to)?\s+|i need to\s+|i have to\s+|i should\s+|i must\s+)",
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    title = title.replaceAll(RegExp(r'^[\-:,.!?\s]+|[\-:,.!?\s]+$'), '');
    if (title.isEmpty) return '';
    if (title.length > 120) title = title.substring(0, 120).trimRight();
    return '${title[0].toUpperCase()}${title.substring(1)}';
  }
}
