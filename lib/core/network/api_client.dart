class ApiClient {
  // 🚀 The single source of truth for your backend URL
  static const String baseUrl = "https://tym-whatsapp-backend.onrender.com";

  // 🚀 Standard headers used across all feature APIs
  static Map<String, String> get defaultHeaders => {
    "Content-Type": "application/json",
    "Accept": "*/*",
  };
}
