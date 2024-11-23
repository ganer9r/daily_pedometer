import 'package:daily_pedometer/helper.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/standalone.dart';

class StepData {
  final String? previousDate;
  final int previousStepCount;
  final String? todayDate;
  final int todayStepCount;
  final int? bootCount;
  final List<int> stack;

  StepData.fromJson(Map<String, dynamic> json)
      : previousDate = json['previousDate'],
        previousStepCount = json['previousStepCount'] ?? 0,
        todayDate = json['todayDate'],
        todayStepCount = json['todayStepCount'] ?? 0,
        bootCount = json['bootCount'],
        stack = json['stack']?.cast<int>() ?? [];

  StepData.empty()
      : previousDate = null,
        previousStepCount = 0,
        todayDate = null,
        todayStepCount = 0,
        bootCount = null,
        stack = [];

  StepData(this.previousDate, this.previousStepCount, this.todayDate,
      this.todayStepCount, this.bootCount, this.stack);

  StepData.initialData(StepCountWithTimestamp stepCount)
      : previousDate =
            formatDate(stepCount.timeStamp.subtract(const Duration(days: 1))),
        previousStepCount = stepCount.stepsFromBoot,
        todayDate = formatDate(stepCount.timeStamp),
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = [];

  // 날짜가 달라진 경우
  StepData.shiftDate(StepData stepData, StepCountWithTimestamp stepCount)
      : previousDate = stepData.todayDate,
        // 오늘 날짜와 같지 않으면, 날짜가 변경되었기 때문에, 다음날로 이동
        // 날짜가 변경 되었는데, 기존에 저장된 걸음수가 현재 걸음수보다 높거나
        // 부팅 카운트가 다르면 새로 부팅이 된 상태라서,
        // 기본 비교값을 0 으로 세팅함!
        previousStepCount =
            (stepData.todayStepCount > stepCount.stepsFromBoot ||
                    (stepData.bootCount != stepCount.bootCount &&
                        stepData.bootCount != null))
                ? 0
                : stepData.todayStepCount,
        todayDate = formatDate(stepCount.timeStamp),
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = [];

  // 부팅이 새로 된 경우
  StepData.newBoot(StepData stepData, StepCountWithTimestamp stepCount)
      : previousDate = stepData.previousDate,
        previousStepCount = stepData.previousStepCount,
        todayDate = stepData.todayDate,
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = [...stepData.stack, stepData.todayStepCount];

  // 일반적인 상황에서 걸음 수 누적
  StepData.accumulate(StepData stepData, StepCountWithTimestamp stepCount)
      : previousDate = stepData.previousDate,
        previousStepCount = stepData.previousStepCount,
        todayDate = stepData.todayDate,
        todayStepCount = stepCount.stepsFromBoot,
        bootCount = stepCount.bootCount,
        stack = stepData.stack;

  Map<String, dynamic> toJson() => {
        'previousDate': previousDate,
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
    else if ((bootCount != stepCount.bootCount && bootCount != null) ||
        stepCount.stepsFromBoot < todayStepCount) {
      return StepData.newBoot(this, stepCount);
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
          listEquals(stack, other.stack);

  @override
  String toString() {
    return 'StepData{previousDate: $previousDate, previousStepCount: $previousStepCount, todayDate: $todayDate, todayStepCount: $todayStepCount, bootCount: $bootCount, stack: $stack}';
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
