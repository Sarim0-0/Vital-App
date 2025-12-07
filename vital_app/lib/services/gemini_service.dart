import 'package:flutter_gemini/flutter_gemini.dart';

class GeminiService {
  final Gemini _gemini = Gemini.instance;
  
  Future<String> sendMessage(String message) async {
    try {
      // Use the prompt method to send message
      final response = await _gemini.prompt(parts: [Part.text(message)]);
      
      // Primary method: get output (as shown in documentation: value?.output)
      if (response?.output != null && response!.output!.isNotEmpty) {
        return response.output!;
      }
      
      // Fallback: try to get text from content.parts (as shown in docs: value?.content?.parts?.last.text)
      if (response?.content?.parts != null && response!.content!.parts!.isNotEmpty) {
        final lastPart = response.content!.parts!.last;
        // Check if it's a TextPart and get the text
        if (lastPart is TextPart) {
          return lastPart.text;
        }
      }
      
      throw 'No response received from API';
    } catch (e) {
      // Handle various error types
      final errorString = e.toString();
      
      if (errorString.contains('API key') || 
          errorString.contains('not configured') ||
          errorString.contains('not initialized')) {
        throw 'API key not configured. Please set your API_KEY in the .env file.';
      }
      
      if (errorString.contains('quota') || errorString.contains('limit')) {
        throw 'API quota exceeded. Please check your usage limits.';
      }
      
      if (errorString.contains('network') || errorString.contains('connection')) {
        throw 'Network error: Please check your internet connection.';
      }
      
      // Return the error message
      if (e is String) {
        throw e;
      }
      
      throw 'An error occurred: ${e.toString()}';
    }
  }
}
