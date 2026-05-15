import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
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

  Future<bool> upsertHistory(History history) {
    return Future.value(false);
  }

  Future<bool> deleteHistory(String id, ComicType type) {
    return Future.value(false);
  }

  Future<bool> clearHistory() {
    return Future.value(false);
  }

  Future<bool> clearUnfavoritedHistory() {
    return Future.value(false);
  }

  Future<List<ServerFavoriteFolder>?> listFavoriteFolders() {
    return Future.value(null);
  }

  Future<ServerFavoritePage?> listFavoriteItems(
    String folder, {
    int limit = 100,
    int offset = 0,
  }) {
    return Future.value(null);
  }

  Future<List<String>?> findFavoriteFolders(String id, ComicType type) {
    return Future.value(null);
  }

  Future<FavoriteItem?> getFavoriteItem(
    String folder,
    String id,
    ComicType type,
  ) {
    return Future.value(null);
  }
}

class ServerFavoriteFolder {
  const ServerFavoriteFolder({
    required this.name,
    required this.count,
    required this.order,
    this.sourceKey,
    this.sourceFolder,
  });

  final String name;
  final int count;
  final int order;
  final String? sourceKey;
  final String? sourceFolder;
}

class ServerFavoritePage {
  const ServerFavoritePage({required this.items, required this.total});

  final List<FavoriteItem> items;
  final int total;
}
