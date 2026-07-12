class CrmApiClient {
  // 🚀 The separate FastAPI + MongoDB service (Render), independent of
  // the existing Node backend in api_client.dart. Handles: menu, contacts,
  // labels, campaigns, delivery boys.
  static const String baseUrl = "https://erp-backend-n1du.onrender.com";

  static Map<String, String> get defaultHeaders => {
    "Content-Type": "application/json",
    "Accept": "*/*",
  };
}