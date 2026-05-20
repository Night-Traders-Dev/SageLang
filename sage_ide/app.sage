import android.app
import android.compose

# ---- Application State ----
let editor_content = android.compose.State("# Welcome to Sage IDE\n# Android 15 Edition\n\nprint(\"Hello from Sage!\")\n\nproc fib(n):\n    if n <= 1: return n\n    return fib(n-1) + fib(n-2)\n\nprint(\"fib(10) = \" + str(fib(10)))\n")
let console_output = android.compose.State("Ready.\n")
let is_running = android.compose.State(false)
let current_file = android.compose.State("main.sage")
let file_list = android.compose.ListState(["main.sage", "utils.sage", "tests.sage"])

# ---- Logic ----

proc run_code():
    if is_running.get():
        return
    
    is_running.set(true)
    console_output.set("Compiling...\n")
    
    console_output.update(proc_update_executing)
    
    # Simulate output
    console_output.update(proc_update_finished)
    
    is_running.set(false)

proc proc_update_executing(old):
    return old + "Executing " + current_file.get() + "...\n"

proc proc_update_finished(old):
    return old + "Hello from Sage!\nfib(10) = 55\n\nProcess finished.\n"

# ---- UI Event Handlers ----

proc on_run_click():
    run_code()

proc on_clear_click():
    console_output.set("")

proc on_new_file_click():
    file_list.add("untitled.sage")

proc on_editor_change(new_text):
    editor_content.set(new_text)

# ---- UI Components ----

proc Sidebar():
    let mod = android.compose.modifier().padding(16).fillMaxSize()
    let col = android.compose.Column(mod)
    col.child(android.compose.Text("Files", nil, 24, "primary"))
    col.child(android.compose.Divider())
    
    let list_mod = android.compose.modifier().weight(1.0)
    let list = android.compose.LazyColumn(list_mod)
    let files = file_list.get()
    for i in range(len(files)):
        let f = files[i]
        list.child(android.compose.Button(f, on_run_click))
    
    col.child(list)
    col.child(android.compose.Button("New File", on_new_file_click))
    return col

proc EditorView():
    let col_mod = android.compose.modifier().fillMaxSize()
    let col = android.compose.Column(col_mod)
    
    # Editor Area
    let editor_mod = android.compose.modifier().weight(0.7).fillMaxSize()
    let editor = android.compose.TextField(
        editor_content.get(), 
        on_editor_change,
        editor_mod,
        "Editor"
    )
    col.child(editor)
    
    col.child(android.compose.Spacer(8))
    col.child(android.compose.Divider())
    col.child(android.compose.Spacer(8))
    
    # Console Area
    let console_mod = android.compose.modifier().weight(0.3).fillMaxSize().padding(8)
    let console_box = android.compose.Box(console_mod)
    console_box.child(android.compose.Text(console_output.get(), nil, nil, "secondary"))
    col.child(console_box)
    
    return col

# ---- Main Layout ----

proc MainLayout():
    let editor = EditorView()
    
    let scaffold = android.compose.Scaffold(
        "Sage IDE - " + current_file.get(),
        editor,
        Sidebar()
    )
    
    return scaffold

# ---- App Initialization ----

let ide_app = android.app.App("Sage IDE")
ide_app.package("com.sage.ide")
ide_app.theme("Material3")

# Register the main compose tree
ide_app.compose_screen("main", MainLayout())

ide_app.launch()
