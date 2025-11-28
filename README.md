# FCRM Chat SDK for Flutter

A Flutter SDK for integrating FCRM Chat Apps into your mobile applications. This package provides real-time messaging capabilities using Socket.IO and REST API integration.

## Features

- Real-time messaging via Socket.IO
- Secure authentication using HMAC-SHA256 signatures
- User registration with custom fields
- Image upload support with progress tracking
- Typing indicators
- Message history
- Local storage for browser key and user data
- Connection state management

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  fcrm_chat_sdk:
    git:
      url: https://github.com/ipchi/fcrm_chat_sdk.git
      ref: main
```

Or for local development:

```yaml
dependencies:
  fcrm_chat_sdk:
    path: ../fcrm_chat_sdk
```

## Quick Start

### 1. Initialize the SDK

```dart
import 'package:fcrm_chat_sdk/fcrm_chat_sdk.dart';

// Create chat instance with your credentials
final chat = FcrmChat(
  config: ChatConfig(
    baseUrl: 'https://your-api-domain.com',
    companyToken: 'your-company-token',  // Tenant/Company token
    appKey: 'your-chat-app-key',
    appSecret: 'your-chat-app-secret',
    enableLogging: true, // Optional: Enable debug logs
  ),
);

// Initialize (fetches config and connects to socket)
await chat.initialize();
```

### 2. Register User

```dart
// Register with required user data
await chat.register(
  userData: {
    'name': 'John Doe',
    'phone': '+1234567890',
    'email': 'john@example.com',
  },
  endpoint: 'Mobile App - Home Screen',
);
```

### 3. Send Messages

```dart
// Send text message
final response = await chat.sendMessage('Hello! I need help with my order.');

// Send image
final imageFile = File('/path/to/image.jpg');
final result = await chat.sendImage(imageFile);

// Send image with progress tracking
final result = await chat.sendImage(
  imageFile,
  onSendProgress: (sent, total) {
    final progress = (sent / total * 100).toStringAsFixed(1);
    print('Upload progress: $progress%');
  },
);
```

### 4. Listen for Messages

```dart
// Listen for incoming messages
chat.onMessage.listen((message) {
  print('New message: ${message.content}');
  print('From: ${message.senderName}');
  print('Type: ${message.type}'); // user, admin, ai, system
});

// Listen for connection status
chat.onConnectionChange.listen((connected) {
  print('Connected: $connected');
});

// Listen for typing indicator
chat.onTyping.listen((isTyping) {
  if (isTyping) {
    print('Agent is typing...');
  }
});
```

### 5. Get Message History

```dart
// Fetch previous messages
final messages = await chat.getMessages();
for (final message in messages) {
  print('${message.senderName}: ${message.content}');
}
```

## Full Example

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fcrm_chat_sdk/fcrm_chat_sdk.dart';

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late FcrmChat _chat;
  final _messages = <ChatMessage>[];
  final _messageController = TextEditingController();
  bool _isConnected = false;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    _chat = FcrmChat(
      config: ChatConfig(
        baseUrl: 'https://api.yourcompany.com',
        companyToken: 'your-company-token',
        appKey: 'your-app-key',
        appSecret: 'your-app-secret',
        enableLogging: true,
      ),
    );

    // Setup listeners
    _chat.onMessage.listen((message) {
      setState(() {
        _messages.add(message);
      });
    });

    _chat.onConnectionChange.listen((connected) {
      setState(() {
        _isConnected = connected;
      });
    });

    _chat.onTyping.listen((typing) {
      setState(() {
        _isTyping = typing;
      });
    });

    // Initialize
    try {
      await _chat.initialize();

      // Check if already registered
      if (await _chat.isRegistered()) {
        final userData = await _chat.getUserData();
        final history = await _chat.updateBrowser(userData: userData!);
        setState(() {
          _messages.addAll(history);
        });
      }
    } catch (e) {
      print('Init error: $e');
    }
  }

  Future<void> _register() async {
    try {
      await _chat.register(
        userData: {
          'name': 'John Doe',
          'phone': '+1234567890',
        },
      );
      print('Registered successfully');
    } catch (e) {
      print('Registration error: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      await _chat.sendMessage(text);
      _messageController.clear();
    } catch (e) {
      print('Send error: $e');
    }
  }

  @override
  void dispose() {
    _chat.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat'),
        actions: [
          Icon(
            Icons.circle,
            color: _isConnected ? Colors.green : Colors.red,
            size: 12,
          ),
          SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message.type == MessageType.user;

                return Align(
                  alignment: isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.all(8),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blue : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.senderName != null)
                          Text(
                            message.senderName!,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        if (message.isImage)
                          Image.network(message.content, width: 200)
                        else
                          Text(
                            message.content,
                            style: TextStyle(
                              color: isUser ? Colors.white : Colors.black,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isTyping)
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('Agent is typing...'),
            ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      _chat.sendTyping(true);
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

## API Reference

### ChatConfig

| Property | Type | Description |
|----------|------|-------------|
| `baseUrl` | String | Base URL of your FCRM API |
| `companyToken` | String | Company/Tenant token for identification |
| `appKey` | String | Chat App key from FCRM dashboard |
| `appSecret` | String | Chat App secret from FCRM dashboard |
| `socketUrl` | String? | Custom socket URL (optional) |
| `connectionTimeout` | int | Connection timeout in ms (default: 20000) |
| `enableLogging` | bool | Enable debug logging (default: false) |

### FcrmChat Methods

| Method | Description |
|--------|-------------|
| `initialize()` | Initialize SDK and connect to socket |
| `register(userData, endpoint)` | Register new user/device |
| `updateBrowser(userData)` | Update user info and get history |
| `sendMessage(message, endpoint)` | Send text message |
| `sendImage(file, endpoint, onSendProgress)` | Upload and send image with optional progress callback |
| `getMessages()` | Get message history |
| `sendTyping(isTyping)` | Send typing indicator |
| `isRegistered()` | Check if user is registered |
| `getUserData()` | Get stored user data |
| `reset()` | Clear all data and disconnect |
| `disconnect()` | Disconnect socket |
| `reconnect()` | Reconnect to socket |
| `dispose()` | Dispose all resources |

### FcrmChat Streams

| Stream | Type | Description |
|--------|------|-------------|
| `onMessage` | `Stream<ChatMessage>` | Incoming messages |
| `onConnectionChange` | `Stream<bool>` | Connection status |
| `onTyping` | `Stream<bool>` | Typing indicator |
| `onReady` | `Stream<bool>` | SDK ready state |

### ChatMessage Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | int | Message ID |
| `chatId` | int | Chat ID |
| `content` | String | Message content or image URL |
| `type` | MessageType | user, admin, ai, system |
| `senderName` | String? | Sender name |
| `senderType` | String? | Sender type |
| `createdAt` | DateTime | Timestamp |
| `metadata` | Map? | Additional metadata |
| `isImage` | bool | Whether message is an image |

### SendProgressCallback

```dart
typedef SendProgressCallback = void Function(int sent, int total);
```

Callback for tracking upload progress when sending images or files.

| Parameter | Type | Description |
|-----------|------|-------------|
| `sent` | int | Bytes sent so far |
| `total` | int | Total bytes to send |

## Getting Credentials

1. Log in to your FCRM Dashboard
2. Navigate to **Chat Apps** section
3. Create a new Chat App or select existing one
4. Copy the **Key** and **Secret** values
5. Use these in your `ChatConfig`

## Requirements

- Flutter 3.0+
- Dart 3.0+
- iOS 12.0+ / Android API 21+

## Dependencies

- `http` - HTTP requests
- `socket_io_client` - Real-time communication
- `crypto` - HMAC-SHA256 signatures
- `shared_preferences` - Local storage
- `image_picker` - Image selection
- `mime` - MIME type detection

## Troubleshooting

### Connection Issues

1. Verify your `baseUrl` is correct and accessible
2. Check that your `appKey` and `appSecret` are valid
3. Ensure the Chat App is active in FCRM dashboard
4. Check firewall settings for socket connections

### Message Not Received

1. Verify socket connection status via `onConnectionChange`
2. Ensure user is registered via `register()` or `updateBrowser()`
3. Check that browser key is saved correctly

### Registration Fails

1. Verify all required fields are provided
2. Check required fields in FCRM Chat App settings
3. Ensure `userData` contains all configured required fields

## License

MIT License - see LICENSE file for details.

## Support

For issues and feature requests, please visit:
- GitHub Issues: https://github.com/ipchi/fcrm_chat_sdk/issues
- FCRM Documentation: https://docs.yourcompany.com
