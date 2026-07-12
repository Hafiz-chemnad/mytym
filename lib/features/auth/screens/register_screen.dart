import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_api.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // 1. Basic & Location
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  // 2. Financials & Logistics
  final _gstRateController = TextEditingController();
  final _deliveryFeeController = TextEditingController();
  final _radiusController = TextEditingController();

  // 3. API & Integrations
  final _wabaIdController = TextEditingController();
  final _phoneIdController = TextEditingController();
  final _tokenController = TextEditingController();
  final _catalogIdController = TextEditingController();
  final _razorpayIdController = TextEditingController();
  final _razorpaySecretController = TextEditingController();
  final _razorpayWebhookController = TextEditingController();
  final _sheetUrlController = TextEditingController();
  final _sheetIdController = TextEditingController();

  // 4. Media
  final _videoUrlController = TextEditingController();
  final _videoMediaIdController = TextEditingController();

  // 5. Dropdown States
  String _selectedService = "DELIVERY";
  String _selectedPayment = "BOTH";
  String _primaryFlow = "LOCATION_FIRST";
  String _deliveryFlow = "LOCATION_FIRST";

  bool _isLoading = false;

  Future<void> _register() async {
    if (_nameController.text.trim().isEmpty || _wabaIdController.text.trim().isEmpty || _phoneIdController.text.trim().isEmpty || _tokenController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Name, WABA ID, Phone ID, and Token are absolutely required!"), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final Map<String, dynamic> payload = {
        "name": _nameController.text.trim(),
        "wabaId": _wabaIdController.text.trim(),
        "phoneNumberId": _phoneIdController.text.trim(),
        "waToken": _tokenController.text.trim(),
        "razorpayKeyId": _razorpayIdController.text.trim().isEmpty ? "string" : _razorpayIdController.text.trim(),
        "razorpayKeySecret": _razorpaySecretController.text.trim().isEmpty ? "string" : _razorpaySecretController.text.trim(),
        "razorpayWebhookSecret": _razorpayWebhookController.text.trim().isEmpty ? "string" : _razorpayWebhookController.text.trim(),
        "menu": [{}],
        "address": _addressController.text.trim().isEmpty ? "string" : _addressController.text.trim(),
        "longitude": double.tryParse(_lngController.text.trim()) ?? 76.2711,
        "latitude": double.tryParse(_latController.text.trim()) ?? 10.8505,
        "gstRate": int.tryParse(_gstRateController.text.trim()) ?? 0,
        "deliveryFee": int.tryParse(_deliveryFeeController.text.trim()) ?? 0,
        "deliveryRadius": int.tryParse(_radiusController.text.trim()) ?? 5,
        "paymentAvailability": _selectedPayment,
        "serviceType": _selectedService,
        "primaryFlowType": _primaryFlow, 
        "deliveryFlowType": _deliveryFlow,
        "catalogId": _catalogIdController.text.trim().isEmpty ? "string" : _catalogIdController.text.trim(),
        "googleSheetUrl": _sheetUrlController.text.trim(),
        "googleSheetId": _sheetIdController.text.trim(),
        "welcomeVideoUrl": _videoUrlController.text.trim(),
        "welcomeVideoMediaId": _videoMediaIdController.text.trim(),
      };

      // 🚀 Use the newly extracted AuthApi
      final generatedId = await AuthApi.instance.registerRestaurant(payload);

      if (!mounted) return;

      if (generatedId != null) {
        _showSuccessDialog(generatedId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to register restaurant. Check backend logs.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Network Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog(String generatedId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Registration Successful!", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Your restaurant has been created. Save this ID to login:", style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE5E7EB))),
              child: Row(
                children: [
                  Expanded(child: SelectableText(generatedId, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF111827)))),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Color(0xFF3B82F6), size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: generatedId));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ID Copied!"), backgroundColor: Colors.green));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("Go to Login", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- 🎨 UI COMPONENTS ---

  Widget _buildContentCard({required String title, required String subtitle, required IconData icon, required Widget content}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, color: const Color(0xFF111827), size: 20), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827)))]),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
            const SizedBox(height: 32),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, {int maxLines = 1, bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF111827))),
          const SizedBox(height: 6),
          TextField(
            controller: controller, maxLines: maxLines,
            keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
            style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField(String label, String value, List<DropdownMenuItem<String>> items, void Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF111827))),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: value, icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF6B7280)),
            decoration: InputDecoration(
              filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
            ),
            items: items, onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)), onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Onboard Restaurant", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 28, color: Color(0xFF111827))),
              const SizedBox(height: 4),
              const Text("Configure the database payload required by the backend API.", style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
              const SizedBox(height: 32),

              _buildContentCard(
                title: "Basic Details & Map", subtitle: "Restaurant identity and physical location", icon: Icons.storefront_outlined,
                content: Column(
                  children: [
                    _buildInputField("Restaurant Name *", _nameController),
                    _buildInputField("Complete Address", _addressController, maxLines: 2),
                    Row(children: [Expanded(child: _buildInputField("Latitude", _latController, isNumber: true)), const SizedBox(width: 16), Expanded(child: _buildInputField("Longitude", _lngController, isNumber: true))]),
                  ],
                ),
              ),

              _buildContentCard(
                title: "Financials & Logistics", subtitle: "Fees, taxes, and service availability", icon: Icons.local_shipping_outlined,
                content: Column(
                  children: [
                    Row(children: [Expanded(child: _buildInputField("GST Rate (%)", _gstRateController, isNumber: true)), const SizedBox(width: 16), Expanded(child: _buildInputField("Delivery Fee (₹)", _deliveryFeeController, isNumber: true)), const SizedBox(width: 16), Expanded(child: _buildInputField("Delivery Radius (KM)", _radiusController, isNumber: true))]),
                    _buildDropdownField("Service Type", _selectedService, const [DropdownMenuItem(value: "DELIVERY", child: Text("Delivery Only")), DropdownMenuItem(value: "TAKEAWAY", child: Text("Takeaway Only")), DropdownMenuItem(value: "BOTH", child: Text("Delivery & Takeaway"))], (v) => setState(() => _selectedService = v!)),
                    _buildDropdownField("Payment Availability", _selectedPayment, const [DropdownMenuItem(value: "COD", child: Text("Cash on Delivery")), DropdownMenuItem(value: "ONLINE", child: Text("Online Payments")), DropdownMenuItem(value: "BOTH", child: Text("Both COD & Online"))], (v) => setState(() => _selectedPayment = v!)),
                  ],
                ),
              ),

              _buildContentCard(
                title: "Bot Ordering Flow", subtitle: "Configure how the WhatsApp bot interacts with customers", icon: Icons.smart_toy_outlined,
                content: Column(
                  children: [
                    _buildDropdownField("Primary Flow Type", _primaryFlow, const [DropdownMenuItem(value: "LOCATION_FIRST", child: Text("Location First Flow")), DropdownMenuItem(value: "LOCATION_LAST", child: Text("Location Last Flow")), DropdownMenuItem(value: "ORDER_TYPE", child: Text("Order Type Flow (Ask Delivery/Takeaway)"))], (v) => setState(() => _primaryFlow = v!)),
                    if (_primaryFlow == "ORDER_TYPE") _buildDropdownField("Delivery Flow Type (Conditional)", _deliveryFlow, const [DropdownMenuItem(value: "LOCATION_FIRST", child: Text("Location First Flow")), DropdownMenuItem(value: "LOCATION_LAST", child: Text("Location Last Flow"))], (v) => setState(() => _deliveryFlow = v!)),
                    _buildInputField("Welcome Video URL (Optional)", _videoUrlController),
                    _buildInputField("Welcome Video Media ID (Optional)", _videoMediaIdController),
                  ],
                ),
              ),

              _buildContentCard(
                title: "API Integrations", subtitle: "Meta, Razorpay, and Google Sheets connections", icon: Icons.api_outlined,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("WhatsApp & Meta", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF111827))), const SizedBox(height: 12),
                    _buildInputField("WABA ID *", _wabaIdController), _buildInputField("Phone Number ID", _phoneIdController), _buildInputField("WhatsApp Access Token *", _tokenController), _buildInputField("Meta Catalog ID", _catalogIdController),
                    const Divider(height: 40), const Text("Razorpay Credentials", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF111827))), const SizedBox(height: 12),
                    _buildInputField("Razorpay Key ID", _razorpayIdController), _buildInputField("Razorpay Key Secret", _razorpaySecretController), _buildInputField("Razorpay Webhook Secret", _razorpayWebhookController),
                    const Divider(height: 40), const Text("Google Sheets (Exporting)", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF111827))), const SizedBox(height: 12),
                    _buildInputField("Google Sheet URL", _sheetUrlController), _buildInputField("Google Sheet ID", _sheetIdController),
                  ],
                ),
              ),

              _isLoading ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6))) : Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                    onPressed: _register,
                    child: const Text("Register Restaurant to Database", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}