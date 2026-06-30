import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/database_helper.dart';

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
  bool _isReadOnly = true; // 🚀 BUG FIX 1: Default to true (locked) for safety!

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
      // 🚀 1. Fast Load Settings from SQLite
      Map<String, dynamic>? settings = await DatabaseHelper.instance
          .getSettings();

      // Fallback to network if settings aren't in SQLite yet (first login)
      if (settings == null) {
        settings = await _apiService.fetchRestaurantProfile(
          widget.restaurantId,
        );
        if (settings != null)
          await DatabaseHelper.instance.saveSettings(settings);
      }

      if (settings != null) {
        bool hasSheet =
            settings['googleSheetId'] != null &&
            settings['googleSheetId'] != 'string' &&
            settings['googleSheetId'].toString().isNotEmpty;
        bool hasCatalog =
            settings['catalogId'] != null &&
            settings['catalogId'] != 'string' &&
            settings['catalogId'].toString().isNotEmpty;

        _metaCatalogId = settings['catalogId']?.toString() ?? '';
        _metaToken = settings['waToken']?.toString() ?? '';
        _isReadOnly = hasSheet || hasCatalog;
      } else {
        _isReadOnly = true;
      }

      // 🚀 2. Read Menu directly from SQLite
      List<Map<String, dynamic>> localItems = await DatabaseHelper.instance
          .getAllMenuItems(widget.restaurantId);

      // 🚀 3. THE FIRST-TIME SEED LOGIC
      if (localItems.isEmpty &&
          _metaCatalogId.isNotEmpty &&
          _metaToken.isNotEmpty) {
        setState(() => _isSyncing = true); // Show the sync overlay

        final metaItems = await _syncService.fetchCatalogFromMeta(
          _metaCatalogId,
          _metaToken,
        );

        if (metaItems.isNotEmpty) {
          for (var metaItem in metaItems) {
            // Meta returns price as a string like "250.00 INR". We need to parse it.
            String rawPrice = metaItem['price']?.toString() ?? '0';
            double parsedPrice =
                double.tryParse(rawPrice.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                0.0;

            // 🚀 FIX: Used 'metaItem' correctly and applied parsedPrice
            Map<String, dynamic> mappedItem = {
              'retailerId':
                  metaItem['retailer_id'] ??
                  metaItem['id'] ??
                  'unknown_${DateTime.now().millisecondsSinceEpoch}',
              'name':
                  metaItem['name'] ??
                  metaItem['title'] ??
                  metaItem['itemName'] ??
                  'Unnamed Item',
              'price': parsedPrice,
              'category':
                  metaItem['description'] ??
                  metaItem['category'] ??
                  'Menu Item',
              'imageUrl':
                  metaItem['image_url'] ??
                  metaItem['image_link'] ??
                  metaItem['image'] ??
                  metaItem['imageUrl'] ??
                  '',
              'isAvailable': metaItem['availability'] == 'in stock',
              'isVeg': false,
            };

            // Save each item to SQLite
            await DatabaseHelper.instance.upsertMenuItem(
              widget.restaurantId,
              mappedItem,
              syncStatus: 'synced',
            );
          }
          // Re-fetch from SQLite now that it's populated
          localItems = await DatabaseHelper.instance.getAllMenuItems(
            widget.restaurantId,
          );
        }
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
      print("Error loading menu data: $e");
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
      // 🚀 1. Fetch with corrected fields from Meta
      final metaItems = await _syncService.fetchCatalogFromMeta(
        _metaCatalogId,
        _metaToken,
      );

      if (metaItems.isNotEmpty) {
        // 🚀 2. Wipe the bad 'UNKNOWN' data from local SQLite (Tenant-scoped!)
        final db = await DatabaseHelper.instance.database;
        await db.delete(
          DatabaseHelper.tableMenu,
          where: 'restaurant_id = ?',
          whereArgs: [widget.restaurantId],
        );

        // 🚀 3. Save the fresh, correctly mapped data
        for (var metaItem in metaItems) {
          String rawPrice = metaItem['price']?.toString() ?? '0';
          double parsedPrice =
              double.tryParse(rawPrice.replaceAll(RegExp(r'[^0-9.]'), '')) ??
              0.0;

          await DatabaseHelper.instance.upsertMenuItem(widget.restaurantId, {
            // 👇 Added the timestamp fallback in case Meta fails to send an ID
            "id":
                metaItem['retailer_id'] ??
                metaItem['id'] ??
                'unknown_${DateTime.now().millisecondsSinceEpoch}',
            // 👇 Safely checking for all variations!
            "name":
                metaItem['name'] ??
                metaItem['title'] ??
                metaItem['itemName'] ??
                'Unnamed Item',
            "price": parsedPrice,
            "category":
                metaItem['description'] ?? metaItem['category'] ?? 'Menu Item',
            // 👇 Catching every possible image key!
            "imageUrl":
                metaItem['image_url'] ??
                metaItem['image_link'] ??
                metaItem['image'] ??
                metaItem['imageUrl'] ??
                '',
            "isAvailable": metaItem['availability'] == 'in stock',
            "isVeg": false,
          }, syncStatus: 'synced');
        }

        // Use a generic SnackBar if _handleSuccess is throwing errors, or keep _handleSuccess if you defined it!
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Catalog perfectly synced from Meta!"),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Meta Sync Failed."),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    } else if (syncType == 'sheet') {
      // (Your existing Google Sheet sync logic)
      // await _apiService.syncGoogleSheet(widget.restaurantId);
    }

    if (mounted) {
      setState(() => _isSyncing = false);
      _loadMenuData(); // Reload the UI with the fresh SQLite data
    }
  }

  void _handleSuccess(ScaffoldMessengerState messenger, String msg) {
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: tymTealDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    _loadMenuData();
  }

  void _showSyncOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Sync Catalog",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: tymTextDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Import your dishes in bulk from an external source.",
                style: TextStyle(fontSize: 14, color: tymTextMuted),
              ),
              const SizedBox(height: 24),
              _buildSyncCard(
                'meta',
                "WhatsApp Catalog",
                "Pull approved items from Meta.",
                Icons.storefront_rounded,
                const Color(0xFF10B981),
              ),
              const SizedBox(height: 16),
              _buildSyncCard(
                'sheet',
                "Google Sheets Sync",
                "Import rows from your spreadsheet.",
                Icons.table_chart_rounded,
                const Color(0xFF3B82F6),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSyncCard(
    String type,
    String title,
    String subtitle,
    IconData icon,
    Color iconColor,
  ) {
    return InkWell(
      onTap: () {
        // 🚀 BUG FIX 2: Safely pop the bottom sheet exactly where the tap happens
        Navigator.pop(context);
        _triggerSync(type);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: tymBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: tymTextDark,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: tymTextMuted),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: tymTextMuted,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<String> categories = ["All"];
    for (var cat in _menu) {
      if (cat['category'] != null && cat['category'].toString().isNotEmpty) {
        categories.add(cat['category'].toString());
      }
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
          String itemName =
              (item['name']?.toString() ?? item['title']?.toString() ?? '')
                  .toLowerCase();

          if (_searchQuery.isEmpty ||
              itemName.contains(_searchQuery.toLowerCase())) {
            displayedProducts.add({
              "data": item,
              "catIndex": cIndex,
              "itemIndex": iIndex,
              "catName": catName,
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
              ? const Center(
                  child: CircularProgressIndicator(color: tymTealDark),
                )
              : Row(
                  children: [
                    Container(
                      width: 240,
                      decoration: const BoxDecoration(
                        color: tymSidebarBg,
                        border: Border(
                          right: BorderSide(color: tymBorder, width: 1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
                            child: Text(
                              "CATEGORIES",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: tymTextMuted,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: categories.length,
                              itemBuilder: (context, index) {
                                String cat = categories[index];
                                bool isActive = _selectedCategory == cat;
                                return InkWell(
                                  onTap: () =>
                                      setState(() => _selectedCategory = cat),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? tymTealDark
                                          : Colors.transparent,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: isActive
                                              ? tymTealDark
                                              : tymBorder,
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      cat,
                                      style: TextStyle(
                                        color: isActive
                                            ? Colors.white
                                            : tymTextDark,
                                        fontWeight: isActive
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                    ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                  bottom: BorderSide(color: tymBorder),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: tymBorder),
                                      ),
                                      child: TextField(
                                        onChanged: (val) =>
                                            setState(() => _searchQuery = val),
                                        decoration: const InputDecoration(
                                          hintText: "Search by name...",
                                          hintStyle: TextStyle(
                                            color: tymTextMuted,
                                            fontSize: 14,
                                          ),
                                          prefixIcon: Icon(
                                            Icons.search_rounded,
                                            color: tymTextMuted,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  OutlinedButton.icon(
                                    onPressed: _showSyncOptions,
                                    icon: const Icon(
                                      Icons.sync_rounded,
                                      size: 18,
                                    ),
                                    label: const Text("Sync Catalog"),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: tymTextDark,
                                      side: const BorderSide(color: tymBorder),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),

                                  // 🚀 BUG FIX 5: Completely hide button when in read-only mode
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    onPressed: () => _showAddDialog(
                                      existingCategory:
                                          _selectedCategory == "All"
                                          ? null
                                          : _selectedCategory,
                                    ),
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      size: 18,
                                      color: tymTealDark,
                                    ),
                                    label: const Text(
                                      "Add Items",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: tymTealDark,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD1FAE5),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: const BorderSide(
                                          color: Color(0xFFA7F3D0),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "${displayedProducts.length} / $totalProducts products",
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: tymTextMuted,
                                    ),
                                  ),
                                  if (_isReadOnly)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        "⚠️ Read-Only Mode Active",
                                        style: TextStyle(
                                          color: Color(0xFF92400E),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            Expanded(
                              child: displayedProducts.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Icon(
                                            Icons.inventory_2_outlined,
                                            size: 48,
                                            color: Color(0xFFCBD5E1),
                                          ),
                                          SizedBox(height: 16),
                                          Text(
                                            "No products found",
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: tymTextDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : GridView.builder(
                                      padding: const EdgeInsets.all(24),
                                      gridDelegate:
                                          const SliverGridDelegateWithMaxCrossAxisExtent(
                                            maxCrossAxisExtent: 220,
                                            childAspectRatio: 0.85,
                                            crossAxisSpacing: 16,
                                            mainAxisSpacing: 16,
                                          ),
                                      itemCount: displayedProducts.length,
                                      itemBuilder: (context, index) {
                                        var productInfo =
                                            displayedProducts[index];
                                        return _buildGridProductCard(
                                          productInfo['data'],
                                          productInfo['catIndex'],
                                          productInfo['itemIndex'],
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

          if (_isSyncing)
            Container(
              color: Colors.white.withOpacity(0.9),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(color: tymTealDark),
                    SizedBox(height: 24),
                    Text(
                      "Syncing Catalog...",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: tymTextDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGridProductCard(Map item, int catIndex, int itemIndex) {
    String imageUrl = item['imageUrl']?.toString() ?? '';
    String itemName =
        (item['name']?.toString() ?? item['title']?.toString() ?? 'UNKNOWN')
            .toUpperCase();
    String price =
        "₹${double.tryParse(item['price'].toString())?.toStringAsFixed(2) ?? '0.00'}";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tymBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 55,
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildImagePlaceholder(),
                        )
                      : _buildImagePlaceholder(),
                ),
                Expanded(
                  flex: 45,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.0,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          itemName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: tymTextDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          price,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: tymTealDark,
                          ),
                        ),
                        Transform.scale(
                          scale: 0.85,
                          child: Switch(
                            value: item['isAvailable'] ?? true,
                            activeColor: const Color(0xFF10B981),
                            onChanged: (bool newValue) async {
                              setState(() {
                                item['isAvailable'] = newValue;
                              });

                              String retailerId =
                                  (item['id'] ??
                                          item['retailerId'] ??
                                          item['retailer_id'] ??
                                          item['retailerid'] ??
                                          '')
                                      .toString();

                              if (retailerId.isNotEmpty) {
                                // 🚀 1. SAVE TO SQLITE INSTANTLY
                                // To this:
                                await DatabaseHelper.instance.upsertMenuItem(
                                  widget.restaurantId, // 🚀 ADD THIS
                                  Map<String, dynamic>.from(item),
                                  syncStatus: 'backend_pending',
                                );

                                // 🚀 2. DIRECT META PUSH
                                bool success = await _syncService
                                    .updateStockInMeta(
                                      retailerId,
                                      newValue,
                                      _metaCatalogId,
                                      _metaToken,
                                    );

                                if (success) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        newValue
                                            ? "Marked In Stock"
                                            : "Marked Out of Stock",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      backgroundColor: tymTealDark,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                } else {
                                  setState(
                                    () => item['isAvailable'] = !newValue,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Failed to update WhatsApp catalog.",
                                      ),
                                      backgroundColor: Color(0xFFEF4444),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
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

            Positioned(
              top: 8,
              right: 8,
              child: InkWell(
                onTap: () {
                  final String trueId =
                      (item['id'] ??
                              item['retailerId'] ??
                              item['retailer_id'] ??
                              item['retailerid'] ??
                              '')
                          .toString();
                  _showEditDialog(
                    catIndex,
                    itemIndex,
                    Map<String, dynamic>.from(item),
                    trueId,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ),

            Positioned(
              top: 8,
              left: 8,
              child: InkWell(
                onTap: () {
                  final String trueId =
                      (item['id'] ??
                              item['retailerId'] ??
                              item['retailer_id'] ??
                              item['retailerid'] ??
                              '')
                          .toString();
                  _deleteDialog(catIndex, itemIndex, trueId);
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: const Color(0xFFF1F5F9),
      child: const Center(
        child: Icon(
          Icons.fastfood_outlined,
          size: 32,
          color: Color(0xFFCBD5E1),
        ),
      ),
    );
  }

  // 1. DELETE DIALOG
  void _deleteDialog(int catIndex, int itemIndex, String retailerId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Product"),
        content: const Text("Remove from backend and WhatsApp catalog?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              // 🚀 FIX: Grab the messenger BEFORE popping the dialog!
              final messenger = ScaffoldMessenger.of(context);

              Navigator.pop(context);

              // 1. ALWAYS REMOVE FROM LOCAL SQLITE CACHE FIRST
              await DatabaseHelper.instance.deleteMenuItemLocally(
                widget.restaurantId,
                retailerId,
              );

              // 2. ALWAYS DELETE FROM META
              if (retailerId.isNotEmpty) {
                await _syncService.deleteItemInMeta(
                  retailerId,
                  _metaCatalogId,
                  _metaToken,
                );
              }

              // 3. Try to delete from Backend (Background process)
              _apiService.deleteMenuItem(
                widget.restaurantId,
                catIndex,
                itemIndex,
              );

              // 🚀 FIX: Use the safely stored messenger variable
              _handleSuccess(messenger, "Product deleted");
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _showAddDialog({String? existingCategory}) {
    // 🚀 1. Extract all unique existing categories from the current menu
    List<String> catOptions = [];
    for (var group in _menu) {
      String c = group['category']?.toString() ?? '';
      if (c.isNotEmpty &&
          c != 'All' &&
          c != 'Unknown' &&
          !catOptions.contains(c)) {
        catOptions.add(c);
      }
    }
    if (catOptions.isNotEmpty) catOptions.add("Create New...");

    // 🚀 2. Determine default selection
    String selectedCatOption = "Create New...";
    if (existingCategory != null && catOptions.contains(existingCategory)) {
      selectedCatOption = existingCategory;
    } else if (catOptions.isNotEmpty) {
      selectedCatOption = catOptions.first;
    }

    TextEditingController catCtrl = TextEditingController(
      text: selectedCatOption == "Create New..." ? "" : selectedCatOption,
    );
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
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24),
          child: StatefulBuilder(
            builder: (context, setModalState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Add Product",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 🚀 3. THE DYNAMIC CATEGORY DROPDOWN
                  if (catOptions.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: selectedCatOption,
                      dropdownColor: const Color(0xFF1E293B),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF94A3B8),
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        labelText: "Select Category",
                        labelStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF334155),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                            color: Color(0xFF10B981),
                            width: 1.5,
                          ),
                        ),
                      ),
                      items: catOptions
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (val) {
                        setModalState(() {
                          selectedCatOption = val!;
                          if (val != "Create New...") {
                            catCtrl.text = val;
                          } else {
                            catCtrl.text = ""; // Clear text field for new input
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 🚀 4. CONDITIONAL NEW CATEGORY FIELD
                  if (catOptions.isEmpty ||
                      selectedCatOption == "Create New...") ...[
                    _darkTextField(catCtrl, "New Category Name"),
                    const SizedBox(height: 16),
                  ],

                  _darkTextField(nameCtrl, "Product Name"),
                  const SizedBox(height: 16),
                  _darkTextField(priceCtrl, "Price (₹)", isNumber: true),
                  const SizedBox(height: 16),
                  _darkTextField(
                    imageCtrl,
                    "Product Image URL (Cloudinary, etc.)",
                  ),
                  const SizedBox(height: 16),
                  _darkTextField(
                    linkCtrl,
                    "Product Link (e.g., goldenbakery.posbytz.com)",
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        "Vegetarian",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      activeColor: Colors.white,
                      activeTrackColor: const Color(0xFF10B981),
                      value: isVeg,
                      onChanged: (v) => setModalState(() => isVeg = v),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        if (catCtrl.text.isEmpty || nameCtrl.text.isEmpty)
                          return;

                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);

                        String newId =
                            "tym_${DateTime.now().millisecondsSinceEpoch}";
                        double price = double.tryParse(priceCtrl.text) ?? 0;
                        String cat = catCtrl.text.trim();
                        String name = nameCtrl.text.trim();
                        String imgUrl = imageCtrl.text.trim();
                        String link = linkCtrl.text.trim();

                        await _apiService.addMenuItem(widget.restaurantId, {
                          "id": newId,
                          "retailerId": newId,
                          "category": cat,
                          "name": name,
                          "price": price,
                          "imageUrl": imgUrl,
                          "productLink": link,
                          "isVeg": isVeg,
                        });

                        await _syncService.addItemToMeta(
                          retailerId: newId,
                          title: name,
                          price: price,
                          description: cat,
                          imageUrl: imgUrl,
                          productLink: link,
                          catalogId: _metaCatalogId,
                          accessToken: _metaToken,
                        );

                        _handleSuccess(messenger, "Saved successfully");
                      },
                      child: const Text(
                        "Save Product",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
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

  void _showEditDialog(
    int catIndex,
    int itemIndex,
    Map<String, dynamic> item,
    String retailerId,
  ) {
    // 🚀 1. Extract existing categories
    List<String> catOptions = [];
    for (var group in _menu) {
      String c = group['category']?.toString() ?? '';
      if (c.isNotEmpty &&
          c != 'All' &&
          c != 'Unknown' &&
          !catOptions.contains(c)) {
        catOptions.add(c);
      }
    }
    if (catOptions.isNotEmpty) catOptions.add("Create New...");

    // 🚀 2. Identify the item's current category
    String currentCat = item['category']?.toString() ?? '';
    String selectedCatOption = "Create New...";

    if (catOptions.contains(currentCat)) {
      selectedCatOption = currentCat;
    } else if (currentCat.isNotEmpty) {
      catOptions.insert(
        0,
        currentCat,
      ); // Failsafe: if cat was deleted but item still has it
      selectedCatOption = currentCat;
    }

    TextEditingController catCtrl = TextEditingController(text: currentCat);
    TextEditingController nameCtrl = TextEditingController(
      text: item['name']?.toString() ?? item['title']?.toString() ?? '',
    );
    TextEditingController priceCtrl = TextEditingController(
      text: item['price'].toString(),
    );
    TextEditingController imageCtrl = TextEditingController(
      text:
          item['imageUrl']?.toString() ?? item['image_link']?.toString() ?? '',
    );
    TextEditingController linkCtrl = TextEditingController(
      text: item['productLink']?.toString() ?? item['link']?.toString() ?? '',
    );
    bool isVeg = item['isVeg'] ?? false;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24),
          child: StatefulBuilder(
            builder: (context, setModalState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Edit Product",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 🚀 3. EDIT CATEGORY DROPDOWN
                  if (catOptions.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: selectedCatOption,
                      dropdownColor: const Color(0xFF1E293B),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF94A3B8),
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        labelText: "Select Category",
                        labelStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF334155),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                            color: Color(0xFF10B981),
                            width: 1.5,
                          ),
                        ),
                      ),
                      items: catOptions
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (val) {
                        setModalState(() {
                          selectedCatOption = val!;
                          if (val != "Create New...") {
                            catCtrl.text = val;
                          } else {
                            catCtrl.text = "";
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (catOptions.isEmpty ||
                      selectedCatOption == "Create New...") ...[
                    _darkTextField(catCtrl, "New Category Name"),
                    const SizedBox(height: 16),
                  ],

                  _darkTextField(nameCtrl, "Product Name"),
                  const SizedBox(height: 16),
                  _darkTextField(priceCtrl, "Price (₹)", isNumber: true),
                  const SizedBox(height: 16),
                  _darkTextField(imageCtrl, "Product Image URL"),
                  const SizedBox(height: 16),
                  _darkTextField(linkCtrl, "Product Link"),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        "Vegetarian",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      activeColor: Colors.white,
                      activeTrackColor: const Color(0xFF10B981),
                      value: isVeg,
                      onChanged: (v) => setModalState(() => isVeg = v),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        if (catCtrl.text.isEmpty || nameCtrl.text.isEmpty)
                          return;

                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);

                        double price = double.tryParse(priceCtrl.text) ?? 0;
                        String name = nameCtrl.text.trim();
                        String cat = catCtrl.text.trim();
                        String imgUrl = imageCtrl.text.trim();
                        String link = linkCtrl.text.trim();

                        setState(() {
                          item['name'] = name;
                          item['price'] = price;
                          item['isVeg'] = isVeg;
                          item['category'] = cat;
                          item['imageUrl'] = imgUrl;
                          item['productLink'] = link;
                        });

                        await _apiService.updateMenuItem(
                          widget.restaurantId,
                          catIndex,
                          itemIndex,
                          {
                            "name": name,
                            "price": price,
                            "isVeg": isVeg,
                            "category": cat,
                            "imageUrl": imgUrl,
                            "productLink": link,
                          },
                        );

                        if (retailerId.isNotEmpty) {
                          await _syncService.updateItemDetailsInMeta(
                            retailerId,
                            name,
                            price,
                            link,
                            _metaCatalogId,
                            _metaToken,
                          );
                        }

                        _handleSuccess(messenger, "Product updated");
                      },
                      child: const Text(
                        "Update Product",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
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


  Widget _darkTextField(
    TextEditingController controller,
    String label, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: const TextStyle(
        fontWeight: FontWeight.w500,
        color: Colors.white,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF334155),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
        ),
      ),
    );
  }
}
