import 'package:flutter/foundation.dart';

/// App-wide "something on the map changed" signal (picked up a relay, dropped one, blocked someone).
/// The map listens and refreshes, so screens deep in a navigation stack don't need to thread results back.
class DataEvents extends ChangeNotifier {
  void changed() => notifyListeners();
}
