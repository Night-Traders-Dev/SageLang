gc_disable()
# ML Visualization - SVG chart generation
# Generates training curves, weight histograms, attention heatmaps, and model architecture diagrams
# Output: SVG files viewable in any browser

import io

# ============================================================================
# SVG primitives
# ============================================================================

let SVG_HEADER = "<svg xmlns=" + chr(34) + "http://www.w3.org/2000/svg" + chr(34)
let NL = chr(10)
let DQ = chr(34)

proc svg_start(width, height):
    return SVG_HEADER + " width=" + DQ + str(width) + DQ + " height=" + DQ + str(height) + DQ + " style=" + DQ + "background:#1a1a2e" + DQ + ">" + NL

proc svg_end():
    return "</svg>" + NL

proc svg_rect(x, y, w, h, fill):
    return "<rect x=" + DQ + str(x) + DQ + " y=" + DQ + str(y) + DQ + " width=" + DQ + str(w) + DQ + " height=" + DQ + str(h) + DQ + " fill=" + DQ + fill + DQ + "/>" + NL

proc svg_line(x1, y1, x2, y2, color, width):
    return "<line x1=" + DQ + str(x1) + DQ + " y1=" + DQ + str(y1) + DQ + " x2=" + DQ + str(x2) + DQ + " y2=" + DQ + str(y2) + DQ + " stroke=" + DQ + color + DQ + " stroke-width=" + DQ + str(width) + DQ + "/>" + NL

proc svg_circle(cx, cy, r, fill):
    return "<circle cx=" + DQ + str(cx) + DQ + " cy=" + DQ + str(cy) + DQ + " r=" + DQ + str(r) + DQ + " fill=" + DQ + fill + DQ + "/>" + NL

proc svg_text(x, y, text, size, color):
    return "<text x=" + DQ + str(x) + DQ + " y=" + DQ + str(y) + DQ + " font-size=" + DQ + str(size) + DQ + " fill=" + DQ + color + DQ + " font-family=" + DQ + "monospace" + DQ + ">" + text + "</text>" + NL

proc svg_polyline(points, color, width):
    let pts = ""
    for i in range(len(points)):
        if i > 0:
            pts = pts + " "
        pts = pts + str(points[i][0]) + "," + str(points[i][1])
    return "<polyline points=" + DQ + pts + DQ + " fill=" + DQ + "none" + DQ + " stroke=" + DQ + color + DQ + " stroke-width=" + DQ + str(width) + DQ + "/>" + NL

# ============================================================================
# Training loss curve
# ============================================================================

proc loss_curve(losses, title, path):
    let w = 800
    let h = 400
    let margin = 60
    let plot_w = w - margin * 2
    let plot_h = h - margin * 2
    let n = len(losses)
    if n == 0:
        return
    # Find data range
    let min_loss = losses[0]
    let max_loss = losses[0]
    for i in range(n):
        if losses[i] < min_loss:
            min_loss = losses[i]
        if losses[i] > max_loss:
            max_loss = losses[i]
    let loss_range = max_loss - min_loss
    if loss_range < 0.001:
        loss_range = 1
    let svg = svg_start(w, h)
    # Title
    svg = svg + svg_text(w / 2 - 80, 25, title, 16, "#e0e0e0")
    # Axes
    svg = svg + svg_rect(margin, margin, plot_w, plot_h, "#16213e")
    svg = svg + svg_line(margin, margin, margin, margin + plot_h, "#4a4a6a", 1)
    svg = svg + svg_line(margin, margin + plot_h, margin + plot_w, margin + plot_h, "#4a4a6a", 1)
    # Y axis labels
    for i in range(5):
        let y_val = max_loss - i * loss_range / 4
        let y_pos = margin + (i * plot_h / 4) | 0
        svg = svg + svg_text(5, y_pos + 4, str((y_val * 100) | 0), 10, "#8888aa")
        svg = svg + svg_line(margin, y_pos, margin + plot_w, y_pos, "#2a2a4a", 1)
    # X axis labels
    for i in range(5):
        let x_pos = margin + (i * plot_w / 4) | 0
        let step = (i * n / 4) | 0
        svg = svg + svg_text(x_pos, h - 10, str(step), 10, "#8888aa")
    # Plot line
    let points = []
    for i in range(n):
        let x = margin + (i * plot_w / (n - 1)) | 0
        let y = margin + plot_h - ((losses[i] - min_loss) / loss_range * plot_h) | 0
        let pt = [x, y]
        push(points, pt)
    svg = svg + svg_polyline(points, "#00d4ff", 2)
    # Data points
    for i in range(n):
        if n < 50 or (i - ((i / (n / 30)) | 0) * ((n / 30) | 0)) == 0:
            svg = svg + svg_circle(points[i][0], points[i][1], 3, "#ff6b6b")
    # Labels
    svg = svg + svg_text(margin, h - 5, "Step", 11, "#8888aa")
    svg = svg + svg_text(5, margin - 5, "Loss", 11, "#8888aa")
    svg = svg + svg_end()
    io.writefile(path, svg)
    return path

# ============================================================================
# Weight distribution histogram
# ============================================================================

proc weight_histogram(weights, title, path):
    let w = 800
    let h = 400
    let margin = 60
    let plot_w = w - margin * 2
    let plot_h = h - margin * 2
    let num_bins = 40
    # Build histogram
    let mn = weights[0]
    let mx = weights[0]
    for i in range(len(weights)):
        if weights[i] < mn:
            mn = weights[i]
        if weights[i] > mx:
            mx = weights[i]
    let bin_w = (mx - mn) / num_bins
    if bin_w < 0.0000001:
        bin_w = 1
    let counts = []
    for i in range(num_bins):
        push(counts, 0)
    for i in range(len(weights)):
        let idx = ((weights[i] - mn) / bin_w) | 0
        if idx >= num_bins:
            idx = num_bins - 1
        if idx < 0:
            idx = 0
        counts[idx] = counts[idx] + 1
    let max_count = 1
    for i in range(num_bins):
        if counts[i] > max_count:
            max_count = counts[i]
    let svg = svg_start(w, h)
    svg = svg + svg_text(w / 2 - 100, 25, title, 16, "#e0e0e0")
    svg = svg + svg_rect(margin, margin, plot_w, plot_h, "#16213e")
    # Bars
    let bar_w = (plot_w / num_bins) | 0
    for i in range(num_bins):
        let bar_h = (counts[i] * plot_h / max_count) | 0
        let x = margin + i * bar_w
        let y = margin + plot_h - bar_h
        let intensity = (counts[i] * 255 / max_count) | 0
        let color = "rgb(" + str(intensity) + ",100," + str(255 - intensity) + ")"
        svg = svg + svg_rect(x, y, bar_w - 1, bar_h, color)
    # Axis labels
    svg = svg + svg_text(margin, h - 5, str((mn * 100) | 0), 10, "#8888aa")
    svg = svg + svg_text(margin + plot_w - 30, h - 5, str((mx * 100) | 0), 10, "#8888aa")
    svg = svg + svg_text(w / 2 - 20, h - 5, "Weight value (x100)", 11, "#8888aa")
    svg = svg + svg_end()
    io.writefile(path, svg)
    return path

# ============================================================================
# Attention heatmap
# ============================================================================

proc attention_heatmap(attn_weights, seq_len, title, path):
    let cell_size = 20
    let margin = 60
    let w = margin * 2 + seq_len * cell_size
    let h = margin * 2 + seq_len * cell_size
    if w > 1200:
        cell_size = (1000 / seq_len) | 0
        if cell_size < 2:
            cell_size = 2
        w = margin * 2 + seq_len * cell_size
        h = w
    let svg = svg_start(w, h)
    svg = svg + svg_text(w / 2 - 80, 25, title, 14, "#e0e0e0")
    # Heatmap cells
    for i in range(seq_len):
        for j in range(seq_len):
            let val = attn_weights[i * seq_len + j]
            let r = (val * 255) | 0
            if r > 255:
                r = 255
            if r < 0:
                r = 0
            let g = (val * 100) | 0
            if g > 255:
                g = 255
            let b = 50
            let color = "rgb(" + str(r) + "," + str(g) + "," + str(b) + ")"
            svg = svg + svg_rect(margin + j * cell_size, margin + i * cell_size, cell_size - 1, cell_size - 1, color)
    # Axis labels
    svg = svg + svg_text(margin, margin - 5, "Query position (row) vs Key position (col)", 10, "#8888aa")
    svg = svg + svg_end()
    io.writefile(path, svg)
    return path

# ============================================================================
# Learning rate schedule visualization
# ============================================================================

proc lr_schedule_chart(total_steps, warmup, max_lr, min_lr, schedule_type, path):
    import llm.train
    let w = 800
    let h = 300
    let margin = 60
    let plot_w = w - margin * 2
    let plot_h = h - margin * 2
    let svg = svg_start(w, h)
    svg = svg + svg_text(w / 2 - 80, 25, "Learning Rate Schedule (" + schedule_type + ")", 14, "#e0e0e0")
    svg = svg + svg_rect(margin, margin, plot_w, plot_h, "#16213e")
    let points = []
    let num_pts = 100
    for i in range(num_pts):
        let step = (i * total_steps / num_pts) | 0
        let lr = 0
        if schedule_type == "cosine":
            lr = train.cosine_schedule(step, total_steps, warmup, max_lr, min_lr)
        if schedule_type == "linear":
            lr = train.linear_schedule(step, total_steps, warmup, max_lr, min_lr)
        if schedule_type == "constant":
            lr = train.constant_schedule(step, warmup, max_lr)
        let x = margin + (i * plot_w / num_pts) | 0
        let y = margin + plot_h - ((lr / max_lr) * plot_h) | 0
        let pt = [x, y]
        push(points, pt)
    svg = svg + svg_polyline(points, "#ffd700", 2)
    svg = svg + svg_text(margin, h - 5, "0", 10, "#8888aa")
    svg = svg + svg_text(margin + plot_w - 30, h - 5, str(total_steps), 10, "#8888aa")
    svg = svg + svg_text(5, margin + 10, str(max_lr), 10, "#8888aa")
    svg = svg + svg_end()
    io.writefile(path, svg)
    return path

# ============================================================================
# Model architecture diagram
# ============================================================================

proc architecture_diagram(name, layers, d_model, d_ff, n_heads, path):
    let w = 600
    let layer_h = 80
    let h = 200 + layers * layer_h
    if h > 2000:
        h = 2000
    let svg = svg_start(w, h)
    svg = svg + svg_text(w / 2 - 60, 25, name + " Architecture", 16, "#e0e0e0")
    let y = 50
    # Embedding
    svg = svg + svg_rect(150, y, 300, 40, "#2d5a27")
    svg = svg + svg_text(220, y + 25, "Embedding (" + str(d_model) + "d)", 12, "#e0e0e0")
    y = y + 50
    # Arrow
    svg = svg + svg_line(300, y - 10, 300, y + 5, "#555", 2)
    # Transformer layers
    let layers_to_show = layers
    if layers_to_show > 12:
        layers_to_show = 12
    for i in range(layers_to_show):
        # Layer box
        svg = svg + svg_rect(100, y, 400, layer_h - 10, "#1a3a5c")
        svg = svg + svg_text(110, y + 15, "Layer " + str(i), 11, "#aaccee")
        # Sub-components
        svg = svg + svg_rect(120, y + 20, 160, 20, "#3a5a8c")
        svg = svg + svg_text(130, y + 35, "MHA (" + str(n_heads) + "h)", 10, "#e0e0e0")
        svg = svg + svg_rect(300, y + 20, 180, 20, "#5a3a8c")
        svg = svg + svg_text(310, y + 35, "FFN (" + str(d_ff) + ")", 10, "#e0e0e0")
        svg = svg + svg_rect(120, y + 45, 360, 15, "#2a4a3a")
        svg = svg + svg_text(200, y + 56, "RMSNorm + Residual", 9, "#88aa88")
        y = y + layer_h
        svg = svg + svg_line(300, y - 15, 300, y + 5, "#555", 2)
    if layers > layers_to_show:
        svg = svg + svg_text(260, y + 10, "... (" + str(layers - layers_to_show) + " more layers)", 12, "#888")
        y = y + 30
    # Final norm + LM head
    svg = svg + svg_rect(150, y, 300, 30, "#5a2727")
    svg = svg + svg_text(200, y + 20, "RMSNorm + LM Head", 12, "#e0e0e0")
    svg = svg + svg_end()
    io.writefile(path, svg)
    return path

# ============================================================================
# Multi-chart dashboard
# ============================================================================

proc generate_dashboard(model_name, losses, weights, attn, seq_len, layers, d_model, d_ff, n_heads, output_dir):
    let files = []
    # Loss curve
    if len(losses) > 0:
        let p = loss_curve(losses, model_name + " Training Loss", output_dir + "/loss_curve.svg")
        push(files, p)
    # Weight histogram
    if len(weights) > 0:
        let p2 = weight_histogram(weights, model_name + " Weight Distribution", output_dir + "/weight_dist.svg")
        push(files, p2)
    # Attention heatmap
    if len(attn) > 0 and seq_len > 0:
        let p3 = attention_heatmap(attn, seq_len, model_name + " Attention", output_dir + "/attention.svg")
        push(files, p3)
    # Architecture
    let p4 = architecture_diagram(model_name, layers, d_model, d_ff, n_heads, output_dir + "/architecture.svg")
    push(files, p4)
    # LR schedule
    let p5 = lr_schedule_chart(len(losses), 10, 0.0003, 0.00001, "cosine", output_dir + "/lr_schedule.svg")
    push(files, p5)
    # Generate index HTML
    let html = "<html><head><title>" + model_name + " Dashboard</title>"
    html = html + "<style>body{background:#0a0a1a;color:#ccc;font-family:monospace;padding:20px} img{margin:10px;border:1px solid #333;border-radius:4px} h1{color:#00d4ff} h2{color:#ffd700}</style></head><body>"
    html = html + "<h1>" + model_name + " Training Dashboard</h1>"
    for i in range(len(files)):
        if files[i] != nil:
            # Extract filename from path
            let fname = files[i]
            html = html + "<h2>" + fname + "</h2>"
            html = html + "<img src=" + DQ + fname + DQ + " width=" + DQ + "800" + DQ + ">"
        html = html + "<br>"
    html = html + "</body></html>"
    io.writefile(output_dir + "/dashboard.html", html)
    push(files, output_dir + "/dashboard.html")
    return files
