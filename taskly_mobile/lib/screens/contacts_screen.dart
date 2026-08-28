import 'package:flutter/material.dart';

import 'people_search_screen.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PeopleSearchScreen(mode: PeopleSearchMode.newChat);
  }
}
