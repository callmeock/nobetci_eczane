class MedicineReminder {
  final String name;
  final String? dose;
  final String mealTiming;
  final int timesPerDay;
  final int totalDays;
  final int intervalDays; // 🔥 kaç günde bir
  final DateTime startDate;
  final int firstReminderHour;
  final int firstReminderMinute;

  /// Bu hatırlatma için oluşturulan tüm notification ID'leri
  final List<int> notificationIds;

  MedicineReminder({
    required this.name,
    required this.mealTiming,
    required this.timesPerDay,
    required this.totalDays,
    required this.intervalDays,
    required this.startDate,
    required this.firstReminderHour,
    required this.firstReminderMinute,
    this.dose,
    List<int>? notificationIds,
  }) : notificationIds = notificationIds ?? [];

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dose': dose,
      'mealTiming': mealTiming,
      'timesPerDay': timesPerDay,
      'totalDays': totalDays,
      'intervalDays': intervalDays,
      'startDate': startDate.toIso8601String(),
      'firstReminderHour': firstReminderHour,
      'firstReminderMinute': firstReminderMinute,
      'notificationIds': notificationIds,
    };
  }

  factory MedicineReminder.fromJson(Map<String, dynamic> json) {
    return MedicineReminder(
      name: json['name'] as String,
      dose: json['dose'] as String?,
      mealTiming: json['mealTiming'] as String? ?? 'Tok',
      timesPerDay: json['timesPerDay'] as int? ?? 1,
      totalDays: json['totalDays'] as int? ?? 1,
      intervalDays: json['intervalDays'] as int? ?? 1,
      startDate: DateTime.parse(json['startDate'] as String),
      firstReminderHour: json['firstReminderHour'] as int? ?? 9,
      firstReminderMinute: json['firstReminderMinute'] as int? ?? 0,
      notificationIds: (json['notificationIds'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
    );
  }
}
