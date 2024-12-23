import 'package:daily_pedometer/helper.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/standalone.dart';

class StepData {
  static Location? _location;
  static set location(Location? location) {
    _location = location;
  }

  final String? previousDate;
  final int previousStepCount;
  final String? todayDate;
  final int todayStepCount;
  final int? bootCount; // bootCount가 지멋대로 올라가는 경우가 있어, 당장은 활용하지 않는다.
  final List<int> stack;
  final String? lastSavedAt;
  final String? previousStepCountSavedAt;

  StepData.fromJson(Map<String, dynamic> json)
      : previousDate = json['previousDate'],
        previousStepCount = json['previousStepCount'] ?? 0,
        todayDate = json['todayDate'],
        todayStepCount = json['todayStepCount'] ?? 0,
        bootCount = json['bootCount'],
        stack = json['stack']?.cast<int>() ?? [],
        lastSavedAt = json['tzLastSavedAt'],
        previousStepCountSavedAt = json['tzPreviousStepCountSavedAt'];

  StepData.empty()
      : previousDate = null,
        previousStepCount = 0,
        todayDate = null,
        todayStepCount = 0,
        bootCount = null,
        stack = [],
        lastSavedAt = null,
        previousStepCountSavedAt = null;

  StepData(
      this.previousDate,
      this.previousStepCount,
      this.todayDate,
      this.todayStepCount,
      this.bootCount,
      this.stack,
      this.lastSavedAt,
      this.previousStepCountSavedAt);

  StepData.initialData(StepCountWithTimestamp stepCount)
      : previousDate =
            formatDate(stepCount.timeStamp.subtract(const Duration(days: 1))),
        previousStepCount = stepCount.stepsFromBoot,
        todayDate = formatDate(stepCount.timeStamp),
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = [],
        lastSavedAt = stepCount.timeStamp.toIso8601String(),
        previousStepCountSavedAt = null;

  // 날짜가 달라진 경우
  StepData.shiftDate(StepData stepData, StepCountWithTimestamp stepCount)
      : previousDate = stepData.todayDate,
        // 오늘 날짜와 같지 않으면, 날짜가 변경되었기 때문에, 다음날로 이동
        // 날짜가 변경 되었는데, 기존에 저장된 걸음수가 현재 걸음수보다 높거나
        // 부팅 카운트가 다르면 새로 부팅이 된 상태라서,
        // 기본 비교값을 0 으로 세팅함!
        previousStepCount = (stepData.todayStepCount > stepCount.stepsFromBoot)
            ? 0
            : stepData.todayStepCount,
        todayDate = formatDate(stepCount.timeStamp),
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = [],
        lastSavedAt = stepCount.timeStamp.toIso8601String(),
        previousStepCountSavedAt = stepData.lastSavedAt;

  // 부팅이 새로 된 경우
  StepData.newBoot(StepData stepData, StepCountWithTimestamp stepCount)
      : previousDate = stepData.previousDate,
        previousStepCount = stepData.previousStepCount,
        todayDate = stepData.todayDate,
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = [...stepData.stack, stepData.todayStepCount],
        lastSavedAt = stepCount.timeStamp.toIso8601String(),
        previousStepCountSavedAt = stepData.previousStepCountSavedAt;

  // 일반적인 상황에서 걸음 수 누적
  StepData.accumulate(StepData stepData, StepCountWithTimestamp stepCount)
      : previousDate = stepData.previousDate,
        previousStepCount = stepData.previousStepCount,
        todayDate = stepData.todayDate,
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = stepData.stack,
        lastSavedAt = stepCount.timeStamp.toIso8601String(),
        previousStepCountSavedAt = stepData.previousStepCountSavedAt;

  Map<String, dynamic> toJson() => {
        'previousDate': previousDate,
        'previousStepCount': previousStepCount,
        'todayDate': todayDate,
        'todayStepCount': todayStepCount,
        'bootCount': bootCount,
        'stack': stack,
        'tzLastSavedAt': lastSavedAt,
        'tzPreviousStepCountSavedAt': previousStepCountSavedAt,
      };

  StepData update(StepCountWithTimestamp stepCount) {
    // 오래된 stepCount는 무시한다.
    if (lastSavedAt != null && _location != null) {
      final dt = TZDateTime.parse(_location!, lastSavedAt!);
      if (stepCount.timeStamp.isBefore(dt)) {
        return this;
      }
    }
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
    // 가끔 센서값이 섞여서 들어오는 경우가 있어, 5보 정도의 오차는 무시한다.
    else if (stepCount.stepsFromBoot < todayStepCount - 5) {
      return StepData.newBoot(this, stepCount);
    } else if (stepCount.stepsFromBoot < todayStepCount) {
      return this;
    }

    return StepData.accumulate(this, stepCount);
  }

  int getDailySteps(TZDateTime now) {
    if (formatDate(now) != todayDate) {
      return 0;
    }
    final accStepCount = todayStepCount + stack.fold(0, (a, b) => a + b) as int;
    return accStepCount - previousStepCount;
  }

  @override
  int get hashCode => Object.hash(previousDate, previousStepCount, todayDate,
      todayStepCount, bootCount, Object.hashAll(stack));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepData &&
          runtimeType == other.runtimeType &&
          previousDate == other.previousDate &&
          previousStepCount == other.previousStepCount &&
          todayDate == other.todayDate &&
          todayStepCount == other.todayStepCount &&
          bootCount == other.bootCount &&
          lastSavedAt == other.lastSavedAt &&
          previousStepCountSavedAt == other.previousStepCountSavedAt &&
          listEquals(stack, other.stack);

  @override
  String toString() {
    return 'StepData${toJson()}';
  }
}

class StepCountWithTimestamp {
  final TZDateTime timeStamp;
  final int stepsFromBoot;
  final int bootCount;

  StepCountWithTimestamp(this.stepsFromBoot, this.bootCount, this.timeStamp);

  @override
  String toString() =>
      'Steps taken: $stepsFromBoot at ${timeStamp.toIso8601String()}';
}
