import 'package:flutter/material.dart';

import '../admin/admin_service.dart';
import 'admin_widgets.dart';
import '../l10n/l10n.dart';

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
      appBar: AppBar(title: Text(context.tr('app.admin_users.users'))),
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
      title: context.tr('app.admin_users.new_user'),
      label: context.tr('common.field.username.label'),
      yes: context.tr('common.date.picker.next.aria'),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final pass = await askText(
      context,
      title: context.tr('app.admin_users.a_password_for_trim', {
        'trim': name.trim(),
      }),
      label: context.tr('common.field.password.label'),
      secret: true,
      yes: context.tr('common.action.add.label'),
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
      title: make
          ? context.tr('app.admin_users.make_username_an_admin', {
              'username': u.username,
            })
          : context.tr('app.admin_users.step_username_down', {
              'username': u.username,
            }),
      body: make
          ? context.tr('app.admin_users.an_admin_can_see_every_job')
          : '${u.username} will no longer be able to change the server.',
      yes: make
          ? context.tr('account.users.make-admin')
          : context.tr('account.users.step-down'),
    );
    if (!ok || !context.mounted) return;
    if (await attempt(context, () => service.setAdmin(u.id, make))) {
      await reload();
    }
  }

  Future<void> _delete(BuildContext context, AdminUser u) async {
    final ok = await confirmDialog(
      context,
      title: context.tr('app.admin_users.remove_username', {
        'username': u.username,
      }),
      body: 'Their whole library goes with them: every work, quote and tag. This cannot be undone.',
      yes: context.tr('common.action.remove.label'),
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
                              tooltip: context.tr(
                                'settings.appearance.contrast.more.label',
                              ),
                              onSelected: (v) => v == 'admin'
                                  ? _toggleAdmin(context, u)
                                  : _delete(context, u),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'admin',
                                  child: Text(
                                    u.isAdmin
                                        ? context.tr(
                                            'app.admin_users.step_down_from_admin',
                                          )
                                        : context.tr(
                                            'account.users.make-admin',
                                          ),
                                  ),
                                ),
                                if (!u.isAdmin)
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      context.tr(
                                        'app.admin_users.remove_this_user',
                                      ),
                                    ),
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
            label: Text(context.tr('app.admin_users.add_a_user')),
          ),
        ),
      ],
    );
  }
}
