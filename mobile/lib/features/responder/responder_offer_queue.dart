import '../../core/models/dispatch_models.dart';

class ResponderOfferQueue {
  static const _priorityRank = {'High': 0, 'Medium': 1, 'Low': 2};

  static List<Offer> openOffers(Iterable<Offer> offers, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final result = offers
        .where((offer) => offer.isOpen && offer.secondsLeft(current) > 0)
        .toList();
    result.sort((a, b) {
      final priority = (_priorityRank[a.priority] ?? 3).compareTo(
        _priorityRank[b.priority] ?? 3,
      );
      if (priority != 0) return priority;
      return (a.expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        b.expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    return result;
  }

  static List<Offer> earlierToday(Iterable<Offer> offers, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final result = offers.where((offer) {
      final created = offer.createdAt?.toLocal();
      return offer.isFinished &&
          created != null &&
          created.year == current.year &&
          created.month == current.month &&
          created.day == current.day;
    }).toList();
    result.sort(
      (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
    return result;
  }
}
