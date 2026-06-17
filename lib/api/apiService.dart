import 'dart:io';
import 'package:dio/dio.dart';

class ApiService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  // 이미지와 메타데이터를 함께 업로드하는 함수
  Future<Map<String, dynamic>?> uploadImage({
    required File imageFile,
    required double focalLength,
    required double distance,
  }) async {
    try {
      String fileName = imageFile.path.split('/').last;

      FormData formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          imageFile.path,
          filename: fileName,
        ),
        'focalLength': focalLength,
        'distance': distance,
      });

      final response = await _dio.post(
        'http://172.16.100.73:8080/analyze',
        data: formData,
      );

      return response.data as Map<String, dynamic>?;
    } on DioException catch (e) {
      print('Dio 에러 발생: ${e.message}');
      if (e.response != null) {
        print('서버 응답 에러: ${e.response?.data}');
      }
      return null;
    } catch (e) {
      print('알 수 없는 에러 발생: $e');
      return null;
    }
  }
}
