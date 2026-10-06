import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../../inventory/application/inventory_controller.dart';
import 'units_screen.dart';
import '../../backup/application/backup_controller.dart';
import '../../backup/presentation/backup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller, this.backups});
  final InventoryController controller;
  final BackupController? backups;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: SafeArea(
      child: PageContent(
        children: [
          Section(
            title: 'Units',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Each item uses one counting unit.'),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
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
            child: ListTile(
              contentPadding: EdgeInsets.zero,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Pharmacy Companion'),
                SizedBox(height: 8),
                Text('Phase 6 · Portable backup and restore'),
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
              applicationVersion: '0.6.0',
            ),
            child: const Text('Open-source licenses'),
          ),
        ],
      ),
    ),
  );
}
