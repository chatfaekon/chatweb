class ChatState {
  static String? activeChatId;
  static String? currentChatId;
  static bool isChatOpen = false;
  static bool isAdmin = false;

  // Suporte para evitar o "piscar" da bolinha vermelha ao fechar um chat
  static String? recentlyClosedId;
  static DateTime? closedAt;

  static bool isRecentlyClosed(String id) {
    if (recentlyClosedId == id && closedAt != null) {
      final diff = DateTime.now().difference(closedAt!).inMilliseconds;
      return diff < 800; // 800ms de debounce visual
    }
    return false;
  }
}
