import 'package:dio/dio.dart';

Future<void> nativeInitRhttp() async {}

HttpClientAdapter createAppHttpClientAdapter({bool enableProxy = true}) =>
    Dio().httpClientAdapter;

HttpClientAdapter createRHttpAdapter({bool enableProxy = true}) =>
    Dio().httpClientAdapter;

HttpClientAdapter createIOAdapter({bool enableProxy = true}) =>
    Dio().httpClientAdapter;
