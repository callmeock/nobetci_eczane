import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsHelper {
  // Tek bir instance kullanalım
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Uygulama açıldığında test için bir event yollayacağız
  static Future<void> logAppStart() async {
    try {
      await _analytics.logEvent(
        name: 'app_start',
        parameters: {
          'app': 'nobetci_eczane',
        },
      );
      // Debug için konsola da yaz
      // (bunu terminalde görürsen, fonksiyon çalışıyor demektir)
      // print('✅ Analytics: app_start event logged');
    } catch (e) {
      // print('❌ Analytics logAppStart error: $e');
    }
  }

  static Future<void> logPharmacySearch({
    required String city,
    String? district,
    required String source, // current_location / manual
  }) async {
    try {
      await _analytics.logEvent(
        name: 'pharmacy_search',
        parameters: {
          'city': city,
          if (district != null) 'district': district,
          'source': source,
        },
      );
      // print('✅ pharmacy_search logged');
    } catch (e) {
      // print('❌ pharmacy_search error: $e');
    }
  }

  static Future<void> logMedicineSearch({
    required String query,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'medicine_search',
        parameters: {
          'query': query,
        },
      );
      // print('✅ medicine_search logged');
    } catch (e) {
      // print('❌ medicine_search error: $e');
    }
  }

  static Future<void> logMedicineDetailView({
    required String barcode,
    required String name,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'medicine_detail_view',
        parameters: {
          'barcode': barcode,
          'name': name,
        },
      );
      // print('✅ medicine_detail_view logged');
    } catch (e) {
      // print('❌ medicine_detail_view error: $e');
    }
  }

  static Future<void> logMedicineReminderCreated({
    required String barcode,
    required String name,
    required int timesPerDay,
    required int days,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'medicine_reminder_created',
        parameters: {
          'barcode': barcode,
          'name': name,
          'times_per_day': timesPerDay,
          'days': days,
        },
      );
      // print('✅ medicine_reminder_created logged');
    } catch (e) {
      // print('❌ medicine_reminder_created error: $e');
    }
  }
}
