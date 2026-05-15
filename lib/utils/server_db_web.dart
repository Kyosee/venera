import 'package:dio/dio.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';

class ServerHistoryPage {
  const ServerHistoryPage({required this.items, required this.total});

  final List<History> items;
  final int total;
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

class ServerDbClient {
  const ServerDbClient();

  String get _profile {
    final value = appdata.settings['webServerDbProfile']?.toString().trim();
    return value == null || value.isEmpty ? 'default' : value;
  }

  Dio _dio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
  }

  Future<ServerHistoryPage?> listHistory({
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final response = await _dio().post(
        '/api/server-db/history/list',
        data: {'profile': _profile, 'limit': limit, 'offset': offset},
      );
      final data = response.data;
      if (data is! Map || data['ok'] != true) {
        return null;
      }
      final rawItems = data['items'];
      final items = rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((item) => History.fromMap(item.cast<String, dynamic>()))
                .toList()
          : <History>[];
      final total = data['total'];
      return ServerHistoryPage(
        items: items,
        total: total is num ? total.toInt() : items.length,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Map<String, dynamic> _historyPayload(History history) {
    return {
      'id': history.id,
      'title': history.title,
      'subtitle': history.subtitle,
      'cover': history.cover,
      'time': history.time.millisecondsSinceEpoch,
      'type': history.type.value,
      'ep': history.ep,
      'page': history.page,
      'readEpisode': history.readEpisode.toList(),
      'max_page': history.maxPage,
      'chapter_group': history.group,
    };
  }

  Future<bool> upsertHistory(History history) async {
    final response = await _dio().post(
      '/api/server-db/history/upsert',
      data: {'profile': _profile, 'history': _historyPayload(history)},
    );
    final data = response.data;
    return data is Map && data['ok'] == true;
  }

  Future<bool> deleteHistory(String id, ComicType type) async {
    final response = await _dio().post(
      '/api/server-db/history/delete',
      data: {'profile': _profile, 'id': id, 'type': type.value},
    );
    final data = response.data;
    return data is Map && data['ok'] == true;
  }

  Future<bool> clearHistory() async {
    final response = await _dio().post(
      '/api/server-db/history/clear',
      data: {'profile': _profile},
    );
    final data = response.data;
    return data is Map && data['ok'] == true;
  }

  Future<bool> clearUnfavoritedHistory() async {
    final response = await _dio().post(
      '/api/server-db/history/clear-unfavorited',
      data: {'profile': _profile},
    );
    final data = response.data;
    return data is Map && data['ok'] == true;
  }

  FavoriteItem _favoriteItemFromMap(Map<String, dynamic> item) {
    final favorite = FavoriteItem.fromJson({
      'id': item['id'],
      'name': item['name'],
      'author': item['author'],
      'type': item['type'],
      'tags': item['tags'],
      'coverPath': item['coverPath'],
    });
    final time = item['time']?.toString();
    if (time != null && time.isNotEmpty) {
      favorite.time = time;
    }
    return favorite;
  }

  Future<List<ServerFavoriteFolder>?> listFavoriteFolders() async {
    try {
      final response = await _dio().post(
        '/api/server-db/favorites/folders',
        data: {'profile': _profile},
      );
      final data = response.data;
      if (data is! Map || data['ok'] != true) {
        return null;
      }
      final folders = data['folders'];
      if (folders is! List) {
        return <ServerFavoriteFolder>[];
      }
      return folders.whereType<Map>().map((folder) {
        final item = folder.cast<String, dynamic>();
        return ServerFavoriteFolder(
          name: item['name']?.toString() ?? '',
          count: item['count'] is num ? (item['count'] as num).toInt() : 0,
          order: item['order'] is num ? (item['order'] as num).toInt() : 0,
          sourceKey: item['sourceKey']?.toString(),
          sourceFolder: item['sourceFolder']?.toString(),
        );
      }).where((folder) => folder.name.isNotEmpty).toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<ServerFavoritePage?> listFavoriteItems(
    String folder, {
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final response = await _dio().post(
        '/api/server-db/favorites/list',
        data: {
          'profile': _profile,
          'folder': folder,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = response.data;
      if (data is! Map || data['ok'] != true) {
        return null;
      }
      final rawItems = data['items'];
      final items = rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((item) => _favoriteItemFromMap(item.cast<String, dynamic>()))
                .toList()
          : <FavoriteItem>[];
      final total = data['total'];
      return ServerFavoritePage(
        items: items,
        total: total is num ? total.toInt() : items.length,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<List<String>?> findFavoriteFolders(String id, ComicType type) async {
    try {
      final response = await _dio().post(
        '/api/server-db/favorites/find',
        data: {'profile': _profile, 'id': id, 'type': type.value},
      );
      final data = response.data;
      if (data is! Map || data['ok'] != true) {
        return null;
      }
      final folders = data['folders'];
      return folders is List
          ? folders.map((item) => item.toString()).toList()
          : <String>[];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<FavoriteItem?> getFavoriteItem(
    String folder,
    String id,
    ComicType type,
  ) async {
    try {
      final response = await _dio().post(
        '/api/server-db/favorites/get',
        data: {
          'profile': _profile,
          'folder': folder,
          'id': id,
          'type': type.value,
        },
      );
      final data = response.data;
      if (data is! Map || data['ok'] != true || data['item'] is! Map) {
        return null;
      }
      return _favoriteItemFromMap(
        (data['item'] as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }
}
