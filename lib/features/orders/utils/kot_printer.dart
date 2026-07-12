import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class KotPrinter {
  static String _cleanTextForPDF(String text) {
    return text.replaceAll(
      RegExp(
        r'[\u{1F300}-\u{1F9FF}]|[\u{1F600}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]',
        unicode: true,
      ),
      '',
    );
  }

  static Future<void> printKOT({
    required Map<String, dynamic> order,
    required String formattedDate,
    required String restaurantName,
    required String restaurantAddress,
    required String Function(String rawName) resolveItemName,
  }) async {
    final pdf = pw.Document();
    
    String displayId = order['displayId'] ?? order['orderId'] ?? 'N/A';
    String customer = order['customerNumber'] ?? 'N/A';
    
    String rawNotes = order['additionalNotes'] ?? '';
    String notes = rawNotes
        .replaceAll('[ACCEPTED]', '')
        .replaceAll('[REJECTED]', '')
        .replaceAll(RegExp(r'\[DELIVERY_BOY:[^\]]*\]'), '')
        .trim();
        
    List<dynamic> items = order['items'] ?? [];

    double subTotal = 0;
    for (var item in items) {
      double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
      int qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
      subTotal += price * qty;
    }
    double orderTotal = double.tryParse(order['totalAmount']?.toString() ?? '0') ?? subTotal;

    String shortOrderNo = displayId.length > 4 ? displayId.substring(displayId.length - 4) : displayId;

    pw.TextStyle bold(double size) => pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: size);
    pw.TextStyle normal(double size) => pw.TextStyle(fontSize: size);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(restaurantName, style: bold(13), textAlign: pw.TextAlign.center),
              if (restaurantAddress.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(restaurantAddress, style: normal(8), textAlign: pw.TextAlign.center),
              ],
              pw.SizedBox(height: 6),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Order No : $shortOrderNo", style: bold(9)),
                  pw.Text("WhatsApp Order", style: bold(9)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text("Customer: +$customer", style: normal(8))],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Date & Time:", style: normal(8)),
                  pw.Text(formattedDate, style: normal(8)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(flex: 5, child: pw.Text("Item", style: bold(9))),
                  pw.SizedBox(width: 4),
                  pw.Text("Qty", style: bold(9)),
                  pw.SizedBox(width: 8),
                  pw.Text("Price", style: bold(9)),
                  pw.SizedBox(width: 8),
                  pw.Text("Amt", style: bold(9)),
                ],
              ),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              ...items.map((item) {
                double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
                int qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
                double amt = price * qty;
                String itemName = _cleanTextForPDF(resolveItemName(item['name'] ?? ''));
                
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(flex: 5, child: pw.Text(itemName, style: bold(10))),
                      pw.SizedBox(width: 4),
                      pw.SizedBox(width: 22, child: pw.Text("$qty", style: normal(10), textAlign: pw.TextAlign.right)),
                      pw.SizedBox(width: 8),
                      pw.SizedBox(width: 38, child: pw.Text(price.toStringAsFixed(2), style: normal(10), textAlign: pw.TextAlign.right)),
                      pw.SizedBox(width: 8),
                      pw.SizedBox(width: 38, child: pw.Text(amt.toStringAsFixed(2), style: normal(10), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                );
              }),

              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Sub Total", style: normal(9)),
                  pw.Text(subTotal.toStringAsFixed(2), style: normal(9)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("+GST", style: normal(9)),
                  pw.Text("0.00", style: normal(9)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Total =", style: bold(12)),
                  pw.Text(orderTotal.toStringAsFixed(2), style: bold(12)),
                ],
              ),
              pw.Divider(),

              if (notes.isNotEmpty) ...[
                pw.SizedBox(height: 6),
                pw.Text("Notes: ${_cleanTextForPDF(notes)}", style: bold(9)),
              ],

              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text("This is a Kitchen Order Ticket.\nNot a payment proof.", style: normal(7), textAlign: pw.TextAlign.center),
              ),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text("*" * 32, style: normal(7))),
              pw.SizedBox(height: 20),
            ],
          );
        },
      ),
    );
    
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'KOT_$displayId',
    );
  }
}