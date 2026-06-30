import 'package:flutter/material.dart';
import 'package:whatsapp_erp_api/screens/login_screen.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';

class SettingsScreen extends StatefulWidget {
  final String restaurantId;
  const SettingsScreen({super.key, required this.restaurantId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;

  // Edit State Toggles for all 4 Tabs
  bool _isEditingProfile = false;
  bool _isEditingOps = false;
  bool _isEditingBot = false;
  bool _isEditingApi = false;

  // 1. Basic & Location
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _radiusController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  // 2. Financials
  final TextEditingController _gstRateController = TextEditingController();
  final TextEditingController _deliveryFeeController = TextEditingController();

  // 3. Media (Bot Config)
  final TextEditingController _videoLinkController = TextEditingController();
  final TextEditingController _videoMediaIdController = TextEditingController();

  // 4. API & Integrations
  final TextEditingController _wabaIdController = TextEditingController();
  final TextEditingController _phoneIdController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _catalogIdController = TextEditingController();
  final TextEditingController _rzpKeyController = TextEditingController();
  final TextEditingController _rzpSecretController = TextEditingController();
  final TextEditingController _rzpWebhookController = TextEditingController();
  final TextEditingController _sheetUrlController = TextEditingController();
  final TextEditingController _sheetIdController = TextEditingController();

  // Safe Backend ENUM Default States
  String _serviceType = 'BOTH';
  String _paymentMethod = 'BOTH';
  String _primaryFlow = 'LOCATION_FIRST';
  String _deliveryFlow = 'LOCATION_FIRST';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final data = await _apiService.fetchRestaurantProfile(widget.restaurantId);

    if (data != null && mounted) {
      // Save to SQLite so KOT and other offline features always have current data
      await DatabaseHelper.instance.saveSettings(data);
      setState(() {

        // Basic Info
        _nameController.text = data['name'] ?? '';
        _addressController.text = data['address'] == 'string'
            ? ''
            : (data['address'] ?? '');
        _radiusController.text = data['deliveryRadius']?.toString() ?? '5';

        _latitudeController.text = data['latitude']?.toString() ?? '0.0';
        _longitudeController.text = data['longitude']?.toString() ?? '0.0';

        // Financials
        _gstRateController.text = data['gstRate']?.toString() ?? '0';
        _deliveryFeeController.text = data['deliveryFee']?.toString() ?? '0';

        // Media
        _videoLinkController.text = data['welcomeVideoUrl'] == 'string'
            ? ''
            : (data['welcomeVideoUrl'] ?? '');
        _videoMediaIdController.text = data['welcomeVideoMediaId'] == 'string'
            ? ''
            : (data['welcomeVideoMediaId'] ?? '');

        // APIs
        _wabaIdController.text = data['wabaId'] ?? '';
        _phoneIdController.text = data['phoneNumberId'] ?? '';
        _tokenController.text = data['waToken'] ?? '';

        // Helper to remove fallback 'string'
        String getClean(String key) =>
            data[key] == 'string' ? '' : (data[key] ?? '');

        _catalogIdController.text = getClean('catalogId');
        _rzpKeyController.text = getClean('razorpayKeyId');
        _rzpSecretController.text = getClean('razorpayKeySecret');
        _rzpWebhookController.text = getClean('razorpayWebhookSecret');
        _sheetUrlController.text = getClean('googleSheetUrl');
        _sheetIdController.text = getClean('googleSheetId');

        // Enums
        _serviceType = data['serviceType'] ?? 'BOTH';
        _paymentMethod = data['paymentAvailability'] ?? 'BOTH';
        _primaryFlow = data['primaryFlowType'] ?? 'LOCATION_FIRST';
        _deliveryFlow = data['deliveryFlowType'] ?? 'LOCATION_FIRST';

        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await DatabaseHelper.instance.clearSession();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettingsToBackend(
    Map<String, dynamic> updatedFields,
    VoidCallback closeEditMode,
  ) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Saving changes...")));

    bool success = await _apiService.updateRestaurantSettings(
      widget.restaurantId,
      updatedFields,
    );

    if (!mounted) return;

    if (success) {
      closeEditMode();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Changes saved successfully!"),
          backgroundColor: Colors.green,
        ),
      );
      _loadProfile();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to save changes. Check backend logs."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(
            child: CircularProgressIndicator(color: Color(0xFF2563EB)),
          )
        : DefaultTabController(
            length: 4,
            child: Scaffold(
              backgroundColor: const Color(0xFFF9FAFB),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Header section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.menu, color: Color(0xFF111827)),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Account Settings",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 24,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  "Manage your account settings, integrations, and preferences",
                                  style: TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => _logout(context),
                          icon: const Icon(
                            Icons.logout,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1, color: Color(0xFFE5E7EB)),

                  // Left-Aligned Tab Bar
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
                      ),
                    ),
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorColor: const Color(0xFF2563EB),
                      indicatorWeight: 2,
                      labelColor: const Color(0xFF2563EB),
                      unselectedLabelColor: const Color(0xFF4B5563),
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      dividerColor: Colors.transparent,
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                      tabs: const [
                        Tab(text: "Profile Information"),
                        Tab(text: "Operations & Payment"),
                        Tab(text: "Bot Configuration"),
                        Tab(text: "API Integrations"),
                      ],
                    ),
                  ),

                  // Tab Content
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildProfileTab(),
                        _buildOperationsTab(),
                        _buildBotConfigTab(),
                        _buildApiTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
  }

  // 🏪 TAB 1: Profile Information
  Widget _buildProfileTab() {
    return _buildScrollableTab(
      child: _buildContentCard(
        title: "Account Information",
        subtitle: "Manage your restaurant details and location mapping",
        isEditing: _isEditingProfile,
        onEdit: () => setState(() => _isEditingProfile = true),
        onCancel: () {
          setState(() => _isEditingProfile = false);
          _loadProfile();
        },
        onSave: () {
          _saveSettingsToBackend({
            "name": _nameController.text.trim(),
            "address": _addressController.text.trim(),
            "deliveryRadius": int.tryParse(_radiusController.text.trim()) ?? 5,
            "latitude": double.tryParse(_latitudeController.text.trim()) ?? 0.0,
            "longitude":
                double.tryParse(_longitudeController.text.trim()) ?? 0.0,
          }, () => setState(() => _isEditingProfile = false));
        },
        content: Column(
          children: [
            _buildInputGrid([
              _buildInputField(
                "Restaurant Name",
                Icons.storefront_outlined,
                _nameController,
                _isEditingProfile,
              ),
              _buildInputField(
                "Delivery Radius (KM)",
                Icons.map_outlined,
                _radiusController,
                _isEditingProfile,
                isNumber: true,
              ),
            ]),
            const SizedBox(height: 24),
            _buildInputField(
              "Complete Address",
              Icons.location_on_outlined,
              _addressController,
              _isEditingProfile,
              maxLines: 2,
            ),

            const SizedBox(height: 32),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.pin_drop_outlined,
                    size: 18,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  "Map Coordinates",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInputGrid([
              _buildInputField(
                "Latitude",
                Icons.map_outlined,
                _latitudeController,
                _isEditingProfile,
                isNumber: true,
              ),
              _buildInputField(
                "Longitude",
                Icons.map_outlined,
                _longitudeController,
                _isEditingProfile,
                isNumber: true,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // 💼 TAB 2: Operations & Payment
  Widget _buildOperationsTab() {
    return _buildScrollableTab(
      child: _buildContentCard(
        title: "Service Offerings",
        subtitle: "Configure delivery fees, taxes, and service availability",
        isEditing: _isEditingOps,
        onEdit: () => setState(() => _isEditingOps = true),
        onCancel: () {
          setState(() => _isEditingOps = false);
          _loadProfile();
        },
        onSave: () {
          _saveSettingsToBackend({
            "gstRate": double.tryParse(_gstRateController.text.trim()) ?? 0.0,
            "deliveryFee":
                double.tryParse(_deliveryFeeController.text.trim()) ?? 0.0,
            "serviceType": _serviceType,
            "paymentAvailability": _paymentMethod,
          }, () => setState(() => _isEditingOps = false));
        },
        content: Column(
          children: [
            _buildInputGrid([
              _buildInputField(
                "GST Rate (%)",
                Icons.receipt_long_outlined,
                _gstRateController,
                _isEditingOps,
                isNumber: true,
              ),
              _buildInputField(
                "Delivery Fee (₹)",
                Icons.local_shipping_outlined,
                _deliveryFeeController,
                _isEditingOps,
                isNumber: true,
              ),
            ]),
            const SizedBox(height: 24),
            _buildInputGrid([
              _buildDropdownField(
                label: "Service Type",
                icon: Icons.storefront_outlined,
                value: _serviceType,
                items: const [
                  DropdownMenuItem(
                    value: "DELIVERY",
                    child: Text("Delivery Only"),
                  ),
                  DropdownMenuItem(
                    value: "TAKEAWAY",
                    child: Text("Takeaway Only"),
                  ),
                  DropdownMenuItem(
                    value: "BOTH",
                    child: Text("Both (Delivery & Takeaway)"),
                  ),
                ],
                isEditing: _isEditingOps,
                onChanged: (val) => setState(() => _serviceType = val!),
              ),
              _buildDropdownField(
                label: "Payment Methods",
                icon: Icons.payments_outlined,
                value: _paymentMethod,
                items: const [
                  DropdownMenuItem(
                    value: "COD",
                    child: Text("Cash on Delivery (COD)"),
                  ),
                  DropdownMenuItem(
                    value: "ONLINE",
                    child: Text("Online Payment Only"),
                  ),
                  DropdownMenuItem(
                    value: "BOTH",
                    child: Text("Both (COD & Online)"),
                  ),
                ],
                isEditing: _isEditingOps,
                onChanged: (val) => setState(() => _paymentMethod = val!),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // 🤖 TAB 3: Bot Configuration
  Widget _buildBotConfigTab() {
    return _buildScrollableTab(
      child: _buildContentCard(
        title: "WhatsApp Bot Configuration",
        subtitle: "Control ordering flows and welcome media",
        isEditing: _isEditingBot,
        onEdit: () => setState(() => _isEditingBot = true),
        onCancel: () {
          setState(() => _isEditingBot = false);
          _loadProfile();
        },
        onSave: () {
          _saveSettingsToBackend({
            "primaryFlowType": _primaryFlow,
            "deliveryFlowType": _deliveryFlow,
            "welcomeVideoUrl": _videoLinkController.text.trim(),
            "welcomeVideoMediaId": _videoMediaIdController.text.trim(),
          }, () => setState(() => _isEditingBot = false));
        },
        content: Column(
          children: [
            _buildInputGrid([
              _buildDropdownField(
                label: "Primary Ordering Flow",
                icon: Icons.route_outlined,
                value: _primaryFlow,
                items: const [
                  DropdownMenuItem(
                    value: "LOCATION_FIRST",
                    child: Text("Location First Flow"),
                  ),
                  DropdownMenuItem(
                    value: "LOCATION_LAST",
                    child: Text("Location Last Flow"),
                  ),
                  DropdownMenuItem(
                    value: "ORDER_TYPE",
                    child: Text("Order Type Flow (Ask Delivery/Takeaway)"),
                  ),
                ],
                isEditing: _isEditingBot,
                onChanged: (val) {
                  setState(() {
                    _primaryFlow = val!;
                    // 🚀 CRITICAL FIX: Auto-sync deliveryFlow if it's not ORDER_TYPE
                    if (_primaryFlow != 'ORDER_TYPE') {
                      _deliveryFlow = _primaryFlow;
                    }
                  });
                },
              ),

              if (_primaryFlow == 'ORDER_TYPE')
                _buildDropdownField(
                  label: "Conditional Delivery Flow",
                  icon: Icons.alt_route_outlined,
                  value: _deliveryFlow,
                  items: const [
                    DropdownMenuItem(
                      value: "LOCATION_FIRST",
                      child: Text("Location First Flow"),
                    ),
                    DropdownMenuItem(
                      value: "LOCATION_LAST",
                      child: Text("Location Last Flow"),
                    ),
                  ],
                  isEditing: _isEditingBot,
                  onChanged: (val) => setState(() => _deliveryFlow = val!),
                )
              else
                const SizedBox(),
            ]),
            const SizedBox(height: 24),
            _buildInputField(
              "Welcome Video URL (Optional)",
              Icons.video_library_outlined,
              _videoLinkController,
              _isEditingBot,
            ),
            const SizedBox(height: 24),
            _buildInputField(
              "Welcome Video Media ID (Optional)",
              Icons.perm_media_outlined,
              _videoMediaIdController,
              _isEditingBot,
            ),
          ],
        ),
      ),
    );
  }

  // 🔌 TAB 4: API Access
  Widget _buildApiTab() {
    return _buildScrollableTab(
      child: _buildContentCard(
        title: "API Integrations",
        subtitle: "Manage connections to Meta, Razorpay, and Google Sheets",
        isEditing: _isEditingApi,
        onEdit: () => setState(() => _isEditingApi = true),
        onCancel: () {
          setState(() => _isEditingApi = false);
          _loadProfile();
        },
        onSave: () {
          _saveSettingsToBackend({
            "wabaId": _wabaIdController.text.trim(),
            "phoneNumberId": _phoneIdController.text.trim(),
            "waToken": _tokenController.text.trim(),
            "catalogId": _catalogIdController.text.trim().isEmpty
                ? "string"
                : _catalogIdController.text.trim(),
            "razorpayKeyId": _rzpKeyController.text.trim().isEmpty
                ? "string"
                : _rzpKeyController.text.trim(),
            "razorpayKeySecret": _rzpSecretController.text.trim().isEmpty
                ? "string"
                : _rzpSecretController.text.trim(),
            "razorpayWebhookSecret": _rzpWebhookController.text.trim().isEmpty
                ? "string"
                : _rzpWebhookController.text.trim(),
            "googleSheetUrl": _sheetUrlController.text.trim(),
            "googleSheetId": _sheetIdController.text.trim(),
          }, () => setState(() => _isEditingApi = false));
        },
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "WhatsApp & Meta",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 16),
            _buildInputGrid([
              _buildInputField(
                "Meta WABA ID",
                Icons.business_outlined,
                _wabaIdController,
                _isEditingApi,
              ),
              _buildInputField(
                "Phone Number ID",
                Icons.phone_iphone_outlined,
                _phoneIdController,
                _isEditingApi,
              ),
            ]),
            const SizedBox(height: 24),
            _buildInputGrid([
              _buildInputField(
                "WhatsApp Access Token",
                Icons.key_outlined,
                _tokenController,
                _isEditingApi,
              ),
              _buildInputField(
                "Meta Catalog ID",
                Icons.shopping_bag_outlined,
                _catalogIdController,
                _isEditingApi,
              ),
            ]),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Divider(height: 1, color: Color(0xFFE5E7EB)),
            ),
            const Text(
              "Razorpay Credentials",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 16),

            _buildInputGrid([
              _buildInputField(
                "Razorpay Key ID",
                Icons.payment_outlined,
                _rzpKeyController,
                _isEditingApi,
              ),
              _buildInputField(
                "Razorpay Key Secret",
                Icons.lock_outline,
                _rzpSecretController,
                _isEditingApi,
              ),
            ]),
            const SizedBox(height: 24),
            _buildInputField(
              "Razorpay Webhook Secret",
              Icons.security_outlined,
              _rzpWebhookController,
              _isEditingApi,
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Divider(height: 1, color: Color(0xFFE5E7EB)),
            ),
            const Text(
              "Google Sheets (Exporting)",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 16),

            _buildInputGrid([
              _buildInputField(
                "Google Sheet URL",
                Icons.table_chart_outlined,
                _sheetUrlController,
                _isEditingApi,
              ),
              _buildInputField(
                "Google Sheet ID",
                Icons.link_outlined,
                _sheetIdController,
                _isEditingApi,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // 🛠️ HELPER WIDGETS

  Widget _buildScrollableTab({required Widget child}) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32.0),
      child: child,
    );
  }

  Widget _buildContentCard({
    required String title,
    required String subtitle,
    required Widget content,
    required bool isEditing,
    required VoidCallback onEdit,
    required VoidCallback onCancel,
    required VoidCallback onSave,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.settings_outlined,
                      color: Color(0xFF111827),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 32),
                content,
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(), // Spacer
                if (!isEditing)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: onEdit,
                    child: const Text(
                      "Edit Settings",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF111827),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: onCancel,
                        child: const Text(
                          "Cancel",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: onSave,
                        child: const Text(
                          "Save Changes",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 24,
          runSpacing: 24,
          children: children
              .map(
                (w) => SizedBox(
                  width: constraints.maxWidth > 800
                      ? (constraints.maxWidth / 2) - 12
                      : constraints.maxWidth,
                  child: w,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildInputField(
    String label,
    IconData icon,
    TextEditingController controller,
    bool isEditing, {
    int maxLines = 1,
    bool isNumber = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF111827)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          readOnly: !isEditing,
          keyboardType: isNumber
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: TextStyle(
            fontSize: 14,
            color: Colors.black, // Dark and visible even when not editing
            fontWeight: isEditing
                ? FontWeight.w400
                : FontWeight.w600, // Bold when reading
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: isEditing ? Colors.white : const Color(0xFFF3F4F6),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: isEditing
                  ? const BorderSide(color: Color(0xFFD1D5DB))
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(
                color: Color(0xFF3B82F6),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required bool isEditing,
    required void Function(String?) onChanged,
  }) {
    if (!isEditing) {
      // 🚀 Automatically extract the exact human-readable text from the Dropdown item
      String displayString = value;
      try {
        final matchedItem = items.firstWhere((item) => item.value == value);
        displayString = (matchedItem.child as Text).data ?? value;
      } catch (e) {
        // Fallback if not found
      }
      return _buildInputField(
        label,
        icon,
        TextEditingController(text: displayString),
        false,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF111827)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF6B7280),
          ),
          style: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(
                color: Color(0xFF3B82F6),
                width: 1.5,
              ),
            ),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
