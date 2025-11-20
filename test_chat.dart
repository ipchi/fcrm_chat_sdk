import 'package:fcrm_chat_sdk/fcrm_chat_sdk.dart';

void main() async {
  print('🚀 Starting FCRM Chat SDK Test...\n');

  // Create chat instance with your credentials
  final chat = FcrmChat(
    config: ChatConfig(
      baseUrl: 'http://localhost:8000',
      companyToken: 'wq8KnuWceNPcM7VgkDnyZ4FQOTPpsLov',
      appKey: 'dykGCkQ9BphZKqzjhSQSWIANV2fopV0N',
      appSecret: '5j38m2Sny4wnGCuh7xXHYXQXg3Ks1xVf',
      socketUrl: 'https://socket-ipchi.mudir.uz',
      enableLogging: true,
    ),
  );

  // Listen for connection changes
  chat.onConnectionChange.listen((connected) {
    print('📡 Connection status: ${connected ? "Connected ✅" : "Disconnected ❌"}');
  });

  // Listen for messages
  chat.onMessage.listen((message) {
    print('💬 New message received:');
    print('   - Type: ${message.type}');
    print('   - Sender: ${message.senderName}');
    print('   - Content: ${message.content}');
    print('   - Time: ${message.createdAt}');
  });

  // Listen for typing indicators
  chat.onTyping.listen((isTyping) {
    if (isTyping) {
      print('✍️  Agent is typing...');
    }
  });

  try {
    // Step 1: Initialize
    print('📋 Step 1: Initializing chat...');
    await chat.initialize();
    print('✅ Chat initialized successfully!\n');

    // Wait a bit for socket to connect
    await Future.delayed(Duration(seconds: 2));

    // Step 2: Register user
    print('📋 Step 2: Registering user...');
    await chat.register(
      userData: {
        'name': 'Test User',
        'phone': '+998901234567',
        'email': 'test@example.com',
      },
      endpoint: 'Test Script - Main',
    );
    print('✅ User registered successfully!');
    print('   - Browser Key: ${chat.browserKey}');
    print('   - Chat ID: ${chat.chatId}\n');

    // Wait a bit for socket to join room
    await Future.delayed(Duration(seconds: 2));

    // Step 3: Send message
    print('📋 Step 3: Sending message "Bismillah"...');
    final response = await chat.sendMessage('Bismillah');
    print('✅ Message sent successfully!');
    print('   - Message ID: ${response.userMessageId}');
    print('   - Chat ID: ${response.chatId}');
    if (response.aiMessage != null) {
      print('   - AI Response: ${response.aiMessage!['content']}\n');
    } else {
      print('');
    }

    // Keep alive to receive socket messages
    print('👂 Listening for incoming messages for 30 seconds...');
    print('   (Press Ctrl+C to exit)\n');

    await Future.delayed(Duration(seconds: 30));

    print('\n✅ Test completed successfully!');
    print('   You can now check the backend to see the message.');

  } on ChatException catch (e) {
    print('❌ Chat error: $e');
  } catch (e, stackTrace) {
    print('❌ Unexpected error: $e');
    print('Stack trace: $stackTrace');
  } finally {
    // Cleanup
    print('\n🧹 Cleaning up...');
    chat.dispose();
    print('✅ Done!');
  }
}
