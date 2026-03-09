import * as vscode from "vscode";
import * as fs from "fs";
import { Report, ReportIssue } from "./types";

/**
 * Manages VS Code diagnostics (Problems tab) from a Dart Sentinel report.
 */
export class DiagnosticsProvider implements vscode.Disposable {
  private readonly collection: vscode.DiagnosticCollection;
  private currentReport: Report | null = null;

  constructor() {
    this.collection =
      vscode.languages.createDiagnosticCollection("dart-sentinel");
  }

  dispose(): void {
    this.collection.dispose();
  }

  /** Clear all diagnostics. */
  clear(): void {
    this.collection.clear();
    this.currentReport = null;
  }

  /** Get the currently loaded report. */
  getReport(): Report | null {
    return this.currentReport;
  }

  /**
   * Load a report JSON file and push diagnostics to the Problems tab.
   * Returns the parsed report or null on failure.
   */
  async loadReport(reportPath: string): Promise<Report | null> {
    try {
      const content = fs.readFileSync(reportPath, "utf-8");
      const report: Report = JSON.parse(content);

      if (!report.issues || !Array.isArray(report.issues)) {
        vscode.window.showWarningMessage(
          "Dart Sentinel: Invalid report format."
        );
        return null;
      }

      this.currentReport = report;
      this.pushDiagnostics(report);

      const { errors, warnings, infos } = report.summary;
      vscode.window.showInformationMessage(
        `Dart Sentinel: ${errors} errors, ${warnings} warnings, ${infos} info — ${report.summary.files} files`
      );

      return report;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") {
        // Report file doesn't exist yet — not an error
        return null;
      }
      vscode.window.showErrorMessage(
        `Dart Sentinel: Failed to read report — ${err}`
      );
      return null;
    }
  }

  /**
   * Push all issues from the report into VS Code's DiagnosticCollection.
   */
  private pushDiagnostics(report: Report): void {
    this.collection.clear();

    // Group issues by absolute file path
    const grouped = new Map<string, ReportIssue[]>();
    for (const issue of report.issues) {
      const key = issue.file;
      if (!grouped.has(key)) {
        grouped.set(key, []);
      }
      grouped.get(key)!.push(issue);
    }

    // Convert to VS Code Diagnostics
    for (const [filePath, issues] of grouped) {
      const uri = vscode.Uri.file(filePath);
      const diagnostics: vscode.Diagnostic[] = issues.map((issue) =>
        this.issueToDiagnostic(issue)
      );
      this.collection.set(uri, diagnostics);
    }
  }

  /** Map a single ReportIssue to a vscode.Diagnostic. */
  private issueToDiagnostic(issue: ReportIssue): vscode.Diagnostic {
    // Lines are 1-based in the report, VS Code uses 0-based
    const line = Math.max(0, issue.line - 1);
    const range = new vscode.Range(line, 0, line, Number.MAX_SAFE_INTEGER);

    const severity = this.mapSeverity(issue.severity);

    const diagnostic = new vscode.Diagnostic(range, issue.message, severity);
    diagnostic.source = "dart-sentinel";
    diagnostic.code = issue.rule;

    return diagnostic;
  }

  /** Map string severity to VS Code DiagnosticSeverity. */
  private mapSeverity(severity: string): vscode.DiagnosticSeverity {
    switch (severity) {
      case "error":
        return vscode.DiagnosticSeverity.Error;
      case "warning":
        return vscode.DiagnosticSeverity.Warning;
      case "info":
        return vscode.DiagnosticSeverity.Information;
      default:
        return vscode.DiagnosticSeverity.Warning;
    }
  }
}
