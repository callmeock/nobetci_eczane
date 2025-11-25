import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../analytics_helper.dart';



class MedicineSearchPage extends StatefulWidget {
  const MedicineSearchPage({super.key});

  @override
  State<MedicineSearchPage> createState() => _MedicineSearchPageState();
}

class _MedicineSearchPageState extends State<MedicineSearchPage> {
  final TextEditingController _queryController = TextEditingController();

  bool _isLoading = false;
  bool _isCsvLoaded = false;
  int _loadedCount = 0;
  String? _error;

  List<MedicineResult> _allMedicines = [];
  List<MedicineResult> _results = [];

  // 🔤 Alfabetik filtre için – İngilizce alfabe
  final List<String> _letters = const [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
    'U', 'V', 'W', 'X', 'Y', 'Z',
  ];
  String? _selectedLetter; // null = hepsi

  // ⚠️ Doktor uyarısı için
  bool _dontShowWarningAgain = false;

  @override
  void initState() {
    super.initState();
    _loadWarningPreference();
    _loadMedicinesFromCsv();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  // ------------------------------
  // 1) UYARI PREF + DİYALOG
  // ------------------------------

  Future<void> _loadWarningPreference() async {
    final prefs = await SharedPreferences.getInstance();
    _dontShowWarningAgain = prefs.getBool('med_warning_dont_show') ?? false;

    if (!_dontShowWarningAgain) {
      // UI hazır olduktan sonra dialog göster
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showMedicalWarningDialog();
      });
    }
  }

  Future<void> _showMedicalWarningDialog() async {
    bool localDontShow = _dontShowWarningAgain;

    await showDialog(
      context: context,
      barrierDismissible: false, // mutlaka Tamam'a basılsın
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Önemli Uyarı'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Bu sayfa yalnızca bilgilendirme amaçlıdır.\n\n'
                    'İlaçları mutlaka doktorunuzun önerdiği şekilde, '
                    'doktorunuzun belirlediği dozlarda kullanınız.\n\n'
                    'Bu uygulama tanı koymaz, tedavi önermez ve '
                    'doktor muayenesinin yerine geçmez.',
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: localDontShow,
                    onChanged: (val) {
                      setStateDialog(() {
                        localDontShow = val ?? false;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Bu uyarıyı bir daha gösterme'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    // Kararı kalıcı kaydet
                    setState(() {
                      _dontShowWarningAgain = localDontShow;
                    });
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool(
                      'med_warning_dont_show',
                      localDontShow,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Tamam'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ------------------------------
  // 2) CSV YÜKLEME
  // ------------------------------

  Future<void> _loadMedicinesFromCsv() async {
    try {
      final raw = await rootBundle.loadString('assets/medicines.csv');

      // Önce ; ile dene, tek kolon çıkarsa , ile tekrar dene
      List<List<dynamic>> rows = const CsvToListConverter(
        fieldDelimiter: ';',
        eol: '\n',
        shouldParseNumbers: false,
      ).convert(raw);

      if (rows.isEmpty || rows.first.length == 1) {
        rows = const CsvToListConverter(
          fieldDelimiter: ',',
          eol: '\n',
          shouldParseNumbers: false,
        ).convert(raw);
      }

      if (rows.isEmpty) return;

      final header = rows.first.map((e) => e.toString().trim()).toList();

      int idxLetter = header.indexOf('Letter');
      int idxDrugName = header.indexOf('Drug Name');
      int idxPrice = header.indexOf('Price');
      int idxPrescReq =
          header.indexOf('Prescription Required (hkt-küb)');
      int idxProsp = header.indexOf('Prosp');
      int idxActive = header.indexOf('Active Ingredient');
      int idxAtc = header.indexOf('ATC Code');
      int idxPrescStatus = header.indexOf('Prescription Status');
      int idxCompany = header.indexOf('Pharmaceutical Company');
      int idxBarcode = header.indexOf('Barcode');
      int idxLastUpdate = header.indexOf('Last Update Date');
      int idxDetailUrl = header.indexOf('Detail Page URL');
      int idxHowToUse = header.indexOf('Nasıl Kullanılmalı?');
      int idxIndications =
          header.indexOf('Hangi Hastalıklar İçin Kullanılır?');

      String getField(List<dynamic> row, int idx) {
        if (idx < 0 || idx >= row.length) return '';
        return row[idx].toString();
      }

      final List<MedicineResult> meds = [];
      for (final row in rows.skip(1)) {
        if (row.isEmpty) continue;

        final drugName = getField(row, idxDrugName).trim();
        if (drugName.isEmpty) continue;

        final activeIngredient = getField(row, idxActive).trim();
        final company = getField(row, idxCompany).trim();
        final barcode = getField(row, idxBarcode).trim();
        final price = getField(row, idxPrice).trim();
        final prescReq = getField(row, idxPrescReq).trim();
        final prescStatus = getField(row, idxPrescStatus).trim();
        final atc = getField(row, idxAtc).trim();
        final lastUpdate = getField(row, idxLastUpdate).trim();
        final detailUrl = getField(row, idxDetailUrl).trim();
        final howToUse = getField(row, idxHowToUse).trim();
        final indications = getField(row, idxIndications).trim();
        final letter = getField(row, idxLetter).trim();
        final prosp = getField(row, idxProsp).trim();

        meds.add(
          MedicineResult(
            name: drugName,
            activeIngredient: activeIngredient,
            company: company,
            price: price.isEmpty ? null : price,
            barcode: barcode.isEmpty ? null : barcode,
            prescriptionRequired:
                prescReq.isEmpty ? null : prescReq,
            prescriptionStatus:
                prescStatus.isEmpty ? null : prescStatus,
            atcCode: atc.isEmpty ? null : atc,
            lastUpdate: lastUpdate.isEmpty ? null : lastUpdate,
            detailUrl: detailUrl.isEmpty ? null : detailUrl,
            howToUse: howToUse.isEmpty ? null : howToUse,
            indications: indications.isEmpty ? null : indications,
            letter: letter.isEmpty ? null : letter,
            prosp: prosp.isEmpty ? null : prosp,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _allMedicines = meds;
        _isCsvLoaded = true;
        _loadedCount = meds.length;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'İlaç verileri yüklenirken hata oluştu: $e';
      });
    }
  }

  // ------------------------------
  // 3) ARAMA ALGORİTMASI
  // ------------------------------

  // Arama algoritması (önce isim başı, sonra isim içi, sonra diğer alanlar)
  List<MedicineResult> _searchMedicines(String query) {
    final lower = query.toLowerCase();

    final List<MedicineResult> startsWith = [];
    final List<MedicineResult> inName = [];
    final List<MedicineResult> others = [];

    for (final m in _allMedicines) {
      final name = m.name.toLowerCase();
      final active = m.activeIngredient.toLowerCase();
      final company = m.company.toLowerCase();
      final barcode = (m.barcode ?? '').toLowerCase();

      if (name.startsWith(lower)) {
        startsWith.add(m);
      } else if (name.contains(lower)) {
        inName.add(m);
      } else if (active.contains(lower) ||
          company.contains(lower) ||
          barcode.contains(lower)) {
        others.add(m);
      }
    }

    return [...startsWith, ...inName, ...others];
  }

  /// Hem arama metni hem harf filtresini birlikte uygulayan tek yer
  void _updateResults({bool fromSearchButton = false}) {
    if (!_isCsvLoaded) return;

    final query = _queryController.text.trim();
    List<MedicineResult> base = [];

    // 1) Metne göre sonuç
    if (query.isEmpty) {
      // Sorgu yok → sadece harfe göre liste
      if (_selectedLetter != null) {
        base = List<MedicineResult>.from(_allMedicines);
      } else {
        base = [];
      }
    } else {
      // Live search için 3 harf altı threshold
      if (!fromSearchButton && query.length < 3) {
        // Butona basmadıysa ve 3 harften azsa arama yapma
        if (_selectedLetter != null) {
          base = List<MedicineResult>.from(_allMedicines);
        } else {
          base = [];
        }
      } else {
        base = _searchMedicines(query);
      }
    }

    // 2) Harf filtresini uygula
    if (_selectedLetter != null) {
      final letterUpper = _selectedLetter!;
      base = base.where((m) {
        final sourceLetter = (m.letter != null && m.letter!.isNotEmpty)
            ? m.letter!
            : m.name.substring(0, 1);
        return sourceLetter.toUpperCase() == letterUpper;
      }).toList();
    }

    setState(() {
      _results = base;
      _isLoading = false;
    });
  }

  Future<void> _onSearchPressed() async {
    final query = _queryController.text.trim();
    if (query.isEmpty && _selectedLetter == null) {
      _showSnackBar('En az bir arama kelimesi ya da harf seçmelisin.');
      return;
    }
    if (!_isCsvLoaded) {
      _showSnackBar('İlaç verileri henüz yüklenmedi, birazdan tekrar dene.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    await AnalyticsHelper.logMedicineSearch(query: query);
    
    _updateResults(fromSearchButton: true);
  }

  void _onQueryChanged(String value) {
    if (!_isCsvLoaded) return;
    _updateResults(fromSearchButton: false);
  }

  void _onLetterTapped(String letter) {
    if (!_isCsvLoaded) return;
    setState(() {
      if (_selectedLetter == letter) {
        _selectedLetter = null; // toggle off
      } else {
        _selectedLetter = letter;
      }
    });
    _updateResults(fromSearchButton: false);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------
  // 4) BUILD
  // ------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('İlaç Sorgulama'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ÜST ARAMA BLOĞU
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _queryController,
                    textInputAction: TextInputAction.search,
                    onChanged: _onQueryChanged,
                    onSubmitted: (_) => _onSearchPressed(),
                    decoration: const InputDecoration(
                      labelText: 'İlaç adı / etken madde / barkod',
                      hintText: 'Örn: PAROL, NUROFEN, PARASETAMOL...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _onSearchPressed,
                      icon: const Icon(Icons.search),
                      label: const Text('İlaç Bilgisini Getir'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (!_isCsvLoaded)
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'İlaç veritabanı yükleniyor (offline CSV)...',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Offline ilaç verisi: $_loadedCount kayıt yüklendi',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Canlı arama 3 harften sonra devreye giriyor. '
                    'Aşağıdan harf seçerek listeyi filtreleyebilirsin.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 🔤 ALFABETİK ŞERİT
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _letters.map((letter) {
                        final isSelected = _selectedLetter == letter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: ChoiceChip(
                            label: Text(letter),
                            selected: isSelected,
                            onSelected: (_) => _onLetterTapped(letter),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _ErrorBanner(message: _error!),
              ),

            // SONUÇ LİSTESİ
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              _selectedLetter == null &&
                                      _queryController.text.trim().isEmpty
                                  ? 'İlaç ismi, etkin madde, firma veya barkod ile\n'
                                    'offline veritabanından arama yapabilirsin.\n\n'
                                    'Ya da üstteki harflerden birini seçerek\n'
                                    'o harfle başlayan ilaçları listeleyebilirsin.'
                                  : 'Filtrelerine uygun ilaç bulunamadı.\n'
                                    'Arama metnini veya harf seçimini değiştirmeyi deneyebilirsin.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final med = _results[index];
                            return _MedicineCard(
                              med: med,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        MedicineDetailPage(med: med),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// MODEL
class MedicineResult {
  final String name; // Drug Name
  final String activeIngredient; // Active Ingredient
  final String company; // Pharmaceutical Company
  final String? price; // Price
  final String? barcode; // Barcode
  final String? prescriptionRequired; // Prescription Required (hkt-küb)
  final String? prescriptionStatus; // Prescription Status
  final String? atcCode; // ATC Code
  final String? lastUpdate; // Last Update Date
  final String? detailUrl; // Detail Page URL
  final String? howToUse; // Nasıl Kullanılmalı?
  final String? indications; // Hangi Hastalıklar İçin Kullanılır?
  final String? letter; // Letter
  final String? prosp; // Prosp

  MedicineResult({
    required this.name,
    required this.activeIngredient,
    required this.company,
    this.price,
    this.barcode,
    this.prescriptionRequired,
    this.prescriptionStatus,
    this.atcCode,
    this.lastUpdate,
    this.detailUrl,
    this.howToUse,
    this.indications,
    this.letter,
    this.prosp,
  });
}

/// LİSTEDEKİ KISA KART
class _MedicineCard extends StatelessWidget {
  final MedicineResult med;
  final VoidCallback onTap;

  const _MedicineCard({
    required this.med,
    required this.onTap,
  });

  Color _statusColor() {
    final status = (med.prescriptionStatus ?? med.prescriptionRequired ?? '')
        .toLowerCase();
    if (status.contains('reçetesiz') || status.contains('otc')) {
      return Colors.green;
    }
    if (status.contains('reçeteli') || status.contains('kırmızı')) {
      return Colors.red;
    }
    return Colors.blueGrey;
  }

  String _statusText() {
    if (med.prescriptionStatus != null &&
        med.prescriptionStatus!.isNotEmpty) {
      return med.prescriptionStatus!;
    }
    if (med.prescriptionRequired != null &&
        med.prescriptionRequired!.isNotEmpty) {
      return med.prescriptionRequired!;
    }
    return 'Reçete bilgisi yok';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor();
    final statusText = _statusText();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.medication_outlined,
                size: 32,
                color: theme.colorScheme.primary.withOpacity(0.9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1) İlaç adı
                    Text(
                      med.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // 2) Reçete chip'i (ALT SATIRDA)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: statusColor.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          statusText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // 3) Etken madde + firma
                    Text(
                      [
                        if (med.activeIngredient.isNotEmpty)
                          'Etken madde: ${med.activeIngredient}',
                        if (med.company.isNotEmpty) 'Firma: ${med.company}',
                      ].join('  •  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade800,
                      ),
                    ),

                    const SizedBox(height: 6),

                    // 4) Fiyat / Barkod chip'leri
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (med.price != null && med.price!.isNotEmpty)
                          Chip(
                            label: Text(
                              'Fiyat: ${med.price}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        if (med.barcode != null && med.barcode!.isNotEmpty)
                          Chip(
                            avatar: const Icon(Icons.qr_code_2, size: 14),
                            label: Text(
                              med.barcode!,
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // 5) "Detayı gör" CTA
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Detayı gör',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// DETAY SAYFASI
class MedicineDetailPage extends StatelessWidget {
  final MedicineResult med;

  const MedicineDetailPage({super.key, required this.med});

  Color _statusColor() {
    final status = (med.prescriptionStatus ?? med.prescriptionRequired ?? '')
        .toLowerCase();
    if (status.contains('reçetesiz') || status.contains('otc')) {
      return Colors.green;
    }
    if (status.contains('reçeteli') || status.contains('kırmızı')) {
      return Colors.red;
    }
    return Colors.blueGrey;
  }

  String _statusText() {
    if (med.prescriptionStatus != null &&
        med.prescriptionStatus!.isNotEmpty) {
      return med.prescriptionStatus!;
    }
    if (med.prescriptionRequired != null &&
        med.prescriptionRequired!.isNotEmpty) {
      return med.prescriptionRequired!;
    }
    return 'Reçete bilgisi yok';
  }

  Future<void> _openDetailUrl(BuildContext context) async {
    final url = med.detailUrl;
    if (url == null || url.isEmpty) return;

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Detay sayfası açılamadı.')),
      );
    }
  }

  Widget _buildInfoRow(String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String? content,
  }) {
    if (content == null || content.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ExpansionTile(
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding:
            const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Text(
            content.trim(),
            style: const TextStyle(height: 1.4),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();
    final statusText = _statusText();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          med.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ÜST KART: İSİM + STATUS
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.medication_rounded,
                        size: 40,
                        color: statusColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              med.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets
                                      .symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        statusColor.withOpacity(0.08),
                                    borderRadius:
                                        BorderRadius.circular(999),
                                    border: Border.all(
                                      color: statusColor
                                          .withOpacity(0.4),
                                    ),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                if (med.price != null &&
                                    med.price!.isNotEmpty)
                                  Chip(
                                    label: Text(
                                      'Fiyat: ${med.price}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                      ),
                                    ),
                                    visualDensity:
                                        VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize
                                            .shrinkWrap,
                                  ),
                                if (med.barcode != null &&
                                    med.barcode!.isNotEmpty)
                                  Chip(
                                    avatar: const Icon(
                                      Icons.qr_code_2,
                                      size: 14,
                                    ),
                                    label: Text(
                                      med.barcode!,
                                      style: const TextStyle(
                                        fontSize: 11,
                                      ),
                                    ),
                                    visualDensity:
                                        VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize
                                            .shrinkWrap,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // TEMEL BİLGİLER
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Temel Bilgiler',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Etken madde',
                        med.activeIngredient.isEmpty
                            ? null
                            : med.activeIngredient,
                      ),
                      _buildInfoRow(
                        'Firma',
                        med.company.isEmpty ? null : med.company,
                      ),
                      _buildInfoRow(
                        'ATC Kodu',
                        med.atcCode,
                      ),
                      _buildInfoRow(
                        'Güncelleme Tarihi',
                        med.lastUpdate,
                      ),
                      _buildInfoRow(
                        'Harf',
                        med.letter,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // UZUN METİN BÖLÜMLERİ
              _buildSection(
                title: 'Nasıl Kullanılır?',
                content: med.howToUse,
              ),
              _buildSection(
                title: 'Hangi Hastalıklar İçin Kullanılır?',
                content: med.indications,
              ),
              _buildSection(
                title: 'Prospektüs Bilgisi',
                content: med.prosp,
              ),

              const SizedBox(height: 8),

              if (med.detailUrl != null &&
                  med.detailUrl!.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openDetailUrl(context),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Resmî detay sayfasını aç'),
                  ),
                ),

              const SizedBox(height: 16),
              Text(
                '⚠️ Bu bilgiler sadece bilgilendirme amaçlıdır. '
                'İlaçları mutlaka doktorunuzun önerdiği şekilde kullanınız.',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.red[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
