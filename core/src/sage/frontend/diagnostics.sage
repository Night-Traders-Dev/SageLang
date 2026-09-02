// ============================================================================
# Frontend Diagnostics - Error reporting and diagnostics
# ============================================================================
// Part of the Frontend concern
// ============================================================================

// Diagnostic severity levels
let DIAG_ERROR = 0
let DIAG_WARNING = 1
let DIAG_INFO = 2
let DIAG_HINT = 3

// Source location
class SourceLocation {
    let file: String
    let line: Int
    let column: Int
    let length: Int
}

// Diagnostic structure
class Diagnostic {
    let level: Int           // DIAG_* constant
    let message: String
    let location: SourceLocation
    let notes: List<DiagnosticNote>  // Additional context
}

// Additional diagnostic notes
class DiagnosticNote {
    let message: String
    let location: SourceLocation
}

// Diagnostic collector
class DiagnosticCollector {
    let diagnostics: List<Diagnostic>
    let max_errors: Int
    let error_count: Int
    let warning_count: Int
}

// Create a new diagnostic collector
proc collector_new(max_errors: Int): DiagnosticCollector = DiagnosticCollector(
    diagnostics: [],
    max_errors: max_errors,
    error_count: 0,
    warning_count: 0
)

// Add an error
proc collector_error(collector: DiagnosticCollector, msg: String, loc: SourceLocation): Unit =
    if collector.error_count < collector.max_errors:
        collector.diagnostics = collector.diagnostics.push(Diagnostic(
            level: DIAG_ERROR,
            message: msg,
            location: loc,
            notes: []
        ))
        collector.error_count = collector.error_count + 1

// Add a warning
proc collector_warning(collector: DiagnosticCollector, msg: String, loc: SourceLocation): Unit =
    collector.diagnostics = collector.diagnostics.push(Diagnostic(
        level: DIAG_WARNING,
        message: msg,
        location: loc,
        notes: []
    ))
    collector.warning_count = collector.warning_count + 1

// Add an info
proc collector_info(collector: DiagnosticCollector, msg: String, loc: SourceLocation): Unit =
    collector.diagnostics = collector.diagnostics.push(Diagnostic(
        level: DIAG_INFO,
        message: msg,
        location: loc,
        notes: []
    ))

// Add a hint
proc collector_hint(collector: DiagnosticCollector, msg: String, loc: SourceLocation): Unit =
    collector.diagnostics = collector.diagnostics.push(Diagnostic(
        level: DIAG_HINT,
        message: msg,
        location: loc,
        notes: []
    ))

// Add a note to the last diagnostic
proc collector_note(collector: DiagnosticCollector, msg: String, loc: SourceLocation): Unit =
    if not collector.diagnostics.is_empty():
        let last = collector.diagnostics.last
        last.notes = last.notes.push(DiagnosticNote(msg, loc))

// Check if there are errors
proc collector_has_errors(collector: DiagnosticCollector): Bool =
    collector.error_count > 0

// Get all diagnostics
proc collector_get_all(collector: DiagnosticCollector): List<Diagnostic> =
    collector.diagnostics

// Format diagnostic for output
proc format_diagnostic(diag: Diagnostic): String =
    let level_str = match diag.level:
        DIAG_ERROR: "error"
        DIAG_WARNING: "warning"
        DIAG_INFO: "info"
        DIAG_HINT: "hint"
    return diag.location.file + ":" + diag.location.line.ToString() + ":" + 
           diag.location.column.ToString() + ": " + level_str + ": " + diag.message

// Format all diagnostics
proc format_diagnostics(diagnostics: List<Diagnostic>): String =
    let output = ""
    for diag in diagnostics:
        output = output + format_diagnostic(diag) + "\n"
        for note in diag.notes:
            output = output + "  note: " + note.message + " at " + 
                     note.location.file + ":" + note.location.line.ToString() + "\n"
    return output

// Merge diagnostic collectors
proc collector_merge(collector: DiagnosticCollector, other: DiagnosticCollector): Unit =
    collector.diagnostics = collector.diagnostics + other.diagnostics
    collector.error_count = collector.error_count + other.error_count
    collector.warning_count = collector.warning_count + other.warning_count
