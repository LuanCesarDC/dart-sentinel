// Dart Sentinel — dead_todo rule
//
// Flags TODO/FIXME/HACK comments that lack actionable context.
// Quick fix available: Remove comment

// ⚠ dead_todo: No context — what needs fixing?
// TODO
// FIXME
// HACK

// ⚠ dead_todo: Too vague to be useful
// TODO: fix this
// FIXME: broken
// TODO: refactor later

// ✅ Correct: Actionable TODOs with context
// TODO(luan): Migrate fetchUser to use new API v2 endpoint — see #42
// FIXME: Race condition when two users update the same document simultaneously
void placeholder() {}
