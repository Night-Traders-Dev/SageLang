from app import *
from compose import *

# ---- Application State ----
let editor_content = State("# Welcome to Sage IDE\n# Android 15 Edition\n\nprint(\"Hello from Sage!\")\n\nproc fib(n):\n    if n <= 1: return n\n    return fib(n-1) + fib(n-2)\n\nprint(\"fib(10) = \" + str(fib(10)))\n")
let console_output = State("Ready.\n")
let is_running = State(false)
let current_file = State("main.sage")
let file_list = ListState(["main.sage", "utils.sage", "tests.sage"])

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
    let mod = modifier().padding(16).fillMaxSize()
    let col = Column(mod)
    col.child(Text("Files", nil, 24, "primary"))
    col.child(Divider())
    
    let list_mod = modifier().weight(1.0)
    let list = LazyColumn(list_mod)
    let files = file_list.get()
    for i in range(len(files)):
        let f = files[i]
        list.child(Button(f, on_run_click))
    
    col.child(list)
    col.child(Button("New File", on_new_file_click))
    return col

proc EditorView():
    let col_mod = modifier().fillMaxSize()
    let col = Column(col_mod)
    
    # Editor Area
    let editor_mod = modifier().weight(0.7).fillMaxSize()
    let editor = TextField(
        editor_content.get(), 
        on_editor_change,
        editor_mod,
        "Editor"
    )
    col.child(editor)
    
    col.child(Spacer(8))
    col.child(Divider())
    col.child(Spacer(8))
    
    # Console Area
    let console_mod = modifier().weight(0.3).fillMaxSize().padding(8)
    let console_box = Box(console_mod)
    console_box.child(Text(console_output.get(), nil, nil, "secondary"))
    col.child(console_box)
    
    return col

# ---- Main Layout ----

proc MainLayout():
    let editor = EditorView()
    
    let scaffold = Scaffold(
        "Sage IDE - " + current_file.get(),
        editor,
        Sidebar()
    )
    
    return scaffold

# ---- App Initialization ----

let ide_app = App("Sage IDE")
ide_app.package("com.sage.ide")
ide_app.theme("Material3")

# Register the main compose tree
ide_app.compose_screen("main", MainLayout())

ide_app.launch()
