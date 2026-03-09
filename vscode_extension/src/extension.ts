import * as vscode from "vscode";
import * as path from "path";
import * as fs from "fs";
import { DiagnosticsProvider } from "./diagnostics";
import { DashboardPanel } from "./dashboard";

let diagnosticsProvider: DiagnosticsProvider;
let fileWatcher: vscode.FileSystemWatcher | undefined;
let statusBarItem: vscode.StatusBarItem;

export function activate(context: vscode.ExtensionContext): void {
  diagnosticsProvider = new DiagnosticsProvider();
  context.subscriptions.push(diagnosticsProvider);

  // Status bar
  statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Left,
    50
  );
  statusBarItem.command = "dartSentinel.dashboard";
  statusBarItem.text = "$(shield) Sentinel";
  statusBarItem.tooltip = "Dart Sentinel — Click to open dashboard";
  statusBarItem.show();
  context.subscriptions.push(statusBarItem);

  // ── Commands ──────────────────────────────────────────────────

  // Run analysis
  context.subscriptions.push(
    vscode.commands.registerCommand("dartSentinel.analyze", async () => {
      await runAnalysis(context);
    })
  );

  // Open dashboard
  context.subscriptions.push(
    vscode.commands.registerCommand("dartSentinel.dashboard", () => {
      const report = diagnosticsProvider.getReport();
      DashboardPanel.show(context.extensionUri, report);
    })
  );

  // Clear diagnostics
  context.subscriptions.push(
    vscode.commands.registerCommand("dartSentinel.clear", () => {
      diagnosticsProvider.clear();
      statusBarItem.text = "$(shield) Sentinel";
      vscode.window.showInformationMessage(
        "Dart Sentinel: Diagnostics cleared."
      );
    })
  );

  // ── File Watcher ──────────────────────────────────────────────

  const config = vscode.workspace.getConfiguration("dartSentinel");
  const autoAnalyze = config.get<boolean>("autoAnalyze", true);

  if (autoAnalyze) {
    const reportGlob = config.get<string>(
      "reportPath",
      ".dart_sentinel/report.json"
    );

    fileWatcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(
        vscode.workspace.workspaceFolders?.[0]?.uri ?? vscode.Uri.file("."),
        reportGlob
      )
    );

    fileWatcher.onDidChange((uri) => loadReportFromUri(uri));
    fileWatcher.onDidCreate((uri) => loadReportFromUri(uri));
    context.subscriptions.push(fileWatcher);
  }

  // ── Auto-load existing report on activation ────────────────────
  autoLoadReport();
}

export function deactivate(): void {
  fileWatcher?.dispose();
}

/**
 * Run `dart run bin/analyze.dart` in the workspace terminal and reload the report.
 */
async function runAnalysis(context: vscode.ExtensionContext): Promise<void> {
  const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!workspaceRoot) {
    vscode.window.showErrorMessage(
      "Dart Sentinel: No workspace folder found."
    );
    return;
  }

  const config = vscode.workspace.getConfiguration("dartSentinel");
  const category = config.get<string>("category", "all");

  statusBarItem.text = "$(loading~spin) Sentinel...";

  // Use the integrated terminal to run analysis
  const terminal = vscode.window.createTerminal({
    name: "Dart Sentinel",
    cwd: workspaceRoot,
  });
  terminal.show(false);

  // Determine the right command — if dart_sentinel is a dependency, use `dart run dart_sentinel`
  // Otherwise, if analyzing from within the dart_sentinel repo, use `dart run bin/analyze.dart`
  const pubspecPath = path.join(workspaceRoot, "pubspec.yaml");
  const pubspec = fs.existsSync(pubspecPath)
    ? fs.readFileSync(pubspecPath, "utf-8")
    : "";

  const isSentinelProject = pubspec.includes("name: dart_sentinel");
  const baseCmd = isSentinelProject
    ? "dart run bin/analyze.dart"
    : "dart run dart_sentinel";

  const cmd =
    category === "all" ? baseCmd : `${baseCmd} -o ${category}`;

  terminal.sendText(cmd);

  // Watch for report file update
  const reportPath = config.get<string>(
    "reportPath",
    ".dart_sentinel/report.json"
  );
  const fullReportPath = path.join(workspaceRoot, reportPath);

  // Poll for report file change (since terminal is async)
  const startTime = Date.now();
  const poll = setInterval(async () => {
    if (Date.now() - startTime > 120_000) {
      clearInterval(poll);
      statusBarItem.text = "$(shield) Sentinel";
      return;
    }
    try {
      const stat = fs.statSync(fullReportPath);
      if (stat.mtimeMs > startTime) {
        clearInterval(poll);
        const report = await diagnosticsProvider.loadReport(fullReportPath);
        if (report) {
          updateStatusBar(report.summary.errors, report.summary.warnings);
          // Update dashboard if open
          if (DashboardPanel.currentPanel) {
            DashboardPanel.currentPanel.update(report);
          }
        }
      }
    } catch {
      // File doesn't exist yet — keep polling
    }
  }, 1000);
}

/**
 * Load a report from a Uri (triggered by file watcher).
 */
async function loadReportFromUri(uri: vscode.Uri): Promise<void> {
  const report = await diagnosticsProvider.loadReport(uri.fsPath);
  if (report) {
    updateStatusBar(report.summary.errors, report.summary.warnings);
    if (DashboardPanel.currentPanel) {
      DashboardPanel.currentPanel.update(report);
    }
  }
}

/**
 * Try to load an existing report on extension activation.
 */
async function autoLoadReport(): Promise<void> {
  const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!workspaceRoot) return;

  const config = vscode.workspace.getConfiguration("dartSentinel");
  const reportPath = config.get<string>(
    "reportPath",
    ".dart_sentinel/report.json"
  );
  const fullPath = path.join(workspaceRoot, reportPath);

  if (fs.existsSync(fullPath)) {
    const report = await diagnosticsProvider.loadReport(fullPath);
    if (report) {
      updateStatusBar(report.summary.errors, report.summary.warnings);
    }
  }
}

/**
 * Update the status bar with issue counts.
 */
function updateStatusBar(errors: number, warnings: number): void {
  if (errors > 0) {
    statusBarItem.text = `$(error) ${errors} $(warning) ${warnings}`;
    statusBarItem.backgroundColor = new vscode.ThemeColor(
      "statusBarItem.errorBackground"
    );
  } else if (warnings > 0) {
    statusBarItem.text = `$(shield) $(warning) ${warnings}`;
    statusBarItem.backgroundColor = new vscode.ThemeColor(
      "statusBarItem.warningBackground"
    );
  } else {
    statusBarItem.text = "$(shield) Sentinel ✓";
    statusBarItem.backgroundColor = undefined;
  }
}
