# FCRM Chat SDK for Flutter

A Flutter SDK for integrating FCRM Chat Apps into your mobile applications. This package provides real-time messaging capabilities using Socket.IO and REST API integration.

## Features

- Real-time messaging via Socket.IO
- Secure authentication using HMAC-SHA256 signatures
- User registration with custom fields
- Image upload support
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
| `sendImage(file, endpoint)` | Upload and send image |
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

## Getting Credentials

1. Log in to your FCRM Dashboard
2. Navigate to **Chat Apps** section
3. Create a new Chat App or select existing one
4. Copy the **Key** and **Secret** values
5. Use these in your `ChatConfig`

## Socket Configuration

The SDK uses Socket.IO for real-time communication. Socket configuration is automatically fetched from your FCRM server during initialization, but developers can customize socket behavior.

### How Socket Configuration Works

When you call `chat.initialize()`, the SDK:
1. Fetches socket configuration from `{baseUrl}/api/chat_app/get_config`
2. Receives socket URL and other settings from the server
3. Connects to the socket server with authentication
4. Joins the private chat room using the browser key

### Socket Connection Details

The SDK establishes a Socket.IO connection with the following configuration:

```dart
// Socket connection is created with these parameters:
// - auth: { key: appKey, browser_key: browserKey }
// - transports: ['websocket', 'polling']
// - reconnection: true
// - reconnectionAttempts: 5
// - reconnectionDelay: 1000ms
// - timeout: 20000ms (configurable via ChatConfig)
```

### Authentication

The socket connection uses authentication to identify the client:

| Auth Parameter | Description |
|----------------|-------------|
| `key` | Your Chat App key (from ChatConfig.appKey) |
| `browser_key` | Unique browser/device identifier (auto-generated on registration) |

The `browser_key` is automatically included in socket auth after user registration and is used to:
- Join the correct private chat room (`private-chat.{browser_key}`)
- Receive messages specific to this user/device
- Maintain session across reconnections

### Custom Socket URL (Optional)

If you need to use a custom socket URL instead of the server-provided one:

```dart
final chat = FcrmChat(
  config: ChatConfig(
    baseUrl: 'https://api.yourcompany.com',
    companyToken: 'your-company-token',
    appKey: 'your-app-key',
    appSecret: 'your-app-secret',
    socketUrl: 'https://custom-socket.yourcompany.com', // Custom socket URL
    connectionTimeout: 30000, // Optional: increase timeout to 30s
  ),
);
```

### Socket Configuration Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `socketUrl` | String? | null | Custom socket server URL (overrides server config) |
| `connectionTimeout` | int | 20000 | Socket connection timeout in milliseconds |
| `transports` | List | ['websocket', 'polling'] | Transport methods (auto-configured) |
| `reconnection` | bool | true | Enable automatic reconnection (auto-configured) |
| `reconnectionAttempts` | int | 5 | Max reconnection attempts (auto-configured) |
| `reconnectionDelay` | int | 1000 | Delay between reconnection attempts in ms (auto-configured) |

### Server-Side Socket Configuration

Developers deploying the FCRM server should configure the socket server endpoint in their backend settings. The SDK will automatically retrieve this configuration via the `/api/chat_app/get_config` endpoint.

Example server response:
```json
{
  "socket_url": "https://socket.yourcompany.com",
  "chat_app": {
    "key": "app_key",
    "name": "Your Chat App"
  }
}
```

### Socket Events Reference

The SDK automatically handles these socket events:

#### Incoming Events (Server → Client)

| Event | Data | Description |
|-------|------|-------------|
| `connect` | - | Socket connection established successfully |
| `disconnect` | `reason` | Socket disconnected (auto-reconnects) |
| `connect_error` | `error` | Connection failed (triggers retry) |
| `reconnect` | `attemptNumber` | Successfully reconnected after disconnect |
| `reconnect_attempt` | `attemptNumber` | Attempting to reconnect |
| `App\\Events\\Chat\\MessageEvent` | `{ message }` | New message from Laravel broadcast |
| `typing` | `{ isTyping }` | Agent typing indicator |
| `auth-error` | `{ message }` | Authentication failed |

#### Outgoing Events (Client → Server)

| Event | Data | Description |
|-------|------|-------------|
| `join` | `private-chat.{browser_key}` | Join private chat room |
| `typing` | `{ browser_key, isTyping }` | Send typing indicator |

### Connection Management

```dart
// Listen for connection status
chat.onConnectionChange.listen((connected) {
  if (connected) {
    print('Socket connected');
  } else {
    print('Socket disconnected');
  }
});

// Manual reconnection
await chat.reconnect();

// Disconnect
chat.disconnect();
```

### Socket Connection Lifecycle

1. **Initialize**: `chat.initialize()` fetches config from server
2. **Connect**: Socket establishes connection with auth (`key` + `browser_key`)
3. **Join Room**: Automatically joins `private-chat.{browser_key}` room
4. **Active**: Real-time message exchange via Laravel broadcast events
5. **Disconnect**: Auto-reconnect (up to 5 attempts with 1s delay)
6. **Reconnect**: On successful reconnect, automatically rejoins chat room
7. **Disposed**: `chat.dispose()` permanently closes connection

**Important Notes:**
- The `browser_key` is updated in socket auth during reconnection attempts
- Chat room is automatically rejoined after successful reconnection
- All messages are received via `App\\Events\\Chat\\MessageEvent` broadcast
- Private chat room ensures messages are only delivered to the correct user/device

### Chat Room Mechanics

The SDK uses private chat rooms to ensure secure, isolated communication:

```dart
// After registration or browser update, the SDK automatically:
// 1. Receives a unique browser_key from the server
// 2. Includes browser_key in socket authentication
// 3. Joins the private room: 'private-chat.{browser_key}'
// 4. Receives messages via Laravel broadcast to this specific room
```

**Room Lifecycle:**
- **On Connect**: Joins `private-chat.{browser_key}` if browser_key exists
- **On Reconnect**: Automatically rejoins the same room
- **On Registration**: Receives browser_key, then joins room
- **On Update**: Updates browser data, rejoins room if needed

**Message Flow:**
1. User sends message via REST API (`/api/chat_app/browser/send-message`)
2. Server processes message and stores in database
3. Server broadcasts `App\\Events\\Chat\\MessageEvent` to the private room
4. SDK receives broadcast event via Socket.IO
5. SDK emits message via `onMessage` stream
6. Your app displays the message in UI

### Debugging Socket Connection

Enable logging to debug socket issues:

```dart
final chat = FcrmChat(
  config: ChatConfig(
    baseUrl: 'https://api.yourcompany.com',
    companyToken: 'your-company-token',
    appKey: 'your-app-key',
    appSecret: 'your-app-secret',
    enableLogging: true, // Enable debug logs
  ),
);
```

This will output socket connection events, errors, and message flow to the console.

**Debug Checklist:**
- ✅ Verify socket URL is returned from `/api/chat_app/get_config`
- ✅ Confirm `browser_key` is stored in local storage after registration
- ✅ Check socket auth includes both `key` and `browser_key`
- ✅ Ensure private room name matches: `private-chat.{browser_key}`
- ✅ Verify Laravel broadcast is configured and running
- ✅ Check that messages are broadcast to the correct room

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
