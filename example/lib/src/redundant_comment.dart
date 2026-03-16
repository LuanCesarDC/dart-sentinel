// Dart Sentinel — redundant_comment rule
//
// Detects comments that simply restate what the code already says.
// Quick fix available: Remove comment

// ignore_for_file: unused_element

// ⚠ redundant_comment: Comment restates the function name
// Returns the user name
String getUserName() => 'Luan';

// ⚠ redundant_comment: Comment restates the code
// Increment the counter
int incrementCounter(int counter) => counter + 1;

// ⚠ redundant_comment: Obvious from the code
// Check if the list is empty
bool isListEmpty(List<dynamic> list) => list.isEmpty;

// ⚠ redundant_comment: Just repeats the variable name
class Order {
  // The order id
  final String orderId;

  // The order total
  final double total;

  Order({required this.orderId, required this.total});
}

// ✅ Correct: Comments that add context the code can't express
/// Retries up to 3 times with exponential backoff.
/// Falls back to cached data if all retries fail.
Future<String> fetchWithRetry() async => '';

/// Price includes 13% tax for BR customers (Lei 8.137/90).
double calculateTotal(double subtotal) => subtotal * 1.13;
