import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';


class MenuManagementScreen extends StatefulWidget {
  final String restaurantId;
  const MenuManagementScreen({super.key, required this.restaurantId});

  @override
  _MenuManagementScreenState createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  final ApiService _apiService = ApiService();
  final SyncService _syncService = SyncService();
  List<dynamic> _menu = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isReadOnly = false; 
  String _metaCatalogId = '';
  String _metaToken = '';
  // 🚀 Split-Pane State
  String _selectedCategory = "All";
  String _searchQuery = "";

  // 🎨 STRICT TYM ERP THEME COLORS
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

  // 🚀 UPDATED: SMART GROUPER & CSV PARSER
  Future<void> _loadMenuData() async {
    setState(() => _isLoading = true);
    
    try {
      final profile = await _apiService.fetchRestaurantProfile(widget.restaurantId);
      bool hasSheet = false;
      bool hasCatalog = false;

      if (profile != null) {
        hasSheet = profile['googleSheetId'] != null && profile['googleSheetId'] != 'string' && profile['googleSheetId'].toString().isNotEmpty;
        hasCatalog = profile['catalogId'] != null && profile['catalogId'] != 'string' && profile['catalogId'].toString().isNotEmpty;

        _metaCatalogId = profile['catalogId']?.toString() ?? '';
        _metaToken = profile['waToken']?.toString() ?? '';
      }

      final rawItems = await _apiService.fetchMenu(widget.restaurantId);

      // 🚀 SMART GROUPER (Handles both Manual Add & CSV Sync)
      List<dynamic> safeMenu = [];

      if (rawItems.isNotEmpty) {
        // If data is already grouped (has 'items' array)
        if (rawItems[0] is Map && rawItems[0].containsKey('items')) {
          safeMenu = List.from(rawItems);
        } 
        // If data is a flat list (From Google Sheets CSV / Meta Catalog)
        else {
          Map<String, List<dynamic>> groupedItems = {};
          
          for (var item in rawItems) {
            if (item is Map) {
              // 🚀 1. Checks for manual 'category', falls back to CSV 'description'
              String catName = item['category']?.toString() ?? item['description']?.toString() ?? 'Uncategorized';
              
              if (!groupedItems.containsKey(catName)) {
                groupedItems[catName] = [];
              }
              groupedItems[catName]!.add(item);
            }
          }

          // Convert map back to the format the UI expects
          groupedItems.forEach((key, value) {
            safeMenu.add({
              "category": key,
              "items": value
            });
          });
        }
      }

      if (mounted) {
        setState(() {
          _menu = safeMenu; 
          _isReadOnly = hasSheet || hasCatalog; 
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading menu data: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🚀 SYNC LOGIC
  Future<void> _triggerSync(String syncType) async {
    Navigator.pop(context); 
    setState(() => _isSyncing = true); 

    int statusCode = 500;
    if (syncType == 'meta') {
      statusCode = await _apiService.syncMetaCatalog(widget.restaurantId);
    } else if (syncType == 'sheet') {
      statusCode = await _apiService.syncGoogleSheet(widget.restaurantId);
    }

    if (mounted) {
      setState(() => _isSyncing = false);
      if (statusCode == 200 || statusCode == 201) {
        _handleSuccess(ScaffoldMessenger.of(context), "Catalog synced successfully!");
      } else if (statusCode == 400 && syncType == 'sheet') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Google Sheet not linked. Check Settings."), backgroundColor: Color(0xFFF59E0B)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sync failed. Please try again."), backgroundColor: Color(0xFFEF4444)));
      }
    }
  }

  void _handleSuccess(ScaffoldMessengerState messenger, String msg) {
    messenger.showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle_rounded, color: Colors.white), const SizedBox(width: 10), Text(msg, style: const TextStyle(fontWeight: FontWeight.bold))]),
      backgroundColor: tymTealDark, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
    _loadMenuData();
  }

  void _showSyncOptions() {
    showModalBottomSheet(
      context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), backgroundColor: Colors.white,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Sync Catalog", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: tymTextDark)),
              const SizedBox(height: 8), const Text("Import your dishes in bulk from an external source.", style: TextStyle(fontSize: 14, color: tymTextMuted)),
              const SizedBox(height: 24),
              _buildSyncCard('meta', "WhatsApp Catalog", "Pull approved items from Meta.", Icons.storefront_rounded, const Color(0xFF10B981)),
              const SizedBox(height: 16),
              _buildSyncCard('sheet', "Google Sheets Sync", "Import rows from your spreadsheet.", Icons.table_chart_rounded, const Color(0xFF3B82F6)),
              const SizedBox(height: 16),
            ],
          ),
        );
      }
    );
  }

  Widget _buildSyncCard(String type, String title, String subtitle, IconData icon, Color iconColor) {
    return InkWell(
      onTap: () => _triggerSync(type), borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: tymBorder), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: iconColor)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tymTextDark)), Text(subtitle, style: const TextStyle(fontSize: 12, color: tymTextMuted))])), const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: tymTextMuted)]),
      ),
    );
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    // Extract unique categories
    List<String> categories = ["All"];
    for (var cat in _menu) {
      if (cat['category'] != null && cat['category'].toString().isNotEmpty) {
        categories.add(cat['category'].toString());
      }
    }

    // Flatten and filter products based on selections
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
          
          // 🚀 2. Checks for manual 'name', falls back to CSV 'title' for searching
          String itemName = (item['name']?.toString() ?? item['title']?.toString() ?? '').toLowerCase();
          
          if (_searchQuery.isEmpty || itemName.contains(_searchQuery.toLowerCase())) {
            displayedProducts.add({
              "data": item,
              "catIndex": cIndex,
              "itemIndex": iIndex,
              "catName": catName
            });
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          _isLoading
            ? const Center(child: CircularProgressIndicator(color: tymTealDark))
            : Row(
                children: [
                  // 🗂️ LEFT SIDEBAR (Categories)
                  Container(
                    width: 240,
                    decoration: const BoxDecoration(
                      color: tymSidebarBg,
                      border: Border(right: BorderSide(color: tymBorder, width: 1))
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
                          child: Text("CATEGORIES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: tymTextMuted, letterSpacing: 1.2)),
                        ),
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
                                  decoration: BoxDecoration(
                                    color: isActive ? tymTealDark : Colors.transparent,
                                    border: Border(bottom: BorderSide(color: isActive ? tymTealDark : tymBorder, width: 1))
                                  ),
                                  child: Text(
                                    cat, 
                                    style: TextStyle(
                                      color: isActive ? Colors.white : tymTextDark,
                                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                      fontSize: 14
                                    )
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      ],
                    ),
                  ),

                  // 📋 RIGHT WORKSPACE (Products & Tools)
                  Expanded(
                    child: Container(
                      color: tymBg,
                      child: Column(
                        children: [
                          // Top Action Bar
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: tymBorder))),
                            child: Row(
                              children: [
                                // 🔍 Search Bar
                                Expanded(
                                  child: Container(
                                    height: 48,
                                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: tymBorder)),
                                    child: TextField(
                                      onChanged: (val) => setState(() => _searchQuery = val),
                                      decoration: const InputDecoration(
                                        hintText: "Search by name...",
                                        hintStyle: TextStyle(color: tymTextMuted, fontSize: 14),
                                        prefixIcon: Icon(Icons.search_rounded, color: tymTextMuted),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(vertical: 14)
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                
                                // 🔄 Sync Button
                                OutlinedButton.icon(
                                  onPressed: _showSyncOptions,
                                  icon: const Icon(Icons.sync_rounded, size: 18),
                                  label: const Text("Sync Catalog"),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: tymTextDark, side: const BorderSide(color: tymBorder),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // ➕ Add Items Button (Locks in Read-Only)
                                ElevatedButton.icon(
                                  onPressed: _isReadOnly ? () {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Read-Only: Edit items in Google Sheets or Meta.")));
                                  } : () => _showAddDialog(existingCategory: _selectedCategory == "All" ? null : _selectedCategory),
                                  icon: Icon(_isReadOnly ? Icons.lock_outline : Icons.add_rounded, size: 18, color: _isReadOnly ? tymTextDark : tymTealDark),
                                  label: Text("Add Items", style: TextStyle(fontWeight: FontWeight.bold, color: _isReadOnly ? tymTextDark : tymTealDark)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isReadOnly ? const Color(0xFFE2E8F0) : const Color(0xFFD1FAE5), 
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: _isReadOnly ? tymBorder : const Color(0xFFA7F3D0))),
                                  ),
                                )
                              ],
                            ),
                          ),

                          // 📊 Stats / Warning Bar
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("${displayedProducts.length} / $totalProducts products", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: tymTextMuted)),
                                if (_isReadOnly)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                                    child: const Text("⚠️ Read-Only Mode Active", style: TextStyle(color: Color(0xFF92400E), fontSize: 12, fontWeight: FontWeight.bold)),
                                  )
                              ],
                            ),
                          ),

                          // 🔲 Products Grid View
                          Expanded(
                            child: displayedProducts.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFFCBD5E1)),
                                      SizedBox(height: 16),
                                      Text("No products found", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tymTextDark)),
                                    ],
                                  ),
                                )
                              : GridView.builder(
                                  padding: const EdgeInsets.all(24),
                                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 220, 
                                    childAspectRatio: 0.85,   
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                                  itemCount: displayedProducts.length,
                                  itemBuilder: (context, index) {
                                    var productInfo = displayedProducts[index];
                                    return _buildGridProductCard(
                                      productInfo['data'], 
                                      productInfo['catIndex'], 
                                      productInfo['itemIndex']
                                    );
                                  },
                                ),
                          )
                        ],
                      ),
                    ),
                  )
                ],
              ),

          // ⏳ FULL SCREEN SYNC LOADER
          if (_isSyncing)
            Container(color: Colors.white.withOpacity(0.9), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [CircularProgressIndicator(color: tymTealDark), SizedBox(height: 24), Text("Syncing Catalog...", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tymTextDark))]))),
        ],
      ),
    );
  }

  // 🚀 THE MINIMALIST GRID CARD
// 🚀 THE UPGRADED GRID CARD (With Images!)
  Widget _buildGridProductCard(Map item, int catIndex, int itemIndex) {
    // Safely extract the image URL from your backend data
  
    String imageUrl = item['imageUrl']?.toString() ?? '';
    String itemName = (item['name']?.toString() ?? item['title']?.toString() ?? 'UNKNOWN').toUpperCase();
    String price = "₹${double.tryParse(item['price'].toString())?.toStringAsFixed(2) ?? '0.00'}";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tymBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))]
      ),
      // ClipRRect keeps the image inside the rounded corners
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 🖼️ TOP 55%: IMAGE SECTION
                Expanded(
                  flex: 55,
                  child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        // If the image link is broken, show the placeholder instead of crashing
                        errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(),
                      )
                    : _buildImagePlaceholder(),
                ),
                
                // 📝 BOTTOM 45%: DETAILS SECTION
                Expanded(
                  flex: 45,
                  child: Padding(
                    // 🤏 Reduced vertical padding slightly to fit the switch
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), 
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          itemName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: tymTextDark),
                          maxLines: 1, // 🤏 Changed to 1 line to prevent Overflow errors
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2), // 🤏 Reduced spacing
                        Text(
                          price,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: tymTealDark),
                        ),
                        
                        // 🚀 NEW: THE INSTANT STOCK TOGGLE SWITCH
                        Transform.scale(
                          scale: 0.85, // Scales the switch down slightly so it fits beautifully in the grid
                          child: Switch(
                            value: item['isAvailable'] ?? true, // Defaults to true if missing
                            activeColor: const Color(0xFF10B981), // Green when In Stock
                            
                            // Notice: We do NOT block this with _isReadOnly, because we want 
                            // them to be able to change stock even if the catalog is locked!
                            onChanged: (bool newValue) async {
                              
                              // 1. Optimistically update UI so it flips instantly
                              setState(() {
                                _menu[catIndex]['items'][itemIndex]['isAvailable'] = newValue;
                              });

                              // 2. Grab the ID value
                              String retailerId = item['id']?.toString() ?? item['retailerId']?.toString() ?? '';
                              
                              if (retailerId.isNotEmpty) {
                                
                                // 3. Hit the Meta Graph API via your SyncService
                                // 🚀 Pass the dynamically fetched ID and Token
                                bool success = await _syncService.updateStockInMeta(retailerId, newValue, _metaCatalogId, _metaToken);
                                
                                if (success) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(newValue ? "Marked In Stock" : "Marked Out of Stock", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
                                      backgroundColor: tymTealDark,
                                      behavior: SnackBarBehavior.floating,
                                    )
                                  );
                                } else {
                                  // Revert the UI if Meta fails
                                  setState(() {
                                    _menu[catIndex]['items'][itemIndex]['isAvailable'] = !newValue;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Failed to update WhatsApp catalog."), backgroundColor: Color(0xFFEF4444), behavior: SnackBarBehavior.floating)
                                  );
                                }
                              } else {
                                // Revert if there is no ID
                                setState(() {
                                  _menu[catIndex]['items'][itemIndex]['isAvailable'] = !newValue;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Item missing ID. Cannot update."), backgroundColor: Color(0xFFF59E0B), behavior: SnackBarBehavior.floating)
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            // 🛠️ Hover Tools (Hidden in Read-Only Mode)
            // Added white circle backgrounds so the icons are visible over dark images
            if (!_isReadOnly)
              Positioned(
                top: 8, right: 8,
                child: InkWell(
                  onTap: () => _showEditDialog(catIndex, itemIndex, Map<String, dynamic>.from(item)),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                    child: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF64748B)),
                  )
                ),
              ),
            if (!_isReadOnly)
              Positioned(
                top: 8, left: 8,
                child: InkWell(
                  onTap: () => _deleteDialog(catIndex, itemIndex),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                    child: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                  )
                ),
              )
          ],
        ),
      ),
    );
  
  }

  // 🖼️ HELPER: Missing Image Placeholder
  Widget _buildImagePlaceholder() {
    return Container(
      color: const Color(0xFFF1F5F9), // Very light grey background
      child: const Center(
        child: Icon(Icons.fastfood_outlined, size: 32, color: Color(0xFFCBD5E1)), // Soft grey food icon
      ),
    );
  }
  // --- MANUAL EDIT DIALOGS (Hidden in Read-Only Mode) ---
  void _deleteDialog(int catIndex, int itemIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text("Delete Product", style: TextStyle(color: tymTextDark, fontWeight: FontWeight.bold, fontSize: 18)),
        content: const Text("Are you sure you want to remove this item?", style: TextStyle(color: tymTextMuted, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: tymTextMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), elevation: 0),
            onPressed: () async {
              Navigator.pop(context);
              bool success = await _apiService.deleteMenuItem(widget.restaurantId, catIndex, itemIndex);
              if (success) _handleSuccess(ScaffoldMessenger.of(context), "Product removed");
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showAddDialog({String? existingCategory}) {
    TextEditingController catCtrl = TextEditingController(text: existingCategory ?? '');
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController priceCtrl = TextEditingController();
    bool isVeg = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existingCategory == null ? "New Category" : "Add Product", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: tymTextDark)),
              const SizedBox(height: 24),
              if (existingCategory == null) ...[_lightTextField(catCtrl, "Category Name"), const SizedBox(height: 16)],
              _lightTextField(nameCtrl, "Product Name"),
              const SizedBox(height: 16),
              _lightTextField(priceCtrl, "Price (₹)", isNumber: true),
              const SizedBox(height: 16),
              Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: tymBorder)), child: SwitchListTile(title: const Text("Vegetarian", style: TextStyle(color: tymTextDark, fontWeight: FontWeight.w600, fontSize: 14)), activeColor: Colors.white, activeTrackColor: const Color(0xFF10B981), value: isVeg, onChanged: (v) => setModalState(() => isVeg = v))),
              const SizedBox(height: 32),
              SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: tymTealDark, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), elevation: 0), onPressed: () async {
                if (catCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;
                Navigator.pop(context);
                bool success = await _apiService.addMenuItem(widget.restaurantId, {"category": catCtrl.text.trim(), "name": nameCtrl.text.trim(), "price": double.tryParse(priceCtrl.text) ?? 0, "isVeg": isVeg});
                if (success) _handleSuccess(ScaffoldMessenger.of(context), "Saved successfully");
              }, child: const Text("Save Product", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)))),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(int catIndex, int itemIndex, Map<String, dynamic> item) {
    // 🚀 Uses CSV 'title' if 'name' doesn't exist
    TextEditingController nameCtrl = TextEditingController(text: item['name']?.toString() ?? item['title']?.toString() ?? '');
    TextEditingController priceCtrl = TextEditingController(text: item['price'].toString());
    bool isVeg = item['isVeg'] ?? false;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Edit Product", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: tymTextDark)),
              const SizedBox(height: 24),
              _lightTextField(nameCtrl, "Product Name"),
              const SizedBox(height: 16),
              _lightTextField(priceCtrl, "Price (₹)", isNumber: true),
              const SizedBox(height: 16),
              Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: tymBorder)), child: SwitchListTile(title: const Text("Vegetarian", style: TextStyle(color: tymTextDark, fontWeight: FontWeight.w600, fontSize: 14)), activeColor: Colors.white, activeTrackColor: const Color(0xFF10B981), value: isVeg, onChanged: (v) => setModalState(() => isVeg = v))),
              const SizedBox(height: 32),
              SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: tymTextDark, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), elevation: 0), onPressed: () async {
                Navigator.pop(context);
                bool success = await _apiService.updateMenuItem(widget.restaurantId, catIndex, itemIndex, {"name": nameCtrl.text.trim(), "price": double.tryParse(priceCtrl.text) ?? 0, "isVeg": isVeg});
                if (success) _handleSuccess(ScaffoldMessenger.of(context), "Product updated");
              }, child: const Text("Update Product", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)))),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lightTextField(TextEditingController controller, String label, {bool isNumber = false}) {
    return TextField(
      controller: controller, keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontWeight: FontWeight.w500, color: tymTextDark, fontSize: 14),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(color: tymTextMuted, fontSize: 13), filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: tymBorder)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: tymBorder)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: tymTealDark, width: 1.5)),
      ),
    );
  }
}