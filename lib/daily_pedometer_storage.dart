import 'dart:async';
import 'dart:convert';

import 'package:daily_pedometer/daily_pedometer.dart';
import 'package:daily_pedometer/daily_pedometer_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyPedometerStorage {
  static const storageKey = 'STEPS';

  DateTime? _lastSaveTime;
  Future<void> save(StepData data) async {
    _lastSaveTime = DateTime.now();
    SharedPreferences preferences = await SharedPreferences.getInstance();
    final json = jsonEncode(data.toJson());
    print("DailyPedometerStorage save : $json");
    await preferences.setString(storageKey, json);
  }

  static const _debounceDuration = Duration(seconds: 2);
  static const _maxDeboundDuration = Duration(minutes: 5);
  Timer? _debounceTimer;

  Future<void> debouncedSave(StepData data) async {
    final now = DateTime.now();
    // 마지막 저장이 오래되었거나,
    // 데이터의 날짜가 달라졌다면, 타이머 캔슬하고 바로 저장한다.
    if (_lastSaveTime == null ||
        _lastSaveTime!.isBefore(now.subtract(_maxDeboundDuration)) ||
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

  DateTime? _lastReloadTime;
  static const _reloadDuration = Duration(minutes: 10);
  reload() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.reload();
  }

  bool needReload() {
    if (_lastReloadTime == null) {
      return true;
    }

    final now = DateTime.now();

    // 마지막 리로드가 오래되었다면, 리로드 필요.
    if (_lastReloadTime!.isBefore(now.subtract(_reloadDuration))) {
      return true;
    }

    // 날짜가 달라졌다면, 리로드 필요.
    if (formatDate(now) != formatDate(_lastReloadTime!)) {
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

class StepData {
  final String? previouseDate;
  final int previousStepCount;
  final String? todayDate;
  final int todayStepCount;
  final int? bootCount;
  final List<int> stack;

  StepData.fromJson(Map<String, dynamic> json)
      : previouseDate = json['previousDate'],
        previousStepCount = json['previousStepCount'] ?? 0,
        todayDate = json['todayDate'],
        todayStepCount = json['todayStepCount'] ?? 0,
        bootCount = json['bootCount'],
        stack = json['stack']?.cast<int>() ?? [];

  StepData.empty()
      : previouseDate = null,
        previousStepCount = 0,
        todayDate = null,
        todayStepCount = 0,
        bootCount = null,
        stack = [];

  StepData.initialData(StepCountWithTimestamp stepCount)
      : previouseDate =
            formatDate(stepCount.timeStamp.subtract(const Duration(days: 1))),
        previousStepCount = stepCount.stepsFromBoot,
        todayDate = formatDate(stepCount.timeStamp),
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = [];

  // 날짜가 달라진 경우
  StepData.shiftDate(StepData stepData, StepCountWithTimestamp stepCount)
      : previouseDate = stepData.todayDate,
        // 오늘 날짜와 같지 않으면, 날짜가 변경되었기 때문에, 다음날로 이동
        // 날짜가 변경 되었는데, 기존에 저장된 걸음수가 현재 걸음수보다 높거나
        // 부팅 카운트가 다르면 새로 부팅이 된 상태라서,
        // 기본 비교값을 0 으로 세팅함!
        previousStepCount =
            (stepData.todayStepCount > stepCount.stepsFromBoot ||
                    stepData.bootCount != stepCount.bootCount)
                ? 0
                : stepData.todayStepCount,
        todayDate = formatDate(stepCount.timeStamp),
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = [];

  // 부팅이 새로 된 경우
  StepData.newBoot(StepData stepData, StepCountWithTimestamp stepCount)
      : previouseDate = stepData.previouseDate,
        previousStepCount = stepData.previousStepCount,
        todayDate = stepData.todayDate,
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = [...stepData.stack, stepData.todayStepCount];

  // 일반적인 상황에서 걸음 수 누적
  StepData.accumulate(StepData stepData, StepCountWithTimestamp stepCount)
      : previouseDate = stepData.previouseDate,
        previousStepCount = stepData.previousStepCount,
        todayDate = stepData.todayDate,
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = stepData.stack;

  Map<String, dynamic> toJson() => {
        'previousDate': previouseDate,
        'previousStepCount': previousStepCount,
        'todayDate': todayDate,
        'todayStepCount': todayStepCount,
        'bootCount': bootCount,
        'stack': stack,
      };

  StepData update(StepCountWithTimestamp stepCount) {
    // 오늘에 대한 정보가 없다면, 앱 설치등 초기 상태이므로
    // 걸음을 초기 상태부터 시작한다.
    if (todayDate == null) {
      return StepData.initialData(stepCount);
    }
    // 오늘 날짜와 같지 않으면, 날짜가 변경되었기 대문에 이전 날짜로 옮김
    // 날짜가 변경 되었는데, 기존에 저장된 걸음수가 현재 걸음수보다 높으면 부팅이 된 상태라서,
    // 기본 비교값을 0 으로 세팅함!
    else if (todayDate != formatDate(stepCount.timeStamp)) {
      return StepData.shiftDate(this, stepCount);
    }
    // 부팅이 새로 되었다면, 기존 걸음수를 stack에 저장하고,
    // 0부터 다시 시작한다.
    else if (bootCount != stepCount.bootCount ||
        stepCount.stepsFromBoot < todayStepCount) {
      return StepData.newBoot(this, stepCount);
    }

    return StepData.accumulate(this, stepCount);
  }

  int getDailySteps() {
    final now = DateTime.now();
    if (formatDate(now) != todayDate) {
      return 0;
    }
    final accStepCount = todayStepCount + stack.fold(0, (a, b) => a + b) as int;
    return accStepCount - previousStepCount;
  }

  @override
  int get hashCode => Object.hash(previouseDate, previousStepCount, todayDate,
      todayStepCount, bootCount, Object.hashAll(stack));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepData &&
          runtimeType == other.runtimeType &&
          previouseDate == other.previouseDate &&
          previousStepCount == other.previousStepCount &&
          todayDate == other.todayDate &&
          todayStepCount == other.todayStepCount &&
          bootCount == other.bootCount &&
          listEquals(stack, other.stack);

  bool isExpired(DateTime now) {
    return todayDate != formatDate(now);
  }
}
