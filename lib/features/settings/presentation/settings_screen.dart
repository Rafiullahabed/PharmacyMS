import 'package:flutter/material.dart';
import '../../../core/presentation/components.dart';
import '../../inventory/application/inventory_controller.dart';
import 'units_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});
  final InventoryController controller;
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
          const Section(
            title: 'Backup & Restore',
            child: Text('Backup and restore are not available in this build.'),
          ),
          const Section(
            title: 'About',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Pharmacy Companion'),
                SizedBox(height: 8),
                Text('Phase 5 · Customer debt notebook'),
                SizedBox(height: 8),
                Text(
                  'Inventory and units work on this device. Daily record entry, customer ledger screens, and backups will follow in later phases.',
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Pharmacy Companion',
              applicationVersion: '0.5.0',
            ),
            child: const Text('Open-source licenses'),
          ),
        ],
      ),
    ),
  );
}
