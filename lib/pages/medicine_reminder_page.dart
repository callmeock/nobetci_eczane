import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../analytics_helper.dart';
import '../models/medicine_reminder.dart';

class MedicineReminderPage extends StatefulWidget {
  const MedicineReminderPage({super.key});

  @override
  State<MedicineReminderPage> createState() => _MedicineReminderPageState();
}

class _MedicineReminderPageState extends State<MedicineReminderPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _doseController = TextEditingController();
  final TextEditingController _timesPerDayController =
      TextEditingController(text: '2');
  final TextEditingController _daysController =
      TextEditingController(text: '5');
  final TextEditingController _intervalDaysController =
      TextEditingController(text: '1'); // 🔥 kaç günde bir

  String _mealTiming = 'Tok';
  DateTime _startDate = DateTime.now();
  TimeOfDay _firstReminderTime = const TimeOfDay(hour: 9, minute: 0);

  final List<MedicineReminder> _reminders = [];

  // 🔔 Local notification plugin
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadRemindersFromStorage();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _doseController.dispose();
    _timesPerDayController.dispose();
    _daysController.dispose();
    _intervalDaysController.dispose();
    super.dispose();
  }

  // -----------------------------
  // NOTIFICATION INIT & HELPERS
  // -----------------------------

  Future<void> _initNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);

    // iOS izin iste
    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  Future<int> _getNextNotificationId() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('notification_id_counter') ?? 0;
    final next = current + 1;
    await prefs.setInt('notification_id_counter', next);
    return next;
  }

  String _buildNotificationBody(MedicineReminder r) {
    final doseText = (r.dose != null && r.dose!.trim().isNotEmpty)
        ? r.dose!.trim()
        : 'İlacını almayı unutma.';
    final mealText = r.mealTiming == 'Fark etmez'
        ? ''
        : ' (${r.mealTiming.toLowerCase()} karnına)';
    return '$doseText$mealText';
  }

  Future<void> _scheduleNotificationsFor(MedicineReminder reminder) async {
    final now = DateTime.now();

    // İlk günün, seçilen saate sabitlenmiş hali
    final baseDateTime = DateTime(
      reminder.startDate.year,
      reminder.startDate.month,
      reminder.startDate.day,
      reminder.firstReminderHour,
      reminder.firstReminderMinute,
    );

    final totalDays = reminder.totalDays;
    final timesPerDay = reminder.timesPerDay.clamp(1, 4); // 1–4 arası sınırla
    final intervalDays = reminder.intervalDays.clamp(1, 365);

    // Basit dağıtım: her doz arası ~4 saat artış (max 4 doz için)
    const perDoseHourOffset = 4;

    final List<int> createdIds = [];

    for (int dayOffset = 0; dayOffset < totalDays; dayOffset += intervalDays) {
      final dayBase = baseDateTime.add(Duration(days: dayOffset));

      for (int i = 0; i < timesPerDay; i++) {
        final scheduledTime =
            dayBase.add(const Duration(hours: perDoseHourOffset) * i);

        // Geçmiş bir zamana bildirim schedule etme
        if (scheduledTime.isBefore(now)) continue;

        final id = await _getNextNotificationId();
        createdIds.add(id);

        const androidDetails = AndroidNotificationDetails(
          'medicine_reminders',
          'İlaç Hatırlatmaları',
          channelDescription: 'İlaç kullanım zamanları için hatırlatmalar.',
          importance: Importance.high,
          priority: Priority.high,
        );

        const iosDetails = DarwinNotificationDetails();

        const details = NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        );

        await _notifications.zonedSchedule(
          id,
          'İlaç Hatırlatma: ${reminder.name}',
          _buildNotificationBody(reminder),
          tz.TZDateTime.from(scheduledTime, tz.local),
          details,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }

    // Oluşan ID'leri hatırlatmanın içine yaz
    reminder.notificationIds.addAll(createdIds);
  }

  // -----------------------------
  // STORAGE (SharedPreferences)
  // -----------------------------

  Future<void> _loadRemindersFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('medicine_reminders_v1');
    if (jsonStr == null || jsonStr.isEmpty) return;

    final List<dynamic> list = jsonDecode(jsonStr);
    final List<MedicineReminder> all = list
        .map((e) => MedicineReminder.fromJson(e as Map<String, dynamic>))
        .toList();

    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    // Süresi bitenleri ele
    final active = all.where((r) {
      final endDate =
          r.startDate.add(Duration(days: r.totalDays)); // bitiş dahil
      final endDateOnly =
          DateTime(endDate.year, endDate.month, endDate.day);
      return !endDateOnly.isBefore(todayDateOnly);
    }).toList();

    setState(() {
      _reminders
        ..clear()
        ..addAll(active);
    });

    // Storage'ı da sadece aktifle güncelle
    await _saveRemindersToStorage();
  }

  Future<void> _saveRemindersToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _reminders.map((r) => r.toJson()).toList();
    await prefs.setString('medicine_reminders_v1', jsonEncode(list));
  }

  // -----------------------------
  // UI ACTIONS
  // -----------------------------

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _startDate,
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  /// Yeni saat/dakika seçici – bottom sheet içinde 2 kolonlu liste
  Future<void> _showTimePickerSheet() async {
    final List<int> hours = List.generate(24, (i) => i); // 0–23
    final List<int> minutes = List.generate(12, (i) => i * 5); // 0,5,10..55

    int selectedHour = _firstReminderTime.hour;
    // Dakika listesinde en yakın 5'lilik değeri bul
    int initialMinuteValue = (_firstReminderTime.minute ~/ 5) * 5;
    if (!minutes.contains(initialMinuteValue)) {
      initialMinuteValue = 0;
    }
    int selectedMinute = initialMinuteValue;

    final int initialHourIndex = hours.indexOf(selectedHour);
    final int initialMinuteIndex = minutes.indexOf(initialMinuteValue);

    final result = await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'İlk hatırlatma saati',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Saati ve dakikayı listeden seç',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text(
                            'Saat',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: FixedExtentScrollController(
                                initialItem: initialHourIndex >= 0
                                    ? initialHourIndex
                                    : 9,
                              ),
                              itemExtent: 32,
                              onSelectedItemChanged: (index) {
                                selectedHour = hours[index];
                              },
                              children: hours
                                  .map(
                                    (h) => Center(
                                      child: Text(
                                        h.toString().padLeft(2, '0'),
                                        style:
                                            const TextStyle(fontSize: 18),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      color: Colors.grey.shade200,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          const Text(
                            'Dakika',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: FixedExtentScrollController(
                                initialItem: initialMinuteIndex >= 0
                                    ? initialMinuteIndex
                                    : 0,
                              ),
                              itemExtent: 32,
                              onSelectedItemChanged: (index) {
                                selectedMinute = minutes[index];
                              },
                              children: minutes
                                  .map(
                                    (m) => Center(
                                      child: Text(
                                        m.toString().padLeft(2, '0'),
                                        style:
                                            const TextStyle(fontSize: 18),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text('İptal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          final time = TimeOfDay(
                            hour: selectedHour,
                            minute: selectedMinute,
                          );
                          Navigator.of(sheetContext).pop(time);
                        },
                        child: const Text('Kaydet'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        _firstReminderTime = result;
      });
    }
  }

  void _onAddReminder() async {
    // 🔹 Önce exact alarm izni iste (Android 13+ zorunlu)
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      final granted = await androidPlugin.requestExactAlarmsPermission();
      if (granted != true) {
        _showSnackBar('Lütfen bildirimler için tam zamanlama izni ver.');
        return;
      }
    }

    // 🔹 Önce klavyeyi kapat
    FocusScope.of(context).unfocus();

    final name = _nameController.text.trim();
    final dose = _doseController.text.trim();
    final timesPerDay =
        int.tryParse(_timesPerDayController.text.trim());
    final days = int.tryParse(_daysController.text.trim());
    final intervalDays =
        int.tryParse(_intervalDaysController.text.trim());

    if (name.isEmpty) {
      _showSnackBar('Lütfen ilaç adını gir.');
      return;
    }
    if (timesPerDay == null || timesPerDay <= 0) {
      _showSnackBar('Günde kaç kez kullanacağını doğru gir.');
      return;
    }
    if (timesPerDay > 4) {
      _showSnackBar(
          'Şu an en fazla günde 4 kez için hatırlatma destekleniyor.');
      return;
    }
    if (days == null || days <= 0) {
      _showSnackBar('Kaç gün kullanacağını doğru gir.');
      return;
    }
    if (intervalDays == null || intervalDays <= 0) {
      _showSnackBar('Kaç günde bir kullanacağını doğru gir.');
      return;
    }

    final reminder = MedicineReminder(
      name: name,
      dose: dose.isEmpty ? null : dose,
      mealTiming: _mealTiming,
      timesPerDay: timesPerDay,
      totalDays: days,
      intervalDays: intervalDays,
      startDate: _startDate,
      firstReminderHour: _firstReminderTime.hour,
      firstReminderMinute: _firstReminderTime.minute,
      notificationIds: [],
    );

    // Bildirimleri planla ve ID'leri modele ekle
    await _scheduleNotificationsFor(reminder);

    setState(() {
      _reminders.add(reminder);
      _nameController.clear();
      _doseController.clear();
      _timesPerDayController.text = '2';
      _daysController.text = '5';
      _intervalDaysController.text = '1';
      _mealTiming = 'Tok';
      _startDate = DateTime.now();
      _firstReminderTime = const TimeOfDay(hour: 9, minute: 0);
    });

    await _saveRemindersToStorage();

    // 🔥 Analytics: Hatırlatma logu
    await AnalyticsHelper.logMedicineReminderCreated(
      barcode: reminder.name,
      name: reminder.name,
      timesPerDay: reminder.timesPerDay,
      days: reminder.totalDays,
    );

    _showSnackBar(
      'İlaç hatırlatması kaydedildi ve bildirimler oluşturuldu.',
    );
  }

  void _onDeleteReminder(int index) async {
    final reminder = _reminders[index];

    // 🔥 Tüm planlı bildirimleri iptal et
    for (final id in reminder.notificationIds) {
      await _notifications.cancel(id);
    }

    setState(() {
      _reminders.removeAt(index);
    });

    await _saveRemindersToStorage();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year;
    return '$d.$m.$y';
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('İlaç Hatırlatma'),
      ),
      body: SafeArea(
        // 🔹 Boş bir yere dokununca klavyeyi kapatmak için GestureDetector
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              // FORM
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                      TextField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'İlaç adı',
                          hintText: 'Örn: Parol 500 mg',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _doseController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Doz / Açıklama (opsiyonel)',
                          hintText: 'Örn: 1 tablet',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _mealTiming,
                              decoration: const InputDecoration(
                                labelText: 'Aç/Tok',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Aç',
                                  child: Text('Aç'),
                                ),
                                DropdownMenuItem(
                                  value: 'Tok',
                                  child: Text('Tok'),
                                ),
                                DropdownMenuItem(
                                  value: 'Fark etmez',
                                  child: Text('Fark etmez'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _mealTiming = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _timesPerDayController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Günde kaç kez?',
                                hintText: 'Örn: 2',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _daysController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Kaç gün?',
                                hintText: 'Örn: 5',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _intervalDaysController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Kaç günde bir?',
                                hintText: 'Örn: 2',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _pickStartDate,
                              borderRadius: BorderRadius.circular(14),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Başlangıç tarihi',
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDate(_startDate)),
                                    const Icon(Icons.calendar_today, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: _showTimePickerSheet,
                              borderRadius: BorderRadius.circular(14),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'İlk hatırlatma saati',
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                        _formatTimeOfDay(_firstReminderTime)),
                                    const Icon(Icons.access_time, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _onAddReminder,
                          icon: const Icon(Icons.add_alert),
                          label: const Text('Hatırlatma Ekle'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // LİSTE
              Expanded(
                child: _reminders.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text(
                            'Kullandığın ilaçları buraya ekleyerek,\n'
                            'kullanım süresi boyunca takibini kolaylaştırabilirsin.\n\n'
                            'Eklediğin ilaçlar için otomatik bildirimler kurulacak,\n'
                            'süresi biten hatırlatmalar ise otomatik silinecek.',
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
                        itemCount: _reminders.length,
                        itemBuilder: (context, index) {
                          final r = _reminders[index];
                          final endDate = r.startDate
                              .add(Duration(days: r.totalDays));
                          return Card(
                            margin:
                                const EdgeInsets.symmetric(vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          r.name,
                                          style: theme
                                              .textTheme.titleMedium
                                              ?.copyWith(
                                            fontWeight:
                                                FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                        ),
                                        onPressed: () =>
                                            _onDeleteReminder(index),
                                        tooltip: 'Sil',
                                      ),
                                    ],
                                  ),
                                  if (r.dose != null &&
                                      r.dose!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      r.dose!,
                                      style:
                                          theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.schedule,
                                          size: 18),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Günde ${r.timesPerDay} kez • ${r.totalDays} gün • ${r.intervalDays} günde bir',
                                        style: theme
                                            .textTheme.bodySmall
                                            ?.copyWith(
                                          color:
                                              Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.restaurant,
                                          size: 18),
                                      const SizedBox(width: 4),
                                      Text(
                                        r.mealTiming,
                                        style: theme
                                            .textTheme.bodySmall
                                            ?.copyWith(
                                          color:
                                              Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Başlangıç: ${_formatDate(r.startDate)}'
                                        '  •  Bitiş: ${_formatDate(endDate)}',
                                        style: theme
                                            .textTheme.bodySmall
                                            ?.copyWith(
                                          color:
                                              Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time,
                                          size: 18),
                                      const SizedBox(width: 4),
                                      Text(
                                        'İlk bildirim: ${_formatTimeOfDay(
                                          TimeOfDay(
                                            hour: r.firstReminderHour,
                                            minute:
                                                r.firstReminderMinute,
                                          ),
                                        )}',
                                        style: theme
                                            .textTheme.bodySmall
                                            ?.copyWith(
                                          color:
                                              Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
