import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// URL Web App Google Apps Script
const String webAppUrl = "https://script.google.com/macros/s/AKfycbw9isPtrn-PoQEH8Kp_ybcxDAHkV4k59D5NusLfWr6UTw_8iin6NBAWqbLEuRYulls/exec";

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
    "SEGREGASI"
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

        // A. Process Data Stok
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

        // B. Process Data Riwayat dari Sheets
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

            // Merapikan Tampilan Jam & Tanggal agar Rapi
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
                tgl = DateFormat('dd/MM').format(parsed.toLocal());
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

    try {
      final response = await http.post(
        Uri.parse(webAppUrl),
        body: jsonEncode({
          "action": "addItem",
          "itemName": cleanName
        }),
      );

      var res = jsonDecode(response.body);
      if (res['status'] == 'success') {
        setState(() {
          items.add({
            "name": cleanName,
            "stock": 0,
            "ctrl": TextEditingController(text: "1"),
            "tujuan": "- Pilih Tujuan -",
          });
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Item '$cleanName' tersimpan di Google Sheets!")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menambah item ke Sheets.")));
    }
  }

  // 3. UPDATE STOK & CATAT LOG SINKRON KE SHEETS
  Future<void> prosesUpdate(Map item, int operasi) async {
    if (operasi == -1 && item['tujuan'] == "- Pilih Tujuan -") {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Pilih Tujuan Resmi!")));
      return;
    }

    int qty = int.tryParse(item['ctrl'].text) ?? 0;
    if (qty <= 0) return;

    if (operasi == -1 && item['stock'] < qty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Stok tidak mencukupi!")));
      return;
    }

    int stokBaru = item['stock'] + (operasi * qty);
    String targetTujuan = operasi == 1 ? "Gudang" : item['tujuan'];

    try {
      final response = await http.post(
        Uri.parse(webAppUrl),
        body: jsonEncode({
          "item": item['name'],
          "stock": stokBaru,
          "operasi": operasi,
          "qty": qty,
          "tujuan": targetTujuan,
        }),
      );

      var res = jsonDecode(response.body);
      if (res['status'] == 'success') {
        String tgl = res['tgl'] ?? DateFormat('dd/MM').format(DateTime.now());
        String jam = res['jam'] ?? DateFormat('HH:mm').format(DateTime.now());

        setState(() {
          item['stock'] = stokBaru;
          history.insert(0, "$tgl|$jam|${operasi == 1 ? "Masuk" : "Keluar"}|$qty|${item['name']}|$targetTujuan");
        });

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Tersimpan di Google Sheets!")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal mengupdate ke Sheets.")));
    }
  }

  // FUNGSI KONFIRMASI HAPUS RIWAYAT DILAYAR
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
              setState(() {
                history.clear();
              });
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
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
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
            // 1. Header Gradient & Dashboard
            Container(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0F5132),
                    Color(0xFF198754),
                    Color(0xFF0D6EFD),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  )
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
                            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.85)),
                          ),
                        ],
                      ),
                      Row(
                        children: [
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
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                FadeTransition(
                                  opacity: _liveAnimCtrl,
                                  child: Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                                ),
                                SizedBox(width: 4),
                                Text("LIVE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                              ],
                            ),
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

            // 2. Daftar Item Card Modern
            Expanded(
              flex: 3,
              child: isLoading
                  ? Center(child: CircularProgressIndicator(color: Colors.teal))
                  : RefreshIndicator(
                      color: Color(0xFF0F5132),
                      backgroundColor: Colors.white,
                      displacement: 20,
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
                              physics: AlwaysScrollableScrollPhysics(),
                              itemBuilder: (context, i) {
                                var item = items[i];
                                bool isStockLow = item['stock'] < 500;

                                return Container(
                                  margin: EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.03),
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
                                                  enabledBorder: OutlineInputBorder(
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
                                );
                              },
                            ),
                    ),
            ),

            // 3. Panel Riwayat Transaksi Modern
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  )
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
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                "${history.length} Log",
                                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                              ),
                            ),
                            SizedBox(width: 4),
                            // 🗑️ TOMBOL HAPUS LOG RIWAYAT DILAYAR
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
                              color: isMasuk ? Colors.green[50]?.withOpacity(0.5) : Colors.red[50]?.withOpacity(0.5),
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
