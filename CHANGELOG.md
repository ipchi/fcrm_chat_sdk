# Changelog

All notable changes to this project will be documented in this file.

## [1.7.0] - 2026-10-20

### Added
- Automatic v2 negotiation through `X-Chat-Sdk-Protocol: 2`, with `enableV2: false` opt-out and legacy fallback.
- Token-authenticated visitor sessions, scoped rotating resume credentials, proactive token refresh and safe concurrent initialization/renewal.
- `sendAudio()` with duration, MIME handling, streamed progress, cancellation and idempotent retry keys. V2 text/image sends also accept `clientMessageId`.
- Typed audio/image messages, opaque public ids, sequence cursors and server link policy.
- Cursor history through `getHistory()`, `markRead()`, `syncEvents()`, `onEvent` and background `onError`.

### Fixed
- V2 Socket.IO namespace/path and authentication; reconnect recovery drains durable events, deduplicates retransmissions and ignores stale message snapshots.
- Legacy edited-message events, refreshed browser credentials and room resubscription after reconnect.
- Socket manager isolation, listener cleanup and reset/disposal guards for pending requests.
- Required registration fields supplied as either arrays or maps.

### Changed
- SDK version is 1.7.0; requires Dart 3.4+ / Flutter 3.22+ and `http` 1.5+ for request cancellation.
- V2 pagination has no exact server total; adapted page responses expose `hasExactTotal: false` and `nextBeforeSeq`.
- V2 operations not exposed by the server (profile updates, editing, ratings, push devices and custom metadata) fail explicitly. Legacy methods retain their existing endpoints.
- Audio recording/playback remain the host application's responsibility. Existing conversations are not migrated between protocols.

## [1.6.0] - 2026-09-05

### Added
- **Push notification device registration** — `FcrmChat.registerPushDevice()`,
  `sendPushHeartbeat()` and `unregisterPushDevice()`.

  The SDK does not depend on Firebase itself: obtain the token from your
  app's own FCM setup (`firebase_messaging` or equivalent) and pass it to
  `registerPushDevice()` along with `platform` (`'android'`/`'ios'`). This
  keeps the SDK usable in apps that don't want push at all, and avoids
  forcing a Firebase dependency on every consumer.

  Re-registering the same token is idempotent (updates the existing device
  row rather than duplicating it), so it's safe to call on every app start
  and on token refresh.

## [1.5.0] - 2026-09-03

### Added
- **Message ratings** - Clients can rate an admin answer from 1 to 5 stars with an
  optional comment.
  - `FcrmChat.rateMessage()`, `getRating()` and `removeRating()`
  - New `MessageRating` model
  - `ChatMessage.publicId`, `ChatMessage.isRatable` and `ChatMessage.rating`

  Ratings are addressed by the opaque `publicId`, not the numeric message id.
  The comment is always optional at every star value.

## [1.4.3] - 2025-11-29

### Fixed
- **Socket messages not received** - Fixed critical event name mismatch between SDK and backend
  - SDK now listens for `App:Events:Chat:MessageEvent` (colon format) sent by backend
  - Added backward compatibility for legacy backslash format
- **Socket channel name mismatch** - Fixed room naming format
  - Changed from `private-chat.{key}` (dot) to `private-chat_{key}` (underscore) to match backend
- Added listener cleanup for new event formats to prevent duplicate messages

## [1.2.2] - 2025-11-20

### Fixed
- Missing import for `PaginatedMessages` in `fcrm_chat.dart`

### Changed
- Updated dependencies to latest stable versions:
  - `http: ^1.2.0` (from ^1.1.2)
  - `shared_preferences: ^2.3.0` (from ^2.2.2)
  - `image_picker: ^1.0.7` (from ^1.0.4)
  - `path: ^1.9.0` (from ^1.8.3)
  - `mime: ^1.0.5` (from ^1.0.4)

## [1.2.1] - 2025-11-20

### Fixed
- Added missing `PaginatedMessages` import

## [1.2.0] - 2025-11-20

### Added
- **Pagination support** for `loadMessages()` and `getMessages()` methods
- **`PaginatedMessages` model** with metadata (total, currentPage, perPage, lastPage, hasMore)
- **Infinite scrolling example** in documentation
- **Logging control** for storage service operations
- Detailed pagination documentation with examples

### Changed
- 🚨 **BREAKING**: `loadMessages()` now returns `PaginatedMessages` instead of `List<ChatMessage>`
- 🚨 **BREAKING**: `getMessages()` now returns `PaginatedMessages` instead of `List<ChatMessage>`
- Both methods now accept `page` and `perPage` parameters (default: page=1, perPage=20)
- Updated all documentation examples to use pagination

### Fixed
- **Duplicate socket messages** - Fixed listener cleanup preventing duplicate message reception
- **Metadata parsing error** - Fixed handling of empty array `[]` from backend
- **Date filter issue** - Removed 2-day restriction on message history in backend
- Socket connection properly disposes old connections before creating new ones

### Backend Changes
- Updated `ChatService::getMessages()` to support pagination with skip/take
- Updated `MobileChatAppController::getMessages()` to accept page and per_page parameters
- Updated `ChatAppWidgetController::getMessages()` to support pagination
- Backend now returns pagination metadata in response

## [1.1.0] - 2025-11-20

### Added
- **`loadMessages()` function** - Load chat history with automatic registration check and session update
- **Enhanced documentation** with recommended usage patterns and storage details
- **Storage section** documenting browser key persistence mechanism
- **Comprehensive examples** showing proper registration flow and message history loading
- **Error handling examples** throughout all documentation

### Improved
- README with step-by-step registration check workflow
- Full example code with `loadMessages()` integration
- API Reference documentation with clear method descriptions
- Better documentation of `isRegistered()` function usage

### Backend Fixes
- Fixed `registerBrowser` endpoint to return `chat_id` in response
- Implemented socket broadcasting in `ChatService.sendSocketMessage()`
- Added automatic Lead creation when browser registers
- Fixed required fields validation to support both array formats
- Improved pipeline selection with chat app mapping support

## [1.0.0] - 2024-11-19

### Added
- Initial release
- Chat configuration with HMAC-SHA256 authentication
- Real-time messaging via Socket.IO
- REST API integration for all chat operations
- User registration with custom required fields
- Message history retrieval
- Image upload support
- Typing indicators
- Connection state management
- Local storage for browser key and user data
- Comprehensive documentation and examples
