# Changelog

All notable changes to this project will be documented in this file.

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
