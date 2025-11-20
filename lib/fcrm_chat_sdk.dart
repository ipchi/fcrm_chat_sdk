/// FCRM Chat SDK - Flutter package for FCRM Chat Apps integration
///
/// This package provides easy integration with FCRM Chat Apps system,
/// including real-time messaging via Socket.IO and REST API support.
library fcrm_chat_sdk;

// Configuration
export 'src/config/chat_config.dart';

// Models
export 'src/models/message.dart';
export 'src/models/chat_app_config.dart';
export 'src/models/browser.dart';
export 'src/models/paginated_messages.dart';

// Services
export 'src/services/chat_api_service.dart';
export 'src/services/chat_socket_service.dart';
export 'src/services/chat_storage_service.dart';

// Main SDK class
export 'src/fcrm_chat.dart';
