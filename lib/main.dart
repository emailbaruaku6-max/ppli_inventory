import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// URL Web App Google Apps Script Terbaru milikmu
const String webAppUrl = "https://script.google.com/macros/s/AKfycbzTpay1CWqmkOlubPoC3SQsqRB5ZESepAJM2Drew6d2RdaVabpgDh-_jOmEl0QniS6eUA/exec";

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: WarehouseApp(),
    ));

class WarehouseApp extends StatefulWidget {
  @override
  _WarehouseAppState createState() => _WarehouseAppState();
}

class _WarehouseAppState extends State<WarehouseApp> with TickerProviderStateMixin {
  late AnimationController _liveAnimCtrl;
  late AnimationController _blinkAnimCtrl;
  late AnimationController _refreshAnimCtrl;
  late Animation<double> _blinkAnimation;
  
  bool isLoading = true;
  List<String> history = [];

  final List<String> daftarTujuan = [
    "- Pilih Tujuan -",
    "6033",
    "6036",
    "6037",
    "6042",
    "Arpro",
    "HMP Truck",
    "SEGREGASI",
    "Single Cabin"
  ];

  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    _liveAnimCtrl = AnimationController(vsync: this, duration: Duration(milliseconds: 800))..repeat(reverse: true);
    _blinkAnimCtrl = AnimationController(vsync: this, duration: Duration(milliseconds: 500))..repeat(reverse: true);
    _blinkAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(_blinkAnimCtrl);
    _refreshAnimCtrl = AnimationController(vsync: this, duration: Duration(milliseconds: 1000));

    fetchDataFromSheets();
  }

  @override
  void dispose() {
    _liveAnimCtrl.dispose();
    _blinkAnimCtrl.dispose();
    _refreshAnimCtrl.dispose();
    super.dispose();
  }

  // 1. LOAD DATA STOK DAN RIWAYAT DARI GOOGLE SHEETS
  Future<void> fetchDataFromSheets() async {
    _refreshAnimCtrl.repeat();
    setState(() => isLoading = true);

    try {
      final response = await http.get(Uri.parse(webAppUrl));
      if (response.statusCode == 200) {
        var resData = jsonDecode(response.body);

        List<dynamic> rawStok = resData['stok'] ?? [];
        List<Map<String, dynamic>> loadedItems = [];

        for (int i = 1; i < rawStok.length; i++) {
          if (rawStok[i][0].toString().trim().isNotEmpty) {
            String name = rawStok[i][0].toString().toUpperCase();
            int stock = int.tryParse(rawStok[i][1].toString()) ?? 0;
            loadedItems.add({
              "name": name,
              "stock": stock,
              "ctrl": TextEditingController(text: "1"),
              "tujuan": "- Pilih Tujuan -",
            });
          }
        }

        List<dynamic> rawRiwayat = resData['riwayat'] ?? [];
        List<String> loadedHistory = [];

        for (int i = 1; i < rawRiwayat.length; i++) {
          var r = rawRiwayat[i];
          if (r.length >= 6 && r[0].toString().trim().isNotEmpty) {
            String tgl = r[0].toString();
            String jam = r[1].toString();
            String namaBarang = r[2].toString();
            String aksi = r[3].toString();
            String qty = r[4].toString();
            String tujuan = r[5].toString();

            if (jam.contains("T")) {
              try {
                DateTime parsed = DateTime.parse(jam);
                jam = DateFormat('HH:mm').format(parsed.toLocal());
              } catch (_) {
                jam = "00:00";
              }
            } else if (jam.length >= 5) {
              jam = jam.substring(0, 5);
            }

            if (tgl.contains("T")) {
              try {
                DateTime parsed = DateTime.parse(tgl);
                tgl = DateFormat('dd/MM/yyyy').format(parsed.toLocal());
              } catch (_) {}
            }

            loadedHistory.insert(0, "$tgl|$jam|$aksi|$qty|$namaBarang|$tujuan");
          }
        }

        setState(() {
          items = loadedItems;
          history = loadedHistory;
          isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✓ Data berhasil disinkronkan dari Google Sheets"), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal memuat data dari Google Sheets!")),
      );
    } finally {
      _refreshAnimCtrl.stop();
      _refreshAnimCtrl.reset();
    }
  }

  // 2. TAMBAH ITEM BARU
  Future<void> tambahItemBaru(String namaItem) async {
    if (namaItem.trim().isEmpty) return;
    String cleanName = namaItem.trim().toUpperCase();

    setState(() {
      items.add({
        "name": cleanName,
        "stock": 0,
        "ctrl": TextEditingController(text: "1"),
        "tujuan": "- Pilih Tujuan -",
      });
    });

    try {
      await http.post(
        Uri.parse(webAppUrl),
        body: jsonEncode({
          "action": "addItem",
          "itemName": cleanName
        }),
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✓ Item '$cleanName' tersimpan!")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menambah item ke Sheets.")));
      fetchDataFromSheets();
    }
  }

  // 3. HAPUS ITEM (SWIPE TO DELETE)
  Future<void> hapusItem(String namaItem) async {
    setState(() {
      items.removeWhere((i) => i['name'] == namaItem);
    });

    try {
      await http.post(
        Uri.parse(webAppUrl),
        body: jsonEncode({
          "action": "deleteItem",
          "itemName": namaItem
        }),
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✓ Item '$namaItem' berhasil dihapus")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menghapus item dari Sheets")));
      fetchDataFromSheets();
    }
  }

  // 4. UPDATE STOK (OPTIMISTIC UI)
  Future<void> prosesUpdate(Map item, int operasi) async {
    if (operasi == -1 && item['tujuan'] == "- Pilih Tujuan -") {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ Pilih Tujuan Resmi terlebih dahulu!")));
      return;
    }

    int qty = int.tryParse(item['ctrl'].text) ?? 0;
    if (qty <= 0) return;

    if (operasi == -1 && item['stock'] < qty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ Stok tidak mencukupi!")));
      return;
    }

    int stokLama = item['stock'];
    int stokBaru = stokLama + (operasi * qty);
    String targetTujuan = operasi == 1 ? "Gudang" : item['tujuan'];
    String aksiStr = operasi == 1 ? "Masuk" : "Keluar";

    setState(() {
      item['stock'] = stokBaru;
      String tglNow = DateFormat('dd/MM/yyyy').format(DateTime.now());
      String jamNow = DateFormat('HH:mm').format(DateTime.now());
      history.insert(0, "$tglNow|$jamNow|$aksiStr|$qty|${item['name']}|$targetTujuan");
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✓ Stok ${item['name']} diperbarui ($aksiStr $qty)"), duration: Duration(milliseconds: 800)),
    );

    try {
      await http.post(
        Uri.parse(webAppUrl),
        body: jsonEncode({
          "item": item['name'],
          "stock": stokBaru,
          "operasi": operasi,
          "qty": qty,
          "tujuan": targetTujuan,
        }),
      );
    } catch (e) {
      setState(() {
        item['stock'] = stokLama;
        if(history.isNotEmpty) history.removeAt(0);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Gagal sinkron ke Sheets. Perubahan dibatalkan.")));
    }
  }

  // DIALOG REKAP BULANAN
  void showRekapBulananDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RekapBulananSheet(history: history),
    );
  }

  void showHapusRiwayatDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Bersihkan Tampilan Log"),
        content: Text("Apakah Anda yakin ingin mengosongkan riwayat di layar aplikasi? (Data di Google Sheets tetap aman)"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => history.clear());
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Tampilan riwayat dibersihkan!")));
            },
            child: Text("Hapus Log", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void showTambahDialog() {
    TextEditingController _namaCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Tambah Item Baru"),
        content: TextField(
          controller: _namaCtrl,
          decoration: InputDecoration(hintText: "Nama barang (misal: PALET KAYU)"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Batal")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              tambahItemBaru(_namaCtrl.text);
            },
            child: Text("Simpan"),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String count, Color iconColor, IconData icon) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: iconColor),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 3),
            Text(
              count,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalItems = items.length;
    int criticalItems = items.where((i) => i['stock'] < 500).length;
    int safeItems = totalItems - criticalItems;

    return Scaffold(
      backgroundColor: Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          children: [
            // Header Gradient & Dashboard
            Container(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F5132), Color(0xFF198754), Color(0xFF0D6EFD)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: Offset(0, 4))
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "PPLi MANYAR SMELTER",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white, letterSpacing: 0.5),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Monitoring Stok Gudang Realtime",
                            style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // TOMBOL REKAP BULANAN 📊
                          IconButton(
                            icon: Icon(Icons.bar_chart_rounded, color: Colors.white, size: 24),
                            tooltip: "Rekap Pemakaian Bulanan",
                            onPressed: showRekapBulananDialog,
                          ),
                          RotationTransition(
                            turns: Tween(begin: 0.0, end: 1.0).animate(_refreshAnimCtrl),
                            child: IconButton(
                              icon: Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
                              tooltip: "Refresh Data",
                              onPressed: fetchDataFromSheets,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.add_circle, color: Colors.white, size: 24),
                            tooltip: "Tambah Item",
                            onPressed: showTambahDialog,
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      _buildSummaryCard("TOTAL ITEM", "$totalItems", Colors.blue[700]!, Icons.inventory_2_outlined),
                      SizedBox(width: 8),
                      _buildSummaryCard("STOK AMAN", "$safeItems", Colors.green[700]!, Icons.check_circle_outline),
                      SizedBox(width: 8),
                      _buildSummaryCard("KRITIS (<500)", "$criticalItems", Colors.red[600]!, Icons.warning_amber_rounded),
                    ],
                  ),
                ],
              ),
            ),

            // Daftar Item Card (Swipe to Delete)
            Expanded(
              flex: 3,
              child: isLoading
                  ? Center(child: CircularProgressIndicator(color: Colors.teal))
                  : RefreshIndicator(
                      color: Color(0xFF0F5132),
                      backgroundColor: Colors.white,
                      onRefresh: fetchDataFromSheets,
                      child: items.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(height: 100),
                                Center(child: Text("Belum ada data item di Sheets.")),
                              ],
                            )
                          : ListView.builder(
                              itemCount: items.length,
                              padding: EdgeInsets.fromLTRB(10, 10, 10, 4),
                              itemBuilder: (context, i) {
                                var item = items[i];
                                bool isStockLow = item['stock'] < 500;

                                return Dismissible(
                                  key: Key(item['name']),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (direction) async {
                                    return await showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text("Konfirmasi Hapus"),
                                        content: Text("Yakin ingin menghapus item '${item['name']}' dari daftar?"),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Batal")),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: Text("Hapus", style: TextStyle(color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  onDismissed: (direction) => hapusItem(item['name']),
                                  background: Container(
                                    margin: EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    alignment: Alignment.centerRight,
                                    padding: EdgeInsets.only(right: 20),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text("Hapus", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        SizedBox(width: 8),
                                        Icon(Icons.delete, color: Colors.white),
                                      ],
                                    ),
                                  ),
                                  child: Container(
                                    margin: EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.03),
                                          blurRadius: 6,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Column(
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                item['name'],
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
                                              ),
                                              isStockLow
                                                  ? FadeTransition(
                                                      opacity: _blinkAnimation,
                                                      child: Container(
                                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.red[50],
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border.all(color: Colors.red.shade200),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.warning_amber_rounded, color: Colors.red[700], size: 10),
                                                            SizedBox(width: 3),
                                                            Text(
                                                              "KRITIS: ${item['stock']}",
                                                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red[700]),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    )
                                                  : Container(
                                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green[50],
                                                        borderRadius: BorderRadius.circular(10),
                                                        border: Border.all(color: Colors.green.shade200),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.check_circle_outline, color: Colors.green[700], size: 10),
                                                          SizedBox(width: 3),
                                                          Text(
                                                            "STOK: ${item['stock']}",
                                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green[800]),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                            ],
                                          ),
                                          SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Container(
                                                  height: 30,
                                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[100],
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: Colors.grey.shade300),
                                                  ),
                                                  child: DropdownButtonHideUnderline(
                                                    child: DropdownButton<String>(
                                                      value: item['tujuan'],
                                                      isExpanded: true,
                                                      style: TextStyle(fontSize: 9, color: Colors.black87),
                                                      items: daftarTujuan.map((s) {
                                                        return DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis));
                                                      }).toList(),
                                                      onChanged: (v) => setState(() => item['tujuan'] = v!),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 6),
                                              Container(
                                                width: 48,
                                                height: 30,
                                                child: TextField(
                                                  controller: item['ctrl'],
                                                  keyboardType: TextInputType.number,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                                  decoration: InputDecoration(
                                                    contentPadding: EdgeInsets.zero,
                                                    filled: true,
                                                    fillColor: Colors.grey[100],
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 6),
                                              Row(
                                                children: [
                                                  Material(
                                                    color: Colors.red[50],
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: InkWell(
                                                      borderRadius: BorderRadius.circular(8),
                                                      onTap: () => prosesUpdate(item, -1),
                                                      child: Padding(
                                                        padding: EdgeInsets.all(5),
                                                        child: Icon(Icons.remove, color: Colors.red[600], size: 18),
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Material(
                                                    color: Colors.green[50],
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: InkWell(
                                                      borderRadius: BorderRadius.circular(8),
                                                      onTap: () => prosesUpdate(item, 1),
                                                      child: Padding(
                                                        padding: EdgeInsets.all(5),
                                                        child: Icon(Icons.add, color: Colors.green[700], size: 18),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),

            // Panel Riwayat Aktivitas
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: Offset(0, -2))
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(14, 6, 14, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.history, size: 16, color: Colors.blueGrey[700]),
                            SizedBox(width: 6),
                            Text(
                              "RIWAYAT AKTIVITAS",
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey[800], letterSpacing: 0.5),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)),
                              child: Text(
                                "${history.length} Log",
                                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                              ),
                            ),
                            SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.red[600]),
                              tooltip: "Bersihkan Tampilan Log",
                              onPressed: history.isEmpty ? null : showHapusRiwayatDialog,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                ],
              ),
            ),

            // Content List Riwayat
            Expanded(
              flex: 1,
              child: Container(
                color: Colors.white,
                child: history.isEmpty
                    ? Center(
                        child: Text(
                          "Belum ada aktivitas transaksi.",
                          style: TextStyle(fontSize: 10, color: Colors.grey[400], fontStyle: FontStyle.italic),
                        ),
                      )
                    : ListView.builder(
                        itemCount: history.length,
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        itemBuilder: (context, i) {
                          var p = history[i].split('|');
                          bool isMasuk = p[2] == "Masuk";

                          return Container(
                            margin: EdgeInsets.symmetric(vertical: 3),
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isMasuk ? Colors.green[50]?.withValues(alpha: 0.5) : Colors.red[50]?.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isMasuk ? Colors.green.shade200 : Colors.red.shade200,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: isMasuk ? Colors.green[100] : Colors.red[100],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isMasuk ? Icons.south_west : Icons.north_east,
                                    size: 12,
                                    color: isMasuk ? Colors.green[800] : Colors.red[800],
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p[4],
                                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black87),
                                      ),
                                      SizedBox(height: 1),
                                      Text(
                                        "${p[2]} (${p[3]} Qty) → ${p[5]}",
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w600,
                                          color: isMasuk ? Colors.green[800] : Colors.red[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Text(
                                    "${p[0]} ${p[1]}",
                                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// WIDGET REKAP BULANAN PER TUJUAN & PER ITEM (DUA SECTION)
// =========================================================================
class RekapBulananSheet extends StatefulWidget {
  final List<String> history;
  RekapBulananSheet({required this.history});

  @override
  _RekapBulananSheetState createState() => _RekapBulananSheetState();
}

class _RekapBulananSheetState extends State<RekapBulananSheet> {
  String selectedMonthYear = DateFormat('MM/yyyy').format(DateTime.now());
  List<String> availableMonths = [];

  @override
  void initState() {
    super.initState();
    generateAvailableMonths();
  }

  void generateAvailableMonths() {
    Set<String> months = {};
    String nowMY = DateFormat('MM/yyyy').format(DateTime.now());
    months.add(nowMY);

    for (String h in widget.history) {
      var p = h.split('|');
      if (p.isNotEmpty) {
        String tgl = p[0];
        var parts = tgl.split('/');
        if (parts.length == 3) {
          months.add("${parts[1]}/${parts[2]}");
        } else if (parts.length == 2) {
          months.add("${parts[1]}/${DateTime.now().year}");
        }
      }
    }

    availableMonths = months.toList();
    if (!availableMonths.contains(selectedMonthYear)) {
      selectedMonthYear = availableMonths.first;
    }
  }

  String formatMonthName(String my) {
    try {
      var p = my.split('/');
      int m = int.parse(p[0]);
      int y = int.parse(p[1]);
      List<String> namaBulan = [
        "", "Januari", "Februari", "Maret", "April", "Mei", "Juni",
        "Juli", "Agustus", "September", "Oktober", "November", "Desember"
      ];
      return "${namaBulan[m]} $y";
    } catch (_) {
      return my;
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, Map<String, int>> rekapTujuan = {};
    Map<String, int> rekapTotalItem = {};
    int grandTotalKeluar = 0;

    for (String h in widget.history) {
      var p = h.split('|');
      if (p.length >= 6) {
        String tgl = p[0];
        String aksi = p[2];
        int qty = int.tryParse(p[3]) ?? 0;
        String namaBarang = p[4];
        String tujuan = p[5];

        if (aksi == "Keluar") {
          String my = "";
          var parts = tgl.split('/');
          if (parts.length == 3) {
            my = "${parts[1]}/${parts[2]}";
          } else if (parts.length == 2) {
            my = "${parts[1]}/${DateTime.now().year}";
          }

          if (my == selectedMonthYear) {
            grandTotalKeluar += qty;

            if (!rekapTujuan.containsKey(tujuan)) {
              rekapTujuan[tujuan] = {};
            }
            rekapTujuan[tujuan]![namaBarang] = (rekapTujuan[tujuan]![namaBarang] ?? 0) + qty;

            rekapTotalItem[namaBarang] = (rekapTotalItem[namaBarang] ?? 0) + qty;
          }
        }
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.bar_chart_rounded, color: Color(0xFF0F5132)),
                    SizedBox(width: 8),
                    Text(
                      "REKAP PEMAKAIAN",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey[900]),
                    ),
                  ],
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.teal[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedMonthYear,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal[900]),
                      items: availableMonths.map((m) {
                        return DropdownMenuItem(value: m, child: Text(formatMonthName(m)));
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => selectedMonthYear = v);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: rekapTujuan.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
                        SizedBox(height: 10),
                        Text(
                          "Belum Ada Transaksi Bosqu 🤣",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    children: [
                      Row(
                        children: [
                          Icon(Icons.pin_drop_outlined, size: 14, color: Colors.teal[800]),
                          SizedBox(width: 4),
                          Text(
                            "DISTRIBUSI PER TUJUAN",
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal[900], letterSpacing: 0.5),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      ...rekapTujuan.entries.map((e) {
                        String tujuan = e.key;
                        Map<String, int> barangMap = e.value;
                        int totalPerTujuan = barangMap.values.fold(0, (sum, val) => sum + val);

                        return Card(
                          elevation: 0,
                          margin: EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ExpansionTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue[50],
                              child: Icon(Icons.location_on, color: Colors.blue[700], size: 18),
                            ),
                            title: Text(
                              tujuan,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            subtitle: Text(
                              "Total: $totalPerTujuan Qty",
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green[700]),
                            ),
                            children: barangMap.entries.map((b) {
                              return Container(
                                color: Colors.grey[50],
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.grey[500]),
                                        SizedBox(width: 6),
                                        Text(
                                          b.key,
                                          style: TextStyle(fontSize: 10, color: Colors.grey[800]),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      "${b.value} Qty",
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      }).toList(),
                      SizedBox(height: 12),
                      Divider(color: Colors.grey[300]),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 14, color: Colors.indigo[800]),
                          SizedBox(width: 4),
                          Text(
                            "TOTAL PEMAKAIAN PER ITEM",
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo[900], letterSpacing: 0.5),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo[50]?.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: Column(
                          children: rekapTotalItem.entries.map((item) {
                            return Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.check_circle_outline, size: 12, color: Colors.indigo[700]),
                                      SizedBox(width: 6),
                                      Text(
                                        item.key,
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.blueGrey[900]),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    "${item.value} Qty",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo[900]),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
          ),
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Color(0xFF0F5132),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "TOTAL BARANG KELUAR BULAN INI",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
                Text(
                  "$grandTotalKeluar Qty",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
