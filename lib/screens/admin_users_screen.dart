import 'package:flutter/material.dart';

import '../admin/admin_service.dart';
import 'admin_widgets.dart';

/// The accounts on the server: add one, make one an admin or step them down, remove one. The server refuses to
/// remove yourself or another admin, and says why; its words are shown as they come.
class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key, required this.service, this.myName = ''});

  final AdminService service;

  /// The account this phone is paired as, marked in the list.
  final String myName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: Loader<List<AdminUser>>(
        load: service.users,
        builder: (context, users, reload) => _Users(
          service: service,
          users: users,
          reload: reload,
          myName: myName,
        ),
      ),
    );
  }
}

class _Users extends StatelessWidget {
  const _Users({
    required this.service,
    required this.users,
    required this.reload,
    required this.myName,
  });

  final AdminService service;
  final List<AdminUser> users;
  final Future<void> Function() reload;
  final String myName;

  Future<void> _add(BuildContext context) async {
    final name = await askText(
      context,
      title: 'New user',
      label: 'Username',
      yes: 'Next',
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final pass = await askText(
      context,
      title: 'A password for ${name.trim()}',
      label: 'Password',
      secret: true,
      yes: 'Add',
    );
    if (pass == null || pass.isEmpty || !context.mounted) return;
    if (await attempt(context, () => service.addUser(name.trim(), pass)) &&
        context.mounted) {
      say(
        context,
        '${name.trim()} is added. They choose their own password when they first sign in.',
      );
      await reload();
    }
  }

  Future<void> _toggleAdmin(BuildContext context, AdminUser u) async {
    final make = !u.isAdmin;
    final ok = await confirmDialog(
      context,
      title: make ? 'Make ${u.username} an admin?' : 'Step ${u.username} down?',
      body: make
          ? 'An admin can see every job, change the server and its backups, and add or remove users.'
          : '${u.username} will no longer be able to change the server.',
      yes: make ? 'Make admin' : 'Step down',
    );
    if (!ok || !context.mounted) return;
    if (await attempt(context, () => service.setAdmin(u.id, make))) {
      await reload();
    }
  }

  Future<void> _delete(BuildContext context, AdminUser u) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove ${u.username}?',
      body: 'Their whole library goes with them: every work, quote and tag. This cannot be undone.',
      yes: 'Remove',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    if (await attempt(context, () => service.deleteUser(u.id))) {
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              for (final u in users)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: u.isAdmin
                            ? scheme.primaryContainer
                            : scheme.secondaryContainer,
                        child: Text(u.username.characters.first.toUpperCase()),
                      ),
                      title: Text(u.username),
                      subtitle: Text(
                        [
                          if (u.isAdmin) 'Admin',
                          if (u.username == myName) 'You',
                          if (u.createdAt.isNotEmpty) 'Joined ${u.createdAt}',
                        ].join(' · '),
                      ),
                      // The server's own rules: only an admin can step themselves down, and an admin is removed only
                      // after they have. So another admin has nothing to offer here.
                      trailing: u.isAdmin && u.username != myName
                          ? null
                          : PopupMenuButton<String>(
                              tooltip: 'More',
                              onSelected: (v) => v == 'admin'
                                  ? _toggleAdmin(context, u)
                                  : _delete(context, u),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'admin',
                                  child: Text(
                                    u.isAdmin
                                        ? 'Step down from admin'
                                        : 'Make admin',
                                  ),
                                ),
                                if (!u.isAdmin)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Remove this user'),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add-user',
            onPressed: () => _add(context),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add a user'),
          ),
        ),
      ],
    );
  }
}
