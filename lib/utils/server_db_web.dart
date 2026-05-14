import 'package:dio/dio.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/history.dart';

class ServerHistoryPage {
  const ServerHistoryPage({required this.items, required this.total});

  final List<History> items;
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
}
