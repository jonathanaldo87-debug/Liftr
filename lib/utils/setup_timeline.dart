class SetupStamp {
  final DateTime date;

  final String? setupId;

  SetupStamp(DateTime date, this.setupId) : date = dayOnly(date);

  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

class SetupTimeline {
  final List<SetupStamp> stamps;

  const SetupTimeline._(this.stamps);

  const SetupTimeline.empty() : stamps = const [];

  factory SetupTimeline(Iterable<SetupStamp> stamps) {
    final sorted = stamps.toList()..sort((a, b) => a.date.compareTo(b.date));
    return SetupTimeline._(sorted);
  }

  bool get isEmpty => stamps.isEmpty;

  String? effectiveOn(DateTime date) {
    final day = SetupStamp.dayOnly(date);

    String? carried;
    for (final stamp in stamps) {
      if (stamp.date.isAfter(day)) break;
      if (stamp.setupId != null) carried = stamp.setupId;
    }
    return carried;
  }

  SetupTimeline withPick(DateTime date, String? setupId) {
    final day = SetupStamp.dayOnly(date);

    return SetupTimeline([
      for (final stamp in stamps)
        if (stamp.date != day) stamp,
      if (setupId != null) SetupStamp(day, setupId),
    ]);
  }
}

class SetupScope {
  final SetupTimeline timeline;

  final String? setupId;

  const SetupScope(this.timeline, this.setupId);

  bool includes(DateTime sessionDate) =>
      timeline.effectiveOn(sessionDate) == setupId;
}
