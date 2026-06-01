import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/read_later.dart';

class ServerHistoryPage {
  const ServerHistoryPage({required this.items, required this.total});

  final List<History> items;
  final int total;
}

class ServerImageFavoritePage {
  const ServerImageFavoritePage({required this.items, required this.total});

  final List<ImageFavoritesComic> items;
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

  Future<List<ReadLaterItem>?> listReadLater({int limit = 1000}) {
    return Future.value(null);
  }

  Future<bool> upsertReadLater(ReadLaterItem item) {
    return Future.value(false);
  }

  Future<bool> deleteReadLater(String id, ComicType type) {
    return Future.value(false);
  }

  Future<bool> clearReadLater() {
    return Future.value(false);
  }

  Future<bool> replaceImageFavorites(List<ImageFavoritesComic> comics) {
    return Future.value(false);
  }

  Future<ServerImageFavoritePage?> listImageFavorites({
    int limit = 500,
    int offset = 0,
  }) {
    return Future.value(null);
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

  Future<bool> createFavoriteFolder(
    String name, {
    bool renameWhenInvalidName = false,
  }) {
    return Future.value(false);
  }

  Future<bool> deleteFavoriteFolder(String name) {
    return Future.value(false);
  }

  Future<bool> renameFavoriteFolder(String before, String after) {
    return Future.value(false);
  }

  Future<bool> updateFavoriteFolderOrder(List<String> folders) {
    return Future.value(false);
  }

  Future<bool> linkFavoriteFolderToNetwork(
    String folder,
    String source,
    String networkFolder,
  ) {
    return Future.value(false);
  }

  Future<bool> addFavoriteItem(
    String folder,
    FavoriteItem item, {
    int? order,
    String? updateTime,
  }) {
    return Future.value(false);
  }

  Future<bool> deleteFavoriteItem(String folder, String id, ComicType type) {
    return Future.value(false);
  }

  Future<bool> batchDeleteFavoriteItems(
    String folder,
    List<FavoriteItem> items,
  ) {
    return Future.value(false);
  }

  Future<bool> reorderFavoriteItems(String folder, List<FavoriteItem> items) {
    return Future.value(false);
  }

  Future<bool> updateFavoriteTags(
    String folder,
    String id,
    ComicType? type,
    List<String> tags,
  ) {
    return Future.value(false);
  }

  Future<bool> updateFavoriteInfo(String folder, FavoriteItem item) {
    return Future.value(false);
  }

  Future<bool> moveFavoriteItem(
    String sourceFolder,
    String targetFolder,
    String id,
    ComicType type,
  ) {
    return Future.value(false);
  }

  Future<bool> batchMoveFavoriteItems(
    String sourceFolder,
    String targetFolder,
    List<FavoriteItem> items,
  ) {
    return Future.value(false);
  }

  Future<bool> batchCopyFavoriteItems(
    String sourceFolder,
    String targetFolder,
    List<FavoriteItem> items,
  ) {
    return Future.value(false);
  }

  Future<bool> batchDeleteFavoriteItemsInAllFolders(List<ComicID> items) {
    return Future.value(false);
  }

  Future<bool> updateFavoriteUpdateTime(
    String folder,
    String id,
    ComicType type,
    String updateTime,
    int lastCheckTime,
  ) {
    return Future.value(false);
  }

  Future<bool> updateFavoriteCheckTime(
    String folder,
    String id,
    ComicType type,
    int lastCheckTime,
  ) {
    return Future.value(false);
  }

  Future<bool> markFavoriteAsRead(String folder, String id, ComicType type) {
    return Future.value(false);
  }

  Future<bool> readFavorite(
    String id,
    ComicType type, {
    required String moveMode,
    String? followUpdatesFolder,
  }) {
    return Future.value(false);
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
