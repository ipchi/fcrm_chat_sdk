# FCRM Chat SDK for Flutter

A Flutter SDK for integrating FCRM Chat Apps into your mobile applications. This package provides real-time messaging capabilities using Socket.IO and REST API integration.

## Features

- Real-time messaging via Socket.IO
- Automatic legacy/v2 protocol negotiation
- Signed configuration requests and token-authenticated v2 sessions
- User registration with custom fields
- Image uploads and v2 audio messages with progress and cancellation
- **Cancellable uploads** - Cancel image/file uploads in progress
- **Message editing** - Edit legacy messages within 24 hours
- **Partial user data updates** - Update legacy name, phone, email individually
- **Message metadata** - Attach custom metadata to legacy messages
- Legacy typing indicators
- V2 session resume, token renewal and missed-event recovery
- **Paginated message history** with infinite scrolling support
- Local storage for browser key and user data
- Connection state management
- Configurable logging for debugging

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
try {
  await chat.initialize();
  print('Chat initialized successfully');
} catch (e) {
  print('Failed to initialize chat: $e');
  // Handle initialization error (show user-friendly message)
}
```

### 2. Register User

```dart
// Register with required user data
try {
  await chat.register(
    userData: {
      'name': 'John Doe',
      'phone': '+1234567890',
      'email': 'john@example.com',
    },
    endpoint: 'Mobile App - Home Screen',
  );
  print('User registered successfully');
} on ChatException catch (e) {
  print('Registration failed: $e');
  // Handle missing required fields or validation errors
} catch (e) {
  print('Unexpected error during registration: $e');
}
```

### 3. Send Messages

```dart
// Send text message
try {
  final response = await chat.sendMessage('Hello! I need help with my order.');
  print('Message sent: ${response.userMessageId}');
} on ChatException catch (e) {
  print('Failed to send message: $e');
  // Handle not registered or not initialized errors
} catch (e) {
  print('Network error: $e');
  // Handle network errors, show retry option
}

// Send image
try {
  final imageFile = File('/path/to/image.jpg');
  final result = await chat.sendImage(imageFile);
  print('Image sent: ${result['image_url']}');
} catch (e) {
  print('Failed to send image: $e');
  // Handle file or upload errors
}

// Send image with progress tracking
try {
  final imageFile = File('/path/to/image.jpg');
  final result = await chat.sendImage(
    imageFile,
    onSendProgress: (sent, total) {
      final progress = (sent / total * 100).toStringAsFixed(1);
      print('Upload progress: $progress%');
    },
  );
  print('Image sent: ${result['image_url']}');
} catch (e) {
  print('Failed to send image: $e');
}

// Send image with cancellation support
final cancelToken = CancelToken();

// Start upload
final uploadFuture = chat.sendImage(
  imageFile,
  onSendProgress: (sent, total) {
    print('Progress: ${(sent / total * 100).toStringAsFixed(1)}%');
  },
  cancelToken: cancelToken,
);

// Cancel button handler
void onCancelPressed() {
  cancelToken.cancel();
}

try {
  final result = await uploadFuture;
  print('Uploaded: ${result['image_url']}');
} on UploadCancelledException {
  print('Upload was cancelled');
}
```

### 4. Send Message with Metadata

```dart
// Send message with custom metadata
final response = await chat.sendMessage(
  'I need help with order #12345',
  metadata: {
    'order_id': 12345,
    'source': 'order_detail_screen',
    'priority': 'high',
  },
);
```

### 5. Edit Messages

```dart
// Edit a message (only within 24 hours of creation)
try {
  final result = await chat.editMessage(
    messageId: 123,
    content: 'Updated message content',
  );
  print('Message edited successfully');
} on ChatApiException catch (e) {
  if (e.statusCode == 403) {
    print('Cannot edit: message is older than 24 hours');
  } else {
    print('Edit failed: ${e.message}');
  }
}

// Check if a message can be edited
for (final message in messages) {
  if (message.canEdit) {
    print('Message ${message.id} can be edited');
  }

  if (message.isEdited) {
    print('Edited at: ${message.editedAt}');
    print('Original: ${message.originalContent}');
  }
}
```

### 6. Update User Data

```dart
// Update only the name
await chat.updateName('New Name');

// Update only the phone
await chat.updatePhone('+1234567890');

// Update only the email
await chat.updateEmail('newemail@example.com');

// Update multiple fields at once (partial update)
final updatedData = await chat.updateUserData({
  'name': 'John Doe',
  'phone': '+1234567890',
  'company': 'Acme Inc',  // Custom fields supported
});
print('Updated user data: $updatedData');
```

### 7. Listen for Messages

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

### 8. Check Registration Status

```dart
// Check if user is already registered
final isRegistered = await chat.isRegistered();

if (isRegistered) {
  print('User is already registered');
  // Load chat history
  final messages = await chat.loadMessages();
  print('Loaded ${messages.length} messages');
} else {
  print('User needs to register');
  // Show registration form
}
```

### 9. Load Chat History with Pagination

```dart
// Load chat history when app starts or when regenerating chat page
// This automatically:
// 1. Checks if user is registered
// 2. Updates browser session
// 3. Returns paginated message history

// Load first page (default: 20 messages per page)
final result = await chat.loadMessages();

if (result.messages.isEmpty) {
  print('No messages or user not registered');
} else {
  print('Loaded ${result.messages.length} of ${result.total} messages');
  print('Page ${result.currentPage} of ${result.lastPage}');

  for (final message in result.messages) {
    print('${message.senderName}: ${message.content}');
  }

  // Check if more messages available
  if (result.hasMore) {
    print('More messages available. Load page ${result.currentPage + 1}');
  }
}

// Load specific page with custom page size
final page2 = await chat.loadMessages(page: 2, perPage: 50);
print('Loaded page 2 with ${page2.messages.length} messages');
```

### 10. Implement Infinite Scrolling

```dart
class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitialMessages();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadInitialMessages() async {
    final result = await chat.loadMessages(page: 1, perPage: 20);
    setState(() {
      _messages.addAll(result.messages);
      _hasMore = result.hasMore;
      _currentPage = result.currentPage;
    });
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final result = await chat.loadMessages(
        page: _currentPage + 1,
        perPage: 20,
      );

      setState(() {
        _messages.addAll(result.messages);
        _hasMore = result.hasMore;
        _currentPage = result.currentPage;
      });
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels == 0) {
      // User scrolled to top, load older messages
      _loadMoreMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return Center(child: CircularProgressIndicator());
        }
        return MessageWidget(message: _messages[index]);
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
```

### 11. Get Message History (Alternative Method)

```dart
// Fetch previous messages with pagination (requires registered user)
try {
  final result = await chat.getMessages(page: 1, perPage: 30);

  print('Total messages: ${result.total}');
  print('Current page: ${result.currentPage}/${result.lastPage}');
  print('Has more: ${result.hasMore}');

  for (final message in result.messages) {
    print('${message.senderName}: ${message.content}');
  }
} on ChatException catch (e) {
  print('Error: $e');
  // Handle not registered error
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

      // Check if already registered and load messages
      if (await _chat.isRegistered()) {
        // Load chat history using loadMessages() with pagination
        final result = await _chat.loadMessages(page: 1, perPage: 20);
        setState(() {
          _messages.addAll(result.messages);
        });
      } else {
        // Show registration prompt if needed
        // _showRegistrationDialog();
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
                          Image.network(message.imageUrl ?? message.content, width: 200)
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

## Recommended Usage Pattern

### Handling Registration and Chat History

Here's the recommended flow for handling user registration and loading chat history:

```dart
class ChatPage extends StatefulWidget {
  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late FcrmChat _chat;
  List<ChatMessage> _messages = [];
  bool _isRegistered = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    // 1. Create chat instance
    _chat = FcrmChat(
      config: ChatConfig(
        baseUrl: 'https://api.yourcompany.com',
        companyToken: 'your-company-token',
        appKey: 'your-app-key',
        appSecret: 'your-app-secret',
      ),
    );

    // 2. Setup message listener
    _chat.onMessage.listen((message) {
      setState(() {
        _messages.add(message);
      });
    });

    try {
      // 3. Initialize SDK
      await _chat.initialize();

      // 4. Check registration status
      final isRegistered = await _chat.isRegistered();

      setState(() {
        _isRegistered = isRegistered;
      });

      // 5. Load chat history if registered
      if (isRegistered) {
        final result = await _chat.loadMessages(page: 1, perPage: 20);
        setState(() {
          _messages = result.messages;
        });
      }
    } catch (e) {
      print('Error initializing chat: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _register() async {
    try {
      await _chat.register(
        userData: {
          'name': 'John Doe',
          'phone': '+1234567890',
          'email': 'john@example.com',
        },
      );

      // After registration, load messages
      final result = await _chat.loadMessages(page: 1, perPage: 20);

      setState(() {
        _isRegistered = true;
        _messages = result.messages;
      });
    } catch (e) {
      print('Registration error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (!_isRegistered) {
      return Center(
        child: ElevatedButton(
          onPressed: _register,
          child: Text('Start Chat'),
        ),
      );
    }

    // Show chat interface
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return MessageWidget(message: _messages[index]);
            },
          ),
        ),
        // Message input field
      ],
    );
  }
}
```

## Storage Details

### Browser Key Storage

The browser key is **automatically saved to device storage** using `SharedPreferences` when you call `register()`. This allows:

- **Persistent sessions**: User stays registered even after app restart
- **Automatic reconnection**: SDK automatically reconnects with saved credentials
- **Message history**: Access to previous conversations

**Storage Keys:**
- Browser Key: `fcrm_chat_browser_{appKey}`
- User Data: `fcrm_chat_user_{appKey}`

**To clear storage:**
```dart
await chat.reset(); // Clears all stored data and disconnects
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
| `enableV2` | bool | Negotiate v2 when advertised (default: true) |

### FcrmChat Methods

| Method | Description |
|--------|-------------|
| `initialize()` | Initialize SDK and connect to socket |
| `isRegistered()` | ✨ **Check if user is registered** (returns bool) |
| `register(userData, endpoint)` | Register new user/device |
| `loadMessages({page, perPage})` | ✨ **Load chat history with pagination** (auto-checks registration, updates session, returns paginated messages) |
| `updateBrowser(userData)` | Update user info and get history |
| `updateUserData(data)` | ✨ **Partial update user data** - update only specific fields |
| `updateName(name)` | ✨ Convenience method to update only name |
| `updatePhone(phone)` | ✨ Convenience method to update only phone |
| `updateEmail(email)` | ✨ Convenience method to update only email |
| `sendMessage(message, {endpoint, metadata})` | Send text message with optional metadata |
| `editMessage({messageId, content})` | ✨ **Edit a message** (within 24 hours) |
| `sendImage(file, {endpoint, onSendProgress, cancelToken})` | Upload and send image with progress and cancellation |
| `sendAudio(file, {durationMs, endpoint, clientMessageId, onSendProgress, cancelToken})` | Send a recorded v2 voice message |
| `getHistory({before, limit})` | Get v2 history using a sequence cursor |
| `markRead({upToSeq})` | Mark v2 operator/AI messages read |
| `syncEvents()` | Recover missed v2 events |
| `sendFile(file, {endpoint, onSendProgress, cancelToken})` | ✨ Upload and send file with progress and cancellation |
| `getMessages({page, perPage})` | Get paginated message history (requires registration) |
| `sendTyping(isTyping)` | Send typing indicator |
| `getUserData()` | Get stored user data |
| `reset()` | Clear all data and disconnect |
| `disconnect()` | Disconnect socket |
| `reconnect()` | Reconnect to socket |
| `dispose()` | Dispose all resources |
| `registerPushDevice({token, platform, ...})` | ✨ Register this device for push notifications — pass a token you already obtained from your own FCM setup |
| `sendPushHeartbeat(token)` | ✨ Keep-alive for a registered push device |
| `unregisterPushDevice(token)` | ✨ Stop push notifications to this device (e.g. on logout) |

### FcrmChat Streams

| Stream | Type | Description |
|--------|------|-------------|
| `onMessage` | `Stream<ChatMessage>` | Incoming messages |
| `onConnectionChange` | `Stream<bool>` | Connection status |
| `onTyping` | `Stream<bool>` | Typing indicator |
| `onReady` | `Stream<bool>` | SDK ready state |
| `onEvent` | `Stream<ChatEvent>` | V2 message creation/update events |
| `onError` | `Stream<Object>` | Background renewal/recovery errors |

### PaginatedMessages Properties

| Property | Type | Description |
|----------|------|-------------|
| `messages` | List\<ChatMessage\> | List of messages for current page |
| `total` | int | Total number of messages across all pages |
| `currentPage` | int | Current page number (1-indexed) |
| `perPage` | int | Number of messages per page |
| `lastPage` | int | Last page number |
| `hasMore` | bool | Whether more pages are available |

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
| `isAudio` | bool | Whether message is an audio attachment |
| `audioUrl` | String? | Audio attachment URL |
| `durationMs` | int? | Audio duration in milliseconds |
| `kind` | MessageKind? | Server attachment type for v2 |
| `seq` | int? | V2 history/read sequence |
| `clientMessageId` | String? | V2 send identity, retained for retries |
| `isEdited` | bool | ✨ Whether message has been edited |
| `editedAt` | DateTime? | ✨ Timestamp when message was edited |
| `originalContent` | String? | ✨ Original content before editing |
| `canEdit` | bool | ✨ Whether message can be edited (within 24 hours) |

### SendProgressCallback

```dart
typedef SendProgressCallback = void Function(int sent, int total);
```

Callback for tracking upload progress when sending images or files.

| Parameter | Type | Description |
|-----------|------|-------------|
| `sent` | int | Bytes sent so far |
| `total` | int | Total bytes to send |

### CancelToken

Token for cancelling upload operations.

```dart
final cancelToken = CancelToken();

// Check if cancelled
if (cancelToken.isCancelled) {
  print('Upload was cancelled');
}

// Cancel the upload
cancelToken.cancel();

// Wait for cancellation
await cancelToken.whenCancelled;
```

| Property/Method | Type | Description |
|-----------------|------|-------------|
| `isCancelled` | bool | Whether token has been cancelled |
| `cancel()` | void | Cancel the operation |
| `whenCancelled` | Future\<void\> | Future that completes when cancelled |

### UploadCancelledException

Exception thrown when an upload is cancelled.

```dart
try {
  await chat.sendImage(file, cancelToken: cancelToken);
} on UploadCancelledException {
  print('Upload was cancelled by user');
}
```

## Getting Credentials

1. Log in to your FCRM Dashboard
2. Navigate to **Chat Apps** section
3. Create a new Chat App or select existing one
4. Copy the **Key** and **Secret** values
5. Use these in your `ChatConfig`

## V2 audio and sessions

Version 1.7.0 sends `X-Chat-Sdk-Protocol: 2` to the signed mobile configuration endpoint. If the app advertises `v2`, the SDK uses that service; other apps continue through the legacy API. Set `ChatConfig(enableV2: false, ...)` to opt out. `chat.isV2` reports the selected protocol.

After initialization, check registration before creating a new session:

```dart
await chat.initialize();
if (!await chat.isRegistered()) {
  await chat.register(userData: {'name': 'John', 'phone': '+998901234567'});
}

if (chat.isV2) {
  // Record the file in your app first. The SDK sends the existing recording.
  final clientId = FcrmChat.newClientMessageId();
  final result = await chat.sendAudio(
    File('/path/to/voice.m4a'),
    durationMs: 3200,
    clientMessageId: clientId,
    onSendProgress: (sent, total) => print('$sent / $total'),
    cancelToken: CancelToken(),
  );
  final audioMessage = ChatMessage.fromJson(
    Map<String, dynamic>.from(result['message']),
  );
  print(audioMessage.audioUrl);
}
```

Import `dart:io` for `File`. Audio uploads accept a duration from 0 to 600000 milliseconds and files up to 10 MiB; images are limited to 5 MiB. Use a recording format supported by your backend, such as AAC in M4A/MP4, Ogg or WebM. The backend validates the file contents as well as its MIME type. WAV files detected as `audio/x-wav` may require a backend MIME allowlist update. `sendFile()` routes supported audio/images to the v2 attachment API; generic documents are not exposed there.

`sendAudio()` and `sendImage()` return the server's `{message, duplicate}` map in v2. Text sends return `SendMessageResponse`, with the projected message in `.message`. Both text and attachment methods accept `clientMessageId`; retain the same id when retrying the same send after a network error. Cancellation aborts the HTTP request, but a message already accepted by the server may still exist.

V2 access tokens stay in memory and refresh automatically. The rotating resume credential is saved separately from the legacy browser key and scoped to the backend, tenant and app. `initialize()` resumes it after an app restart. A temporary network error preserves the credential for a later retry; an invalid or blocked session clears it. `reset()` clears both protocols' stored sessions. V2 exposes `visitorId`; `browserKey` and `chatId` remain null because that API does not return them. Legacy history is not migrated into a v2 session.

For v2 pagination, use the sequence cursor:

```dart
final latest = await chat.getHistory(limit: 30);
if (latest.hasMore) {
  final older = await chat.getHistory(before: latest.beforeSeq, limit: 30);
  print(older.messages.length);
}
if (latest.messages.isNotEmpty) {
  await chat.markRead(upToSeq: latest.messages.last.seq!);
}
```

`getMessages(page:, perPage:)` and `loadMessages()` also adapt v2 cursor pages for existing callers; v2 `perPage` must be 1–50. Their `hasExactTotal` is false, `total` and `lastPage` are estimates from the pages fetched, and `nextBeforeSeq` supplies the next cursor. Prefer `hasMore` for pagination controls.

V2 attachments have `kind`, `imageUrl`, `audioUrl` and `durationMs`; `content` is empty for attachments. Render using `isImage`/`isAudio` and the corresponding URL. V2 text remains text even if it contains an image URL. `publicId` holds the opaque server id, while `id` maps to the numeric `seq` for compatibility. `allowLinks` carries the server's link-rendering policy.

The current v2 public API supports sessions, text, image/audio attachments, history, event recovery and read acknowledgements. Profile updates, message editing, ratings and push device registration remain legacy-only methods and throw `ChatException` on v2. Custom message metadata is also legacy-only. V2 has no typing socket event, so `sendTyping()` has no effect there.

## Socket Configuration

`initialize()` fetches `{baseUrl}/api/v1/mobile-chat/{companyToken}/config?key=...&sig=...`. Legacy sockets can connect immediately; v2 sockets connect after a session is created or resumed. `onReady` indicates configuration/session readiness, and `onConnectionChange` reports the actual socket connection.

| Protocol | Namespace | Transport path | Handshake authentication |
| --- | --- | --- | --- |
| Legacy | `/` | `/socket.io` | `{key: socket_api_key, browser_key}` |
| V2 | Advertised `socket_namespace`, normally `/v2` | Advertised `socket_path`, normally `/v2/socket.io` | `{token: access_token}` |

`ChatConfig.socketUrl` optionally overrides the socket origin. `connectionTimeout` applies to HTTP requests and the socket handshake. Each SDK instance uses an isolated Socket.IO manager, reconnects automatically and supplies its latest credential on every handshake.

Legacy clients join `private-chat_{browser_key}` and replay subscriptions after reconnecting. They receive colon and backslash versions of Chat/Telegram `MessageEvent` and `MessageEditedEvent`, along with `typing` and browser-key updates. V2 rooms are derived by the server from the verified token. The SDK sends no v2 room names or typing events.

V2 receives `message.created` and `message.updated`. After every connection, it drains `/v1/widget/events?after=...` until caught up, deduplicates live/replayed events and suppresses older snapshots of an already updated message. Token rotation reconnects the socket so the server resets its expiry timer. `syncEvents()` can also be called explicitly. Background renewal and recovery failures are available through `onError`.

```dart
chat.onMessage.listen((message) {
  // Insert or replace by publicId, or by clientMessageId for local pending sends.
  // Updates are emitted here too; appending every event creates duplicates.
});
chat.onEvent.listen((event) {
  print('${event.event} at cursor ${event.cursor}');
});
chat.onError.listen((error) => print('Chat background error: $error'));
chat.onConnectionChange.listen((connected) => print('Connected: $connected'));

chat.disconnect();
chat.reconnect();
```

Enable `ChatConfig.enableLogging` for connection diagnostics. V2 recovery cursors are tracked in memory; use history to populate the conversation after restarting your app. `dispose()` releases socket listeners, HTTP resources, streams and renewal timers.

## Requirements

- Flutter 3.22+
- Dart 3.4+
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
