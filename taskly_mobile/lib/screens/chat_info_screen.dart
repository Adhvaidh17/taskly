import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../local_chat/local_chat_runtime.dart';
import '../providers/chat_provider.dart';

// Chat Info must remain usable when live transport is temporarily unavailable.
// The local database is initialized independently; transport is not a prerequisite.
