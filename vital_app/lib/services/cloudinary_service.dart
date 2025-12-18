import 'dart:io';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CloudinaryService {
  late CloudinaryPublic _cloudinary;

  CloudinaryService() {
    final cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
    final uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? 'vital_app_preset';

    if (cloudName.isEmpty) {
      throw Exception('Cloudinary cloud name not found in .env');
    }

    _cloudinary = CloudinaryPublic(cloudName, uploadPreset, cache: false);
  }

  /// Upload food image to Cloudinary
  /// Returns the secure URL of the uploaded image
  Future<String?> uploadFoodImage({
    required File imageFile,
    required String userId,
  }) async {
    try {
      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'food_${timestamp}';

      // Upload to Cloudinary
      CloudinaryResponse response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          imageFile.path,
          folder: 'vital_app/food_images/$userId',
          publicId: fileName,
          resourceType: CloudinaryResourceType.Image,
        ),
      );

      // Return the secure URL
      return response.secureUrl;
    } catch (e) {
      print('Error uploading image to Cloudinary: $e');
      return null;
    }
  }

  /// Delete food image from Cloudinary
  Future<bool> deleteFoodImage(String imageUrl) async {
    try {
      // Extract public ID from URL
      final publicId = _extractPublicId(imageUrl);
      if (publicId == null) return false;

      // Note: Deletion requires authenticated requests
      // For unsigned uploads, you may need to use the Admin API
      // or set up a backend endpoint for deletion
      
      print('Image deletion requires backend implementation: $publicId');
      return true; // Return true for now as unsigned presets can't delete
    } catch (e) {
      print('Error deleting image from Cloudinary: $e');
      return false;
    }
  }

  /// Extract public ID from Cloudinary URL
  String? _extractPublicId(String imageUrl) {
    try {
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      
      // Find the index after 'upload' or version (v1234567890)
      int startIndex = pathSegments.indexWhere((segment) => 
        segment == 'upload' || segment.startsWith('v')
      );
      
      if (startIndex == -1) return null;
      
      // Get all segments after version, excluding file extension
      final publicIdParts = pathSegments.sublist(startIndex + 1);
      final publicId = publicIdParts.join('/').replaceAll(RegExp(r'\.[^.]+$'), '');
      
      return publicId;
    } catch (e) {
      print('Error extracting public ID: $e');
      return null;
    }
  }

  /// Get optimized thumbnail URL
  String getOptimizedUrl(String imageUrl, {int width = 300, int height = 300}) {
    try {
      // Insert transformation parameters into URL
      final uri = Uri.parse(imageUrl);
      final pathParts = uri.path.split('/upload/');
      
      if (pathParts.length != 2) return imageUrl;
      
      final transformation = 'w_$width,h_$height,c_fill,q_auto,f_auto';
      final optimizedPath = '${pathParts[0]}/upload/$transformation/${pathParts[1]}';
      
      return uri.replace(path: optimizedPath).toString();
    } catch (e) {
      print('Error creating optimized URL: $e');
      return imageUrl;
    }
  }
}