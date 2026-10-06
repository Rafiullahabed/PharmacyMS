import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../../inventory/application/inventory_controller.dart';
import 'units_screen.dart';
import '../../backup/application/backup_controller.dart';
import '../../backup/presentation/backup_screen.dart';
import 'appearance_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller, this.backups});
  final InventoryController controller;
  final BackupController? backups;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: pageAppBar(context, title: 'Settings'),
    body: SafeArea(
      child: PageContent(
        children: [
          AppearanceSettings(resolve: () => controller.settings),
          Section(
            title: 'Units',
            icon: Icons.straighten_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Each item uses one counting unit.'),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  title: const Text('Manage units'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UnitsScreen(controller: controller),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Section(
            title: 'Backup & Restore',
            icon: Icons.shield_outlined,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              title: const Text('Portable backup and restore'),
              subtitle: const Text(
                'Keep a private copy or restore a previous backup.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: backups == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BackupScreen(controller: backups!),
                      ),
                    ),
            ),
          ),
          const Section(
            title: 'About',
            icon: Icons.local_pharmacy_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Pharmacy Companion'),
                SizedBox(height: 8),
                Text('Version 0.8.0 · Offline pharmacy notebook'),
                SizedBox(height: 8),
                Text(
                  'Inventory, manual daily sales/profit and customer debt work independently on this device. Portable backups include all records and settings.',
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Pharmacy Companion',
              applicationVersion: '0.8.0',
            ),
            child: const Text('Open-source licenses'),
          ),
        ],
      ),
    ),
  );
}
