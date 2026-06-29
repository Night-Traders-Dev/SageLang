import rich

# Print styled text
rich.print_styled("Hello, World!", "bold green")

# Create a panel
let panel = rich.Panel("Hello from Sage!", "My Panel")
rich.show(panel)

# Create a table
let table = rich.Table("Fruits")
table.add_column("Name", nil, "left", nil, nil, nil, nil, nil, nil, nil, false, nil, nil)
table.add_column("Color", nil, "left", nil, nil, nil, nil, nil, nil, nil, false, nil, nil)
table.add_column("Count", nil, "left", nil, nil, nil, nil, nil, nil, nil, false, nil, nil)
table.add_row(["Apple", "Red", 42])
table.add_row(["Banana", "Yellow", 17])
table.add_row(["Grape", "Purple", 93])
rich.show(table)

# Create a tree
let tree = rich.Tree("Root")
let child = tree.add("Branch A", nil)
child.add("Leaf 1", nil)
child.add("Leaf 2", nil)
let child2 = tree.add("Branch B", nil)
child2.add("Leaf 3", nil)
rich.print_tree(tree)

# Print markdown
rich.print_markdown("# Hello\n\nThis is **bold** and this is *italic*.\n\n- Item 1\n- Item 2")

# Use emoji
rich.show(rich.emoji("rocket") + " Launching!")
