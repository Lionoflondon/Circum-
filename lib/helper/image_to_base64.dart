import 'dart:convert';
import 'dart:io';

Future<String> imageFileToBase64(File file) async {
  // Read the file as bytes
  List<int> imageBytes = await file.readAsBytes();

  // Encode the bytes to base64 string
  String base64String = base64Encode(imageBytes);

  return base64String;
}
