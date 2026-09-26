import 'package:flutter/material.dart';
import 'package:wms_app/features/labels/container_labels_screen.dart';
import 'package:wms_app/features/labels/location_labels_screen.dart';

/// Entry screen for the label printing feature.
class LabelsHomeScreen extends StatelessWidget {
  const LabelsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: const Text('Yorliqlar'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _LabelTypeCard(
            icon: Icons.place_outlined,
            title: 'Joylashuv yorliqlari',
            subtitle: 'Ombordagi joylashuv kodlarini QR bilan chop etish',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LocationLabelsScreen()),
            ),
          ),
          _LabelTypeCard(
            icon: Icons.qr_code_2,
            title: 'Konteyner yorliqlari',
            subtitle: 'Partiyaning konteyner shtrix kodlarini chop etish',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContainerLabelsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelTypeCard extends StatelessWidget {
  const _LabelTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, size: 36, color: color),
        title: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
