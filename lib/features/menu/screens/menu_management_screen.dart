import 'package:flutter/material.dart';
import '../../settings/services/settings_api_service.dart';
import '../../settings/services/settings_db_service.dart';
import '../services/menu_api.dart';
import '../services/menu_db.dart';
import '../widgets/menu_grid_card.dart';

class MenuManagementScreen extends StatefulWidget {
  final String restaurantId;
  const MenuManagementScreen({super.key, required this.restaurantId});

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  List<dynamic> _menu = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isReadOnly = true; 

  String _metaCatalogId = '';
  String _metaToken = '';

  String _selectedCategory = "All";
  String _searchQuery = "";

  static const Color tymTealDark = Color(0xFF096A56);
  static const Color tymSidebarBg = Color(0xFFF1F5F9);
  static const Color tymBg = Color(0xFFF8FAFC);
  static const Color tymBorder = Color(0xFFE2E8F0);
  static const Color tymTextDark = Color(0xFF0F172A);
  static const Color tymTextMuted = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _loadMenuData();
  }

  Future<void> _loadMenuData() async {
    setState(() => _isLoading = true);

    try {
      // 🚀 1. Load Settings from new SettingsDbService
      Map<String, dynamic>? settings = await SettingsDbService.instance.getSettings();

      if (settings == null) {
        settings = await SettingsApiService.instance.fetchRestaurantProfile(widget.restaurantId);
        if (settings != null) await SettingsDbService.instance.saveSettings(settings);
      }

      if (settings != null) {
        bool hasSheet = settings['googleSheetId'] != null && settings['googleSheetId'] != 'string' && settings['googleSheetId'].toString().isNotEmpty;
        bool hasCatalog = settings['catalogId'] != null && settings['catalogId'] != 'string' && settings['catalogId'].toString().isNotEmpty;

        _metaCatalogId = settings['catalogId']?.toString() ?? '';
        _metaToken = settings['waToken']?.toString() ?? '';
        _isReadOnly = hasSheet || hasCatalog;
      } else {
        _isReadOnly = true;
      }

      // 🚀 2. Read Menu directly from MenuDbService
      List<Map<String, dynamic>> localItems = await MenuDbService.instance.getAllMenuItems(widget.restaurantId);

      // 🚀 3. SEED LOGIC — backend owns the Meta pull now; Flutter just
      // triggers it and re-syncs from Mongo → SQLite.
      if (localItems.isEmpty && _metaCatalogId.isNotEmpty && _metaToken.isNotEmpty) {
        setState(() => _isSyncing = true);

        await MenuApi.instance.triggerMetaSync(widget.restaurantId, _metaCatalogId, _metaToken);
        await MenuApi.instance.syncMenuBackground(widget.restaurantId);
        localItems = await MenuDbService.instance.getAllMenuItems(widget.restaurantId);

        setState(() => _isSyncing = false);
      }

      // 🚀 4. Group items for the UI Grid
      Map<String, List<dynamic>> groupedItems = {};

      for (var item in localItems) {
        String catName = item['category']?.toString() ?? 'Uncategorized';
        if (!groupedItems.containsKey(catName)) {
          groupedItems[catName] = [];
        }
        groupedItems[catName]!.add(item);
      }

      List<dynamic> safeMenu = [];
      groupedItems.forEach((key, value) {
        safeMenu.add({"category": key, "items": value});
      });

      if (mounted) {
        setState(() {
          _menu = safeMenu;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isReadOnly = true;
          _isLoading = false;
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _triggerSync(String syncType) async {
    setState(() => _isSyncing = true);

    if (syncType == 'meta') {
      final syncedCount = await MenuApi.instance.triggerMetaSync(widget.restaurantId, _metaCatalogId, _metaToken);

      if (syncedCount != null) {
        await MenuApi.instance.syncMenuBackground(widget.restaurantId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Catalog perfectly synced from Meta!"), backgroundColor: Color(0xFF10B981)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Meta Sync Failed."), backgroundColor: Color(0xFFEF4444)),
          );
        }
      }
    }

    if (mounted) {
      setState(() => _isSyncing = false);
      _loadMenuData(); 
    }
  }

  void _handleSuccess(ScaffoldMessengerState messenger, String msg) {
    messenger.showSnackBar(
      SnackBar(
        content: Row(children: [const Icon(Icons.check_circle_rounded, color: Colors.white), const SizedBox(width: 10), Text(msg, style: const TextStyle(fontWeight: FontWeight.bold))]),
        backgroundColor: tymTealDark, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    _loadMenuData();
  }

  void _showSyncOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      backgroundColor: Colors.white,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Sync Catalog", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: tymTextDark)),
              const SizedBox(height: 8),
              const Text("Import your dishes in bulk from an external source.", style: TextStyle(fontSize: 14, color: tymTextMuted)),
              const SizedBox(height: 24),
              _buildSyncCard('meta', "WhatsApp Catalog", "Pull approved items from Meta.", Icons.storefront_rounded, const Color(0xFF10B981)),
              const SizedBox(height: 16),
              _buildSyncCard('sheet', "Google Sheets Sync", "Import rows from your spreadsheet.", Icons.table_chart_rounded, const Color(0xFF3B82F6)),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSyncCard(String type, String title, String subtitle, IconData icon, Color iconColor) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _triggerSync(type);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border.all(color: tymBorder), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: iconColor)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tymTextDark)), Text(subtitle, style: const TextStyle(fontSize: 12, color: tymTextMuted))])),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: tymTextMuted),
          ],
        ),
      ),
    );
  }

  void _deleteDialog(int catIndex, int itemIndex, String retailerId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Product"),
        content: const Text("Remove from backend and WhatsApp catalog?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);

              // Backend deletes from Mongo, then pushes the delete to Meta
              // itself (best-effort) if credentials are provided — Flutter
              // never talks to Meta directly anymore.
              await MenuApi.instance.deleteItemOnErpBackend(
                widget.restaurantId, retailerId,
                catalogId: _metaCatalogId, accessToken: _metaToken,
              );

              _handleSuccess(messenger, "Product deleted");
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _showAddDialog({String? existingCategory}) {
    List<String> catOptions = [];
    for (var group in _menu) {
      String c = group['category']?.toString() ?? '';
      if (c.isNotEmpty && c != 'All' && c != 'Unknown' && !catOptions.contains(c)) catOptions.add(c);
    }
    if (catOptions.isNotEmpty) catOptions.add("Create New...");

    String selectedCatOption = "Create New...";
    if (existingCategory != null && catOptions.contains(existingCategory)) {
      selectedCatOption = existingCategory;
    } else if (catOptions.isNotEmpty) {
      selectedCatOption = catOptions.first;
    }

    TextEditingController catCtrl = TextEditingController(text: selectedCatOption == "Create New..." ? "" : selectedCatOption);
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController priceCtrl = TextEditingController();
    TextEditingController imageCtrl = TextEditingController();
    TextEditingController linkCtrl = TextEditingController();
    bool isVeg = false;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500), padding: const EdgeInsets.all(24),
          child: StatefulBuilder(
            builder: (context, setModalState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Add Product", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)), IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context))]),
                  const SizedBox(height: 24),
                  if (catOptions.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: selectedCatOption, dropdownColor: const Color(0xFF1E293B), icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8)), style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(labelText: "Select Category", labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13), filled: true, fillColor: const Color(0xFF334155), contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5))),
                      items: catOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) {
                        setModalState(() {
                          selectedCatOption = val!;
                          catCtrl.text = val != "Create New..." ? val : "";
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (catOptions.isEmpty || selectedCatOption == "Create New...") ...[
                    _darkTextField(catCtrl, "New Category Name"), const SizedBox(height: 16),
                  ],
                  _darkTextField(nameCtrl, "Product Name"), const SizedBox(height: 16),
                  _darkTextField(priceCtrl, "Price (₹)", isNumber: true), const SizedBox(height: 16),
                  _darkTextField(imageCtrl, "Product Image URL (Cloudinary, etc.)"), const SizedBox(height: 16),
                  _darkTextField(linkCtrl, "Product Link (e.g., goldenbakery.posbytz.com)"), const SizedBox(height: 16),
                  Container(decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(6)), child: SwitchListTile(title: const Text("Vegetarian", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)), activeColor: Colors.white, activeTrackColor: const Color(0xFF10B981), value: isVeg, onChanged: (v) => setModalState(() => isVeg = v))),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), elevation: 0),
                      onPressed: () async {
                        if (catCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;

                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);

                        String newId = "tym_${DateTime.now().millisecondsSinceEpoch}";
                        double price = double.tryParse(priceCtrl.text) ?? 0;
                        String cat = catCtrl.text.trim();
                        String name = nameCtrl.text.trim();
                        String imgUrl = imageCtrl.text.trim();
                        String link = linkCtrl.text.trim();

                        await MenuApi.instance.createOrUpdateItemOnErpBackend(
                          widget.restaurantId,
                          {
                            "id": newId, "retailerId": newId, "category": cat, "name": name, "price": price, "imageUrl": imgUrl, "isVeg": isVeg,
                          },
                          catalogId: _metaCatalogId,
                          accessToken: _metaToken,
                        );

                        _handleSuccess(messenger, "Saved successfully");
                      },
                      child: const Text("Save Product", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditDialog(int catIndex, int itemIndex, Map<String, dynamic> item, String retailerId) {
    List<String> catOptions = [];
    for (var group in _menu) {
      String c = group['category']?.toString() ?? '';
      if (c.isNotEmpty && c != 'All' && c != 'Unknown' && !catOptions.contains(c)) catOptions.add(c);
    }
    if (catOptions.isNotEmpty) catOptions.add("Create New...");

    String currentCat = item['category']?.toString() ?? '';
    String selectedCatOption = "Create New...";

    if (catOptions.contains(currentCat)) {
      selectedCatOption = currentCat;
    } else if (currentCat.isNotEmpty) {
      catOptions.insert(0, currentCat); 
      selectedCatOption = currentCat;
    }

    TextEditingController catCtrl = TextEditingController(text: currentCat);
    TextEditingController nameCtrl = TextEditingController(text: item['name']?.toString() ?? item['title']?.toString() ?? '');
    TextEditingController priceCtrl = TextEditingController(text: item['price'].toString());
    TextEditingController imageCtrl = TextEditingController(text: item['imageUrl']?.toString() ?? item['image_link']?.toString() ?? '');
    TextEditingController linkCtrl = TextEditingController(text: item['productLink']?.toString() ?? item['link']?.toString() ?? '');
    bool isVeg = item['isVeg'] ?? false;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500), padding: const EdgeInsets.all(24),
          child: StatefulBuilder(
            builder: (context, setModalState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Edit Product", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)), IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context))]),
                  const SizedBox(height: 24),
                  if (catOptions.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: selectedCatOption, dropdownColor: const Color(0xFF1E293B), icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8)), style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(labelText: "Select Category", labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13), filled: true, fillColor: const Color(0xFF334155), contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5))),
                      items: catOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) {
                        setModalState(() {
                          selectedCatOption = val!;
                          catCtrl.text = val != "Create New..." ? val : "";
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (catOptions.isEmpty || selectedCatOption == "Create New...") ...[
                    _darkTextField(catCtrl, "New Category Name"), const SizedBox(height: 16),
                  ],
                  _darkTextField(nameCtrl, "Product Name"), const SizedBox(height: 16),
                  _darkTextField(priceCtrl, "Price (₹)", isNumber: true), const SizedBox(height: 16),
                  _darkTextField(imageCtrl, "Product Image URL"), const SizedBox(height: 16),
                  _darkTextField(linkCtrl, "Product Link"), const SizedBox(height: 16),
                  Container(decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(6)), child: SwitchListTile(title: const Text("Vegetarian", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)), activeColor: Colors.white, activeTrackColor: const Color(0xFF10B981), value: isVeg, onChanged: (v) => setModalState(() => isVeg = v))),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), elevation: 0),
                      onPressed: () async {
                        if (catCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;

                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);

                        double price = double.tryParse(priceCtrl.text) ?? 0;
                        String name = nameCtrl.text.trim();
                        String cat = catCtrl.text.trim();
                        String imgUrl = imageCtrl.text.trim();
                        String link = linkCtrl.text.trim();

                        setState(() {
                          item['name'] = name; item['price'] = price; item['isVeg'] = isVeg; item['category'] = cat; item['imageUrl'] = imgUrl; item['productLink'] = link;
                        });

                       await MenuApi.instance.createOrUpdateItemOnErpBackend(
                         widget.restaurantId,
                         {
                           "id": retailerId,
                           "name": name,
                           "price": price,
                           "isVeg": isVeg,
                           "category": cat,
                           "imageUrl": imgUrl,
                         },
                         catalogId: _metaCatalogId,
                         accessToken: _metaToken,
                       );

                        _handleSuccess(messenger, "Product updated");
                      },
                      child: const Text("Update Product", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _darkTextField(TextEditingController controller, String label, {bool isNumber = false}) {
    return TextField(
      controller: controller, keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white, fontSize: 14),
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13), filled: true, fillColor: const Color(0xFF334155), contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5))),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<String> categories = ["All"];
    for (var cat in _menu) {
      if (cat['category'] != null && cat['category'].toString().isNotEmpty) categories.add(cat['category'].toString());
    }

    List<Map<String, dynamic>> displayedProducts = [];
    int totalProducts = 0;

    for (int cIndex = 0; cIndex < _menu.length; cIndex++) {
      var cat = _menu[cIndex];
      String catName = cat['category'] ?? 'Unknown';
      List items = cat['items'] ?? [];
      totalProducts += items.length;

      if (_selectedCategory == "All" || _selectedCategory == catName) {
        for (int iIndex = 0; iIndex < items.length; iIndex++) {
          var item = items[iIndex];
          String itemName = (item['name']?.toString() ?? item['title']?.toString() ?? '').toLowerCase();
          if (_searchQuery.isEmpty || itemName.contains(_searchQuery.toLowerCase())) {
            displayedProducts.add({"data": item, "catIndex": cIndex, "itemIndex": iIndex, "catName": catName});
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          _isLoading ? const Center(child: CircularProgressIndicator(color: tymTealDark))
              : Row(
                  children: [
                    Container(
                      width: 240, decoration: const BoxDecoration(color: tymSidebarBg, border: Border(right: BorderSide(color: tymBorder, width: 1))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 16), child: Text("CATEGORIES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: tymTextMuted, letterSpacing: 1.2))),
                          Expanded(
                            child: ListView.builder(
                              itemCount: categories.length,
                              itemBuilder: (context, index) {
                                String cat = categories[index];
                                bool isActive = _selectedCategory == cat;
                                return InkWell(
                                  onTap: () => setState(() => _selectedCategory = cat),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    decoration: BoxDecoration(color: isActive ? tymTealDark : Colors.transparent, border: Border(bottom: BorderSide(color: isActive ? tymTealDark : tymBorder, width: 1))),
                                    child: Text(cat, style: TextStyle(color: isActive ? Colors.white : tymTextDark, fontWeight: isActive ? FontWeight.bold : FontWeight.w500, fontSize: 14)),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: tymBg,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: tymBorder))),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 48, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: tymBorder)),
                                      child: TextField(
                                        onChanged: (val) => setState(() => _searchQuery = val),
                                        decoration: const InputDecoration(hintText: "Search by name...", hintStyle: TextStyle(color: tymTextMuted, fontSize: 14), prefixIcon: Icon(Icons.search_rounded, color: tymTextMuted), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 14)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  OutlinedButton.icon(
                                    onPressed: _showSyncOptions, icon: const Icon(Icons.sync_rounded, size: 18), label: const Text("Sync Catalog"),
                                    style: OutlinedButton.styleFrom(foregroundColor: tymTextDark, side: const BorderSide(color: tymBorder), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    onPressed: () => _showAddDialog(existingCategory: _selectedCategory == "All" ? null : _selectedCategory),
                                    icon: const Icon(Icons.add_rounded, size: 18, color: tymTealDark), label: const Text("Add Items", style: TextStyle(fontWeight: FontWeight.bold, color: tymTealDark)),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD1FAE5), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFFA7F3D0)))),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("${displayedProducts.length} / $totalProducts products", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: tymTextMuted)),
                                  if (_isReadOnly) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)), child: const Text("⚠️ Read-Only Mode Active", style: TextStyle(color: Color(0xFF92400E), fontSize: 12, fontWeight: FontWeight.bold))),
                                ],
                              ),
                            ),
                            Expanded(
                              child: displayedProducts.isEmpty
                                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFFCBD5E1)), SizedBox(height: 16), Text("No products found", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tymTextDark))]))
                                  : GridView.builder(
                                      padding: const EdgeInsets.all(24),
                                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, childAspectRatio: 0.85, crossAxisSpacing: 16, mainAxisSpacing: 16),
                                      itemCount: displayedProducts.length,
                                      itemBuilder: (context, index) {
                                        var productInfo = displayedProducts[index];
                                        return MenuGridCard(
                                          item: productInfo['data'],
                                          catIndex: productInfo['catIndex'],
                                          itemIndex: productInfo['itemIndex'],
                                          onToggleAvailability: (bool newValue) async {
                                            var item = productInfo['data'];
                                            setState(() => item['isAvailable'] = newValue);

                                            String retailerId = (item['id'] ?? item['retailerId'] ?? item['retailer_id'] ?? item['retailerid'] ?? '').toString();

                                            if (retailerId.isNotEmpty) {
                                              bool success = await MenuApi.instance.updateFieldsOnErpBackend(
                                                widget.restaurantId, retailerId,
                                                {"is_available": newValue},
                                                catalogId: _metaCatalogId, accessToken: _metaToken,
                                              );

                                              if (success) {
                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(newValue ? "Marked In Stock" : "Marked Out of Stock", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: tymTealDark, behavior: SnackBarBehavior.floating));
                                              } else {
                                                setState(() => item['isAvailable'] = !newValue);
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to update WhatsApp catalog."), backgroundColor: Color(0xFFEF4444), behavior: SnackBarBehavior.floating));
                                              }
                                            }
                                          },
                                          onEdit: () {
                                            final String trueId = (productInfo['data']['id'] ?? productInfo['data']['retailerId'] ?? productInfo['data']['retailer_id'] ?? productInfo['data']['retailerid'] ?? '').toString();
                                            _showEditDialog(productInfo['catIndex'], productInfo['itemIndex'], Map<String, dynamic>.from(productInfo['data']), trueId);
                                          },
                                          onDelete: () {
                                            final String trueId = (productInfo['data']['id'] ?? productInfo['data']['retailerId'] ?? productInfo['data']['retailer_id'] ?? productInfo['data']['retailerid'] ?? '').toString();
                                            _deleteDialog(productInfo['catIndex'], productInfo['itemIndex'], trueId);
                                          },
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
          if (_isSyncing) Container(color: Colors.white.withOpacity(0.9), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [CircularProgressIndicator(color: tymTealDark), SizedBox(height: 24), Text("Syncing Catalog...", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tymTextDark))]))),
        ],
      ),
    );
  }
}