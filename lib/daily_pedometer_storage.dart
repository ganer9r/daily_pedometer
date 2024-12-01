import 'dart:async';
import 'dart:convert';

import 'package:daily_pedometer/helper.dart';
import 'package:daily_pedometer/value_objects.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/standalone.dart';

class DailyPedometerStorage {
  static const storageKey = 'STEPS';

  final Location _timezone;

  DailyPedometerStorage(this._timezone);

  TZDateTime? _lastSaveTime;
  Future<void> save(StepData data) async {
    _lastSaveTime = TZDateTime.now(_timezone);
    SharedPreferences preferences = await SharedPreferences.getInstance();
    final json = jsonEncode(data.toJson());
    print("DailyPedometerStorage save : $json");
    await preferences.setString(storageKey, json);
  }

  static const _debounceDuration = Duration(seconds: 2);
  static const _maxDeboundDuration = Duration(minutes: 5);
  Timer? _debounceTimer;

  Future<void> debouncedSave(StepData data) async {
    final now = TZDateTime.now(_timezone);
    final nextMidnight = now.add(const Duration(days: 1)).subtract(Duration(
        hours: now.hour,
        minutes: now.minute,
        seconds: now.second,
        milliseconds: now.millisecond,
        microseconds: now.microsecond));

    // 마지막 저장이 오래되었거나,
    // 날짜가 바뀌기 직전이거나,
    // 데이터의 날짜가 달라졌다면, 타이머 캔슬하고 바로 저장한다.
    if (_lastSaveTime == null ||
        _lastSaveTime!.isBefore(now.subtract(_maxDeboundDuration)) ||
        (nextMidnight.difference(now).inMilliseconds < 1000 &&
            now.difference(_lastSaveTime!).inMilliseconds > 1000) ||
        data.todayDate != formatDate(_lastSaveTime!)) {
      await save(data);
      _debounceTimer?.cancel();
      _debounceTimer = null;
      return;
    }

    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
      _debounceTimer = null;
    }

    _debounceTimer = Timer(_debounceDuration, () async {
      await save(data);
    });
  }

  TZDateTime? _lastReloadTime;
  static const _reloadDuration = Duration(minutes: 10);
  reload() async {
    _lastReloadTime = TZDateTime.now(_timezone);
    SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.reload();
  }

  bool needReload() {
    if (_lastReloadTime == null) {
      return true;
    }

    final now = TZDateTime.now(_timezone);

    // 마지막 리로드가 오래되었다면, 리로드 필요.
    if (_lastReloadTime!.isBefore(now.subtract(_reloadDuration))) {
      return true;
    }

    // 날짜가 달라졌다면, 리로드 필요.
    if (formatDate(now) != formatDate(_lastReloadTime!)) {
      return true;
    }

    // 날짜가 바뀌기 직전이라면, 리로드 필요.
    final nextMidnight = now.add(const Duration(days: 1)).subtract(Duration(
        hours: now.hour,
        minutes: now.minute,
        seconds: now.second,
        milliseconds: now.millisecond,
        microseconds: now.microsecond));
    if (nextMidnight.difference(now).inMilliseconds < 300 * 1000) {
      return true;
    }

    return false;
  }

  remove() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
  }

  Future<StepData> read() async {
    if (needReload()) {
      await reload();
    }
    SharedPreferences preferences = await SharedPreferences.getInstance();
    String? value = preferences.getString(storageKey);
    if (value == null) {
      return StepData.empty();
    } else {
      return StepData.fromJson(jsonDecode(value));
    }
  }
}
