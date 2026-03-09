import * as vscode from "vscode";
import { Report } from "./types";

/**
 * Dashboard webview panel — shows a visual summary of analysis results,
 * similar to a SonarQube dashboard.
 */
export class DashboardPanel {
  public static currentPanel: DashboardPanel | undefined;
  private readonly panel: vscode.WebviewPanel;
  private disposables: vscode.Disposable[] = [];

  private constructor(panel: vscode.WebviewPanel) {
    this.panel = panel;

    this.panel.onDidDispose(
      () => {
        DashboardPanel.currentPanel = undefined;
        this.disposables.forEach((d) => d.dispose());
      },
      null,
      this.disposables
    );
  }

  /**
   * Create or show the dashboard panel.
   */
  static show(
    extensionUri: vscode.Uri,
    report: Report | null
  ): DashboardPanel {
    const column = vscode.ViewColumn.Beside;

    if (DashboardPanel.currentPanel) {
      DashboardPanel.currentPanel.panel.reveal(column);
      if (report) {
        DashboardPanel.currentPanel.update(report);
      }
      return DashboardPanel.currentPanel;
    }

    const panel = vscode.window.createWebviewPanel(
      "dartSentinelDashboard",
      "Dart Sentinel",
      column,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
      }
    );

    DashboardPanel.currentPanel = new DashboardPanel(panel);
    if (report) {
      DashboardPanel.currentPanel.update(report);
    } else {
      DashboardPanel.currentPanel.showEmpty();
    }
    return DashboardPanel.currentPanel;
  }

  /** Update the dashboard with new report data. */
  update(report: Report): void {
    this.panel.webview.html = this.buildHtml(report);
  }

  /** Show empty state. */
  private showEmpty(): void {
    this.panel.webview.html = `<!DOCTYPE html>
<html><head><style>${this.getStyles()}</style></head>
<body>
  <div class="empty">
    <h1>Dart Sentinel</h1>
    <p>No report found. Run analysis first:</p>
    <code>dart run bin/analyze.dart</code>
  </div>
</body></html>`;
  }

  /** Build the full HTML dashboard for a report. */
  private buildHtml(report: Report): string {
    const { summary } = report;
    const total = summary.total;
    const errorPct = total > 0 ? ((summary.errors / total) * 100).toFixed(1) : "0";
    const warnPct = total > 0 ? ((summary.warnings / total) * 100).toFixed(1) : "0";
    const infoPct = total > 0 ? ((summary.infos / total) * 100).toFixed(1) : "0";

    // Group by rule
    const byRule = new Map<string, { errors: number; warnings: number; infos: number; total: number }>();
    for (const issue of report.issues) {
      if (!byRule.has(issue.rule)) {
        byRule.set(issue.rule, { errors: 0, warnings: 0, infos: 0, total: 0 });
      }
      const r = byRule.get(issue.rule)!;
      r.total++;
      if (issue.severity === "error") r.errors++;
      else if (issue.severity === "warning") r.warnings++;
      else r.infos++;
    }

    // Sort by total descending
    const sortedRules = [...byRule.entries()].sort((a, b) => b[1].total - a[1].total);

    // Group by file — top offenders
    const byFile = new Map<string, { errors: number; warnings: number; total: number }>();
    for (const issue of report.issues) {
      const key = issue.relativeFile;
      if (!byFile.has(key)) {
        byFile.set(key, { errors: 0, warnings: 0, total: 0 });
      }
      const f = byFile.get(key)!;
      f.total++;
      if (issue.severity === "error") f.errors++;
      else if (issue.severity === "warning") f.warnings++;
    }
    const sortedFiles = [...byFile.entries()].sort((a, b) => {
      const scoreA = b[1].errors * 3 + b[1].warnings;
      const scoreB = a[1].errors * 3 + a[1].warnings;
      return scoreA - scoreB;
    });
    const topFiles = sortedFiles.slice(0, 20);

    // Health score (0-100, where 100 = no issues)
    const maxScore = total > 0 ? Math.max(0, 100 - (summary.errors * 3 + summary.warnings * 0.5 + summary.infos * 0.1) / summary.files) : 100;
    const healthScore = Math.round(Math.min(100, Math.max(0, maxScore)));
    const healthColor = healthScore >= 80 ? "#4caf50" : healthScore >= 50 ? "#ff9800" : "#f44336";

    const rulesRows = sortedRules
      .map(
        ([rule, counts]) => `
        <tr>
          <td class="rule-name">${this.escapeHtml(rule)}</td>
          <td class="num err">${counts.errors || ""}</td>
          <td class="num warn">${counts.warnings || ""}</td>
          <td class="num info">${counts.infos || ""}</td>
          <td class="num total">${counts.total}</td>
        </tr>`
      )
      .join("");

    const filesRows = topFiles
      .map(
        ([file, counts], i) => `
        <tr>
          <td class="rank">${i + 1}</td>
          <td class="file-path" title="${this.escapeHtml(file)}">${this.escapeHtml(this.truncatePath(file, 60))}</td>
          <td class="num err">${counts.errors || ""}</td>
          <td class="num warn">${counts.warnings || ""}</td>
          <td class="num total">${counts.total}</td>
        </tr>`
      )
      .join("");

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>${this.getStyles()}</style>
</head>
<body>
  <header>
    <h1>&#x1f6e1; Dart Sentinel</h1>
    <span class="meta">
      ${new Date(report.timestamp).toLocaleString()} &mdash; ${report.elapsedMs}ms
    </span>
  </header>

  <!-- Summary Cards -->
  <div class="cards">
    <div class="card health" style="border-color: ${healthColor}">
      <div class="card-value" style="color: ${healthColor}">${healthScore}</div>
      <div class="card-label">Health Score</div>
    </div>
    <div class="card">
      <div class="card-value">${summary.files}</div>
      <div class="card-label">Files Analyzed</div>
    </div>
    <div class="card error">
      <div class="card-value">${summary.errors}</div>
      <div class="card-label">Errors</div>
      <div class="card-pct">${errorPct}%</div>
    </div>
    <div class="card warning">
      <div class="card-value">${summary.warnings}</div>
      <div class="card-label">Warnings</div>
      <div class="card-pct">${warnPct}%</div>
    </div>
    <div class="card info-card">
      <div class="card-value">${summary.infos}</div>
      <div class="card-label">Info</div>
      <div class="card-pct">${infoPct}%</div>
    </div>
  </div>

  <!-- Severity Bar -->
  <div class="severity-bar">
    <div class="bar-segment bar-error" style="width: ${errorPct}%" title="Errors: ${summary.errors}"></div>
    <div class="bar-segment bar-warning" style="width: ${warnPct}%" title="Warnings: ${summary.warnings}"></div>
    <div class="bar-segment bar-info" style="width: ${infoPct}%" title="Info: ${summary.infos}"></div>
  </div>

  <!-- Rules Table -->
  <section>
    <h2>Issues by Rule</h2>
    <table>
      <thead>
        <tr>
          <th class="left">Rule</th>
          <th>Errors</th>
          <th>Warnings</th>
          <th>Info</th>
          <th>Total</th>
        </tr>
      </thead>
      <tbody>${rulesRows}</tbody>
    </table>
  </section>

  <!-- Top Offenders -->
  <section>
    <h2>Top ${topFiles.length} Worst Files</h2>
    <table>
      <thead>
        <tr>
          <th>#</th>
          <th class="left">File</th>
          <th>Errors</th>
          <th>Warnings</th>
          <th>Total</th>
        </tr>
      </thead>
      <tbody>${filesRows}</tbody>
    </table>
  </section>

  <footer>
    <p>Dart Sentinel v${report.version} &mdash; Category: <strong>${report.category}</strong></p>
  </footer>
</body>
</html>`;
  }

  private truncatePath(path: string, maxLen: number): string {
    if (path.length <= maxLen) return path;
    return "..." + path.slice(path.length - maxLen + 3);
  }

  private escapeHtml(text: string): string {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  private getStyles(): string {
    return `
      :root {
        --bg: #1e1e1e;
        --surface: #252526;
        --border: #3c3c3c;
        --text: #cccccc;
        --text-muted: #808080;
        --error: #f44336;
        --warning: #ff9800;
        --info: #2196f3;
        --success: #4caf50;
      }
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        background: var(--bg);
        color: var(--text);
        padding: 24px;
        line-height: 1.5;
      }
      header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 24px;
        padding-bottom: 16px;
        border-bottom: 1px solid var(--border);
      }
      header h1 { font-size: 22px; font-weight: 600; }
      .meta { color: var(--text-muted); font-size: 13px; }
      .empty {
        text-align: center; padding: 80px 20px;
      }
      .empty h1 { margin-bottom: 16px; }
      .empty code {
        display: inline-block;
        margin-top: 12px;
        background: var(--surface);
        padding: 8px 16px;
        border-radius: 4px;
        font-size: 14px;
      }

      /* Cards */
      .cards {
        display: grid;
        grid-template-columns: repeat(5, 1fr);
        gap: 12px;
        margin-bottom: 24px;
      }
      .card {
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 8px;
        padding: 16px;
        text-align: center;
      }
      .card.health { border-width: 2px; }
      .card-value { font-size: 32px; font-weight: 700; }
      .card-label { font-size: 12px; color: var(--text-muted); margin-top: 4px; text-transform: uppercase; letter-spacing: 0.5px; }
      .card-pct { font-size: 11px; color: var(--text-muted); margin-top: 2px; }
      .card.error .card-value { color: var(--error); }
      .card.warning .card-value { color: var(--warning); }
      .card.info-card .card-value { color: var(--info); }

      /* Severity bar */
      .severity-bar {
        display: flex;
        height: 8px;
        border-radius: 4px;
        overflow: hidden;
        background: var(--surface);
        margin-bottom: 28px;
      }
      .bar-segment { min-width: 2px; transition: width 0.3s; }
      .bar-error { background: var(--error); }
      .bar-warning { background: var(--warning); }
      .bar-info { background: var(--info); }

      /* Sections */
      section { margin-bottom: 28px; }
      h2 {
        font-size: 16px;
        font-weight: 600;
        margin-bottom: 12px;
        color: var(--text);
      }

      /* Tables */
      table {
        width: 100%;
        border-collapse: collapse;
        font-size: 13px;
      }
      th {
        text-align: right;
        padding: 8px 12px;
        border-bottom: 2px solid var(--border);
        color: var(--text-muted);
        font-weight: 500;
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: 0.5px;
      }
      th.left { text-align: left; }
      td {
        padding: 6px 12px;
        border-bottom: 1px solid var(--border);
      }
      .num { text-align: right; font-variant-numeric: tabular-nums; }
      .rank { text-align: center; color: var(--text-muted); width: 40px; }
      .rule-name { text-align: left; font-family: monospace; font-size: 12px; }
      .file-path {
        text-align: left;
        font-family: monospace;
        font-size: 12px;
        max-width: 400px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .err { color: var(--error); }
      .warn { color: var(--warning); }
      .info { color: var(--info); }
      .total { color: var(--text); font-weight: 600; }
      tr:hover { background: rgba(255,255,255,0.03); }

      /* Footer */
      footer {
        margin-top: 32px;
        padding-top: 16px;
        border-top: 1px solid var(--border);
        color: var(--text-muted);
        font-size: 12px;
        text-align: center;
      }
    `;
  }
}
