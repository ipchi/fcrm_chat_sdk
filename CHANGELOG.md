# Changelog

All notable changes to this project will be documented in this file.

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
