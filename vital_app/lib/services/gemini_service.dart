import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  // Ensure Gemini is initialized before use
  void _ensureInitialized() {
    final apiKey = dotenv.env['API_KEY'];
    if (apiKey == null ||
        apiKey.isEmpty ||
        apiKey == 'your_gemini_api_key_here') {
      throw 'API key not configured. Please set your API_KEY in the .env file.';
    }

    // Always re-initialize to ensure it's set (safe to call multiple times)
    try {
      Gemini.init(apiKey: apiKey);
    } catch (e) {
      // If initialization fails, throw a clear error
      throw 'Failed to initialize Gemini API. Please check your API_KEY in the .env file.';
    }
  }

  Future<String> sendMessage(String message) async {
    try {
      // Ensure Gemini is initialized before each request
      _ensureInitialized();

      // Validate message is not empty
      if (message.trim().isEmpty) {
        throw 'Message cannot be empty';
      }

      // Use the prompt method according to documentation
      // Documentation shows: Gemini.instance.prompt(parts: [Part.text('...')])
      final response = await Gemini.instance.prompt(parts: [Part.text(message.trim())]);

      // According to documentation, access response via value?.output
      if (response?.output != null) {
        final output = response!.output!;
        if (output.isNotEmpty) {
          return output;
        }
      }

      // Fallback: try to get text from content.parts.last.text (as shown in docs)
      if (response?.content?.parts != null &&
          response!.content!.parts!.isNotEmpty) {
        final lastPart = response.content!.parts!.last;
        if (lastPart is TextPart) {
          final text = lastPart.text;
          if (text.isNotEmpty) {
            return text;
          }
        }
      }

      throw 'No response received from API';
    } catch (e) {
      // Handle various error types
      final errorString = e.toString();

      // Check for API key errors
      if (errorString.contains('API key') ||
          errorString.contains('not configured') ||
          errorString.contains('not initialized') ||
          errorString.contains('401') ||
          errorString.contains('403')) {
        throw 'API key error. Please check your API_KEY in the .env file.';
      }

      // Check for bad request errors (400)
      if (errorString.contains('400') ||
          errorString.contains('bad syntax') ||
          errorString.contains('cannot be fulfilled')) {
        throw 'Invalid request. Please check your API key and try again.';
      }

      // Check for quota/limit errors
      if (errorString.contains('quota') ||
          errorString.contains('limit') ||
          errorString.contains('429')) {
        throw 'API quota exceeded. Please check your usage limits.';
      }

      // Check for network errors
      if (errorString.contains('network') ||
          errorString.contains('connection') ||
          errorString.contains('timeout')) {
        throw 'Network error: Please check your internet connection.';
      }

      // Return the error message
      // If it's a string error message, throw it as-is
      if (e is String) {
        // ignore: use_rethrow_when_possible
        // Can't use rethrow for String types, only for Exception types
        throw e; // ignore: use_rethrow_when_possible
      }

      // For exceptions, convert to user-friendly message
      throw 'An error occurred: ${e.toString()}';
    }
  }
}
