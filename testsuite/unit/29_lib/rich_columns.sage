# EXPECT:  Col 1    Col 2
import rich.columns as columns

let c1 = "Col 1"
let c2 = "Col 2"
let col = columns.Columns([c1, c2], nil, [0, 1], false, 20, false, nil)
print col.render(nil)
