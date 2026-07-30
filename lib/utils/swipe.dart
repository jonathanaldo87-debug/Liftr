library;

const double kFlingVelocity = 200;
const double kDragDistance = 40;
const double kSnapFraction = 0.22;

int? carouselSnap({
  required double velocity,
  required double offset,
  required double width,
  double snapFraction = kSnapFraction,
  double flingVelocity = kFlingVelocity,
}) {
  if (width <= 0) return null;

  final flung = velocity.abs() >= flingVelocity;
  final pulled = offset.abs() >= width * snapFraction;
  if (!flung && !pulled) return null;

  return (flung ? velocity : offset) < 0 ? 1 : -1;
}

int? swipeDirection({
  required double velocity,
  required double delta,
  double flingVelocity = kFlingVelocity,
  double dragDistance = kDragDistance,
}) {
  final flung = velocity.abs() >= flingVelocity;
  final dragged = delta.abs() >= dragDistance;
  if (!flung && !dragged) return null;

  return (flung ? velocity : delta) < 0 ? -1 : 1;
}
