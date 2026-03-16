// Dart Sentinel — complexity rule
//
// Flags functions that exceed thresholds for:
// - Cyclomatic complexity (branches)
// - Lines of code
// - Parameter count
// - Nesting depth

// ignore_for_file: unused_element, unused_local_variable

// ⚠ complexity: Too many parameters (6)
void createUser(
  String name,
  String email,
  String phone,
  String address,
  String city,
  String country,
) {}

// ⚠ complexity: High cyclomatic complexity + deep nesting
String classifyScore(int score, bool isFinal, bool hasBonusuardia) {
  if (score < 0) {
    return 'invalid';
  } else if (score == 0) {
    if (isFinal) {
      if (hasBonusuardia) {
        return 'bonus-zero';
      } else {
        return 'zero';
      }
    } else {
      return 'in-progress';
    }
  } else if (score < 50) {
    if (isFinal) {
      return 'fail';
    } else {
      if (hasBonusuardia) {
        return 'recovering';
      } else {
        return 'at-risk';
      }
    }
  } else if (score < 70) {
    return 'pass';
  } else if (score < 90) {
    return 'good';
  } else {
    return 'excellent';
  }
}

// ✅ Correct: Low complexity — early returns, flat structure
String classifyScoreClean(int score) {
  if (score < 0) return 'invalid';
  if (score < 50) return 'fail';
  if (score < 70) return 'pass';
  if (score < 90) return 'good';
  return 'excellent';
}

// ✅ Correct: Use a data class to reduce parameters
class CreateUserRequest {
  final String name;
  final String email;
  final String phone;
  final String address;

  CreateUserRequest({
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
  });
}

void createUserClean(CreateUserRequest request) {}
