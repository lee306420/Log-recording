import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateListDialog extends StatefulWidget {
  final List<DateTime> dates;
  final Function(DateTime) onSelectDate;
  final int Function(DateTime) getLogCount;

  const DateListDialog({
    super.key,
    required this.dates,
    required this.onSelectDate,
    required this.getLogCount,
  });

  @override
  State<DateListDialog> createState() => _DateListDialogState();
}

class _DateListDialogState extends State<DateListDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 按月份对日期进行分组
  Map<String, List<DateTime>> _getGroupedDates() {
    final Map<String, List<DateTime>> grouped = {};

    for (var date in widget.dates) {
      if (_searchQuery.isNotEmpty) {
        final dateStr = DateFormat('yyyy年MM月dd日').format(date);
        if (!dateStr.contains(_searchQuery)) {
          continue;
        }
      }

      final monthKey = DateFormat('yyyy年MM月').format(date);
      grouped.putIfAbsent(monthKey, () => []).add(date);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final groupedDates = _getGroupedDates();
    final months = groupedDates.keys.toList()..sort((a, b) => b.compareTo(a));

    return Container(
      constraints: const BoxConstraints(maxHeight: 600),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  '所有日期',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索日期...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: groupedDates.isEmpty
                ? Center(
                    child: Text(
                      '没有找到匹配的日期',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: months.length,
                    itemBuilder: (context, monthIndex) {
                      final month = months[monthIndex];
                      final dates = groupedDates[month]!;

                      return ExpansionTile(
                        initiallyExpanded: _searchQuery.isNotEmpty,
                        title: Row(
                          children: [
                            Text(
                              month,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${dates.length}天',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        children: dates.map((date) {
                          final count = widget.getLogCount(date);
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              DateFormat('dd日 EEEE').format(date),
                              style: const TextStyle(fontSize: 15),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$count条',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            onTap: () => widget.onSelectDate(date),
                          );
                        }).toList(),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
