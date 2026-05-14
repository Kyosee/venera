import 'package:venera/foundation/history.dart';

class ServerHistoryPage {
  const ServerHistoryPage({required this.items, required this.total});

  final List<History> items;
  final int total;
}

class ServerDbClient {
  const ServerDbClient();

  Future<ServerHistoryPage?> listHistory({int limit = 100, int offset = 0}) {
    return Future.value(null);
  }
}
