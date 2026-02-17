import '../data/local/local_event_store.dart';
import '../models/calendar_event.dart';
import 'notification_event_source.dart';

class LocalEventNotificationSource implements NotificationEventSource {
  LocalEventNotificationSource(this._localStore);

  final LocalEventStore _localStore;

  @override
  Future<List<CalendarEvent>> getEventsBetween(
    DateTime startUtc,
    DateTime endUtc,
  ) {
    return _localStore.getEventsBetween(startUtc, endUtc);
  }

  @override
  Stream<void> onEventsChanged() {
    return _localStore.onEventsChanged();
  }
}
