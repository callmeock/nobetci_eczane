import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart' as geo;

import '../constants/api_keys.dart';
import '../models/pharmacy.dart';
import '../widgets/pharmacy_card.dart';
import '../widgets/error_banner.dart';
import '../widgets/empty_view.dart';
import '../analytics_helper.dart'; // 🆕 EKLENDİ

class DutyPharmacyPage extends StatefulWidget {
  const DutyPharmacyPage({super.key});

  @override
  State<DutyPharmacyPage> createState() => _DutyPharmacyPageState();
}

class _DutyPharmacyPageState extends State<DutyPharmacyPage> {
  bool _initializing = true; // Splash / ilk yükleme
  bool _isLoading = false;
  String? _error;

  Position? _position;
  bool _locationFailed = false;

  bool _citiesLoading = true;
  List<String> _cityOptions = [];
  List<String> _districtOptions = [];
  String? _selectedCity;
  String? _selectedDistrict;

  List<Pharmacy> _pharmacies = [];

  @override
  void initState() {
    super.initState();
    _startInitialLoad();
  }

  Future<void> _startInitialLoad() async {
    setState(() {
      _initializing = true;
      _error = null;
    });

    await Future.wait([
      _loadCities(),
      _initLocation(),
    ]);

    if (mounted) {
      setState(() {
        _initializing = false;
      });
    }
  }

  Future<void> _loadCities() async {
    try {
      setState(() {
        _citiesLoading = true;
      });

      final uri = Uri.https(
        'api.collectapi.com',
        '/health/districtList',
        {},
      );

      final response = await http.get(
        uri,
        headers: {
          'authorization': 'apikey $collectApiToken',
          'content-type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Şehir listesi alınamadı (${response.statusCode}).');
      }

      final Map<String, dynamic> body = jsonDecode(response.body);
      final success = body['success'] == true;
      if (!success) {
        throw Exception('API şehir listesi için success=false döndü.');
      }

      final result = body['result'];
      if (result is! List) {
        throw Exception('Şehir listesi için beklenmeyen veri formatı.');
      }

      final List<String> cities = result
          .map<String>((item) => (item['text'] ?? '').toString())
          .where((name) => name.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _cityOptions = cities;
        _citiesLoading = false;
        if (_selectedCity == null && _cityOptions.isNotEmpty) {
          _selectedCity = _cityOptions.first;
          _loadDistrictsForCity(_selectedCity!);
        }
      });
    } catch (e) {
      debugPrint('Şehir listesi alınamadı: $e');
      if (!mounted) return;
      setState(() {
        _citiesLoading = false;
      });
    }
  }

  Future<void> _loadDistrictsForCity(String city) async {
    try {
      setState(() {
        _districtOptions = [];
        _selectedDistrict = null;
      });

      final uri = Uri.https(
        'api.collectapi.com',
        '/health/districtList',
        {'il': city.toLowerCase()},
      );

      final response = await http.get(
        uri,
        headers: {
          'authorization': 'apikey $collectApiToken',
          'content-type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('İlçe listesi alınamadı (${response.statusCode}).');
      }

      final Map<String, dynamic> body = jsonDecode(response.body);
      final success = body['success'] == true;
      if (!success) {
        throw Exception('API ilçe listesi için success=false döndü.');
      }

      final result = body['result'];
      if (result is! List) {
        throw Exception('İlçe listesi için beklenmeyen veri formatı.');
      }

      final List<String> districts = result
          .map<String>((item) => (item['text'] ?? '').toString())
          .where((name) => name.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _districtOptions = districts;
        if (_districtOptions.isNotEmpty) {
          _selectedDistrict = _districtOptions.first;
        }
      });
    } catch (e) {
      debugPrint('İlçe listesi alınamadı: $e');
    }
  }

  Future<void> _initLocation() async {
    try {
      final pos = await _determinePosition();
      if (!mounted) return;

      setState(() {
        _position = pos;
        _locationFailed = false;
      });

      await _fillCityDistrictFromPosition(pos);
    } catch (e) {
      debugPrint('Konum alınamadı veya çözümlenemedi: $e');
      if (!mounted) return;
      setState(() {
        _locationFailed = true;
      });
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        'Konum servisi kapalı. Lütfen cihaz ayarlarından aç.',
      );
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Konum izni verilmedi.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Konum izni kalıcı olarak reddedilmiş. Ayarlardan açman gerekiyor.',
      );
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _fillCityDistrictFromPosition(Position pos) async {
    try {
      final placemarks = await geo.placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );

      if (placemarks.isEmpty) return;

      final p = placemarks.first;

      final String city =
          (p.administrativeArea ?? p.locality ?? '').trim();
      final String district =
          (p.subAdministrativeArea ?? p.locality ?? '').trim();

      if (!mounted) return;

      String? matchedCity;
      if (_cityOptions.isNotEmpty && city.isNotEmpty) {
        final lower = city.toLowerCase();
        for (final c in _cityOptions) {
          if (c.toLowerCase().contains(lower) ||
              lower.contains(c.toLowerCase())) {
            matchedCity = c;
            break;
          }
        }
      }

      setState(() {
        if (matchedCity != null) {
          _selectedCity = matchedCity;
        } else if (city.isNotEmpty) {
          _selectedCity = city;
          if (!_cityOptions.contains(city)) {
            _cityOptions = [city, ..._cityOptions];
          }
        }
      });

      if (_selectedCity != null) {
        await _loadDistrictsForCity(_selectedCity!);

        if (district.isNotEmpty && _districtOptions.isNotEmpty) {
          String? matchedDistrict;
          final lowerDistrict = district.toLowerCase();
          for (final d in _districtOptions) {
            if (d.toLowerCase().contains(lowerDistrict) ||
                lowerDistrict.contains(d.toLowerCase())) {
              matchedDistrict = d;
              break;
            }
          }
          if (matchedDistrict != null) {
            if (!mounted) return;
            setState(() {
              _selectedDistrict = matchedDistrict;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Şehir/ilçe çözümlenemedi: $e');
    }
  }

  Future<void> _onFetchPressed() async {
    FocusScope.of(context).unfocus();

    final city = _selectedCity?.trim() ?? '';
    final district = _selectedDistrict?.trim() ?? '';

    if (city.isEmpty) {
      _showSnackBar('Lütfen şehir (il) seç.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _pharmacies = [];
    });

    try {
      // 🆕 ANALYTICS: Nöbetçi eczane aramasını logla
      final source = (_position != null && !_locationFailed)
          ? 'current_location'
          : 'manual';

      await AnalyticsHelper.logPharmacySearch(
        city: city,
        district: district.isEmpty ? null : district,
        source: source,
      );

      await _fetchDutyPharmacies(
        city: city,
        district: district.isEmpty ? null : district,
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchDutyPharmacies({
    required String city,
    String? district,
  }) async {
    final queryParams = <String, String>{
      'il': city,
      if (district != null && district.isNotEmpty) 'ilce': district,
    };

    final uri = Uri.https(
      'api.collectapi.com',
      '/health/dutyPharmacy',
      queryParams,
    );

    final response = await http.get(
      uri,
      headers: {
        'authorization': 'apikey $collectApiToken',
        'content-type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Eczane bilgileri alınamadı. (Kod: ${response.statusCode})',
      );
    }

    final Map<String, dynamic> body = jsonDecode(response.body);

    final success = body['success'] == true;
    if (!success) {
      throw Exception('API success=false döndü.');
    }

    final result = body['result'];
    if (result is! List) {
      throw Exception('Beklenmeyen veri formatı alındı.');
    }

    final List<Pharmacy> pharmacies = result
        .map<Pharmacy>(
          (item) => Pharmacy.fromJson(item as Map<String, dynamic>),
        )
        .toList();

    final pos = _position;

    if (pos != null) {
      for (final p in pharmacies) {
        if (p.lat != 0.0 && p.lng != 0.0) {
          final distance = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            p.lat,
            p.lng,
          );
          p.distanceMeters = distance;
        } else {
          p.distanceMeters = null;
        }
      }

      pharmacies.sort((a, b) {
        final da = a.distanceMeters;
        final db = b.distanceMeters;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    }

    if (!mounted) return;
    setState(() {
      _pharmacies = pharmacies;
    });
  }

  void _onCall(Pharmacy pharmacy) async {
    final cleanedPhone = pharmacy.phone.replaceAll(' ', '');
    final uri = Uri(scheme: 'tel', path: cleanedPhone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar('Arama başlatılamadı.');
    }
  }

  void _onNavigate(Pharmacy pharmacy) async {
    if (pharmacy.lat == 0.0 || pharmacy.lng == 0.0) {
      _showSnackBar('Bu eczane için konum bilgisi bulunamadı.');
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${pharmacy.lat},${pharmacy.lng}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnackBar('Harita açılamadı.');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _todayText() {
    final now = DateTime.now();
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year;
    return '$day.$month.$year';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_initializing) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Nöbetçi Eczane'),
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.location_searching,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Konum bilgileriniz alınıyor...',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sana en yakın nöbetçi eczaneleri bulmak için\n'
                    'konumunu ve şehir bilgilerini kontrol ediyoruz.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  if (_locationFailed)
                    Text(
                      'Konum alınamadı, birazdan şehir seçerek devam edebilirsin.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.red[700],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final pos = _position;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nöbetçi Eczane'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Bugünün bilgisi + konum
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.black.withOpacity(0.03),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.nightlight_round,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Bugünün nöbetçi eczaneleri',
                                  style:
                                      theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (pos != null)
                                IconButton(
                                  icon: const Icon(
                                    Icons.refresh,
                                    size: 18,
                                  ),
                                  onPressed: _initLocation,
                                  tooltip: 'Konumu yenile',
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _todayText(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                          ),
                          if (pos != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on, size: 16),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '${pos.latitude.toStringAsFixed(2)}, '
                                    '${pos.longitude.toStringAsFixed(2)}',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(
                                      color: Colors.grey.shade700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_locationFailed)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                'Konum alınamadı, lütfen şehir seç.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.red[700],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Şehir / ilçe & buton
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedCity,
                      decoration: InputDecoration(
                        labelText: 'Şehir (il)',
                        hintText: _citiesLoading
                            ? 'Şehirler yükleniyor...'
                            : 'Şehir seç',
                      ),
                      isExpanded: true,
                      items: _cityOptions
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c,
                              child: Text(c),
                            ),
                          )
                          .toList(),
                      onChanged: _citiesLoading
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedCity = value;
                                _selectedDistrict = null;
                              });
                              _loadDistrictsForCity(value);
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _selectedDistrict,
                      decoration: const InputDecoration(
                        labelText: 'İlçe (opsiyonel)',
                        hintText: 'İlçe seç',
                      ),
                      isExpanded: true,
                      items: _districtOptions
                          .map(
                            (d) => DropdownMenuItem<String>(
                              value: d,
                              child: Text(d),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() => _selectedDistrict = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _onFetchPressed,
                        icon: const Icon(Icons.search),
                        label: const Text('Nöbetçi Eczaneleri Getir'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ErrorBanner(message: _error!),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _pharmacies.isEmpty
                      ? const EmptyView(
                          message:
                              'Şehir ve istersen ilçe seçip,\n'
                              '“Nöbetçi Eczaneleri Getir” butonuna bas.',
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _pharmacies.length,
                          itemBuilder: (context, index) {
                            final pharmacy = _pharmacies[index];
                            return PharmacyCard(
                              pharmacy: pharmacy,
                              onCall: () => _onCall(pharmacy),
                              onNavigate: () => _onNavigate(pharmacy),
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
