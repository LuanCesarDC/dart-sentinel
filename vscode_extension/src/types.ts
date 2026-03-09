/**
 * Dart Sentinel — Report types.
 * Matches the JSON structure written by the CLI.
 */

export interface ReportIssue {
  rule: string;
  message: string;
  file: string; // absolute path
  relativeFile: string;
  line: number;
  severity: "error" | "warning" | "info";
}

export interface ReportSummary {
  total: number;
  errors: number;
  warnings: number;
  infos: number;
  files: number;
}

export interface Report {
  version: number;
  timestamp: string;
  projectRoot: string;
  elapsedMs: number;
  category: string;
  summary: ReportSummary;
  issues: ReportIssue[];
}
