import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/medicine_result.dart';
import '../analytics_helper.dart';


class MedicineDetailPage extends StatelessWidget {
  final MedicineResult medicine;

  const MedicineDetailPage({
    super.key,
    required this.medicine,
  });

  void _openDetailUrl() async {
    final url = medicine.detailUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildInfoRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AnalyticsHelper.logMedicineDetailView(
    barcode: medicine.barcode ?? 'no_barcode',
    name: medicine.name,);
    
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(medicine.name),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicine.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('Etkin madde', medicine.activeIngredient),
                  _buildInfoRow('Firma', medicine.company),
                  _buildInfoRow('Fiyat', medicine.price),
                  _buildInfoRow('Barkod', medicine.barcode),
                  _buildInfoRow(
                    'Reçete durumu',
                    medicine.prescriptionStatus ??
                        medicine.prescriptionRequired,
                  ),
                  _buildInfoRow('ATC Kodu', medicine.atcCode),
                  _buildInfoRow('Son güncelleme', medicine.lastUpdate),
                  _buildInfoRow('Harf', medicine.letter),
                  const SizedBox(height: 12),
                  _buildInfoRow('Nasıl kullanılır?', medicine.howToUse),
                  _buildInfoRow(
                    'Hangi hastalıklar için kullanılır?',
                    medicine.indications,
                  ),
                  _buildInfoRow('Prospektüs', medicine.prosp),
                  const SizedBox(height: 16),
                  if (medicine.detailUrl != null &&
                      medicine.detailUrl!.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _openDetailUrl,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Resmi detay sayfası'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
