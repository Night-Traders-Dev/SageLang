gc_disable()
import rich.style
import rich.text
import rich.measure
import rich.color

# Progress bar component

# Spinner frames (common spinners)
let SPINNER_DOTS = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
let SPINNER_LINE = ["|", "/", "-", "\\"]
let SPINNER_DOTS_SIMPLE = [".  ", ".. ", "...", "   "]
let SPINNER_ARROW = ["←", "↖", "↑", "↗", "→", "↘", "↓", "↙"]
let SPINNER_BOUNCE = ["[    ]", "[   =]", "[  ==]", "[ ===]", "[====]", "[=== ]", "[==  ]", "[=   ]"]
let SPINNER_PULSE = ["█", "▓", "▒", "░"]

class Progress:
    proc init(self, console, total, description, transient, refresh_per_second):
        self.console = console
        self.total = total if total != nil else 0
        self.completed = 0
        self.description = description if description != nil else ""
        self.transient = transient if transient != nil else false
        self.refresh_per_second = refresh_per_second if refresh_per_second != nil else 10
        self._spinner_idx = 0
        self._spinner = SPINNER_DOTS
        self._task_id = 0
        self._tasks = []

    # Add a task
    proc add_task(self, description, total, completed, start_time):
        let task = {}
        task["id"] = self._task_id
        self._task_id = self._task_id + 1
        task["description"] = description if description != nil else ""
        task["total"] = total if total != nil else 100
        if total == nil:
            task["total"] = 100
        task["completed"] = completed if completed != nil else 0
        task["start_time"] = start_time if start_time != nil else nil
        push(self._tasks, task)
        return task["id"]

    # Update task progress
    proc update(self, task_id, advance, completed, description, total):
        for i in range(len(self._tasks)):
            if self._tasks[i]["id"] == task_id:
                let task = self._tasks[i]
                if advance != nil:
                    task["completed"] = task["completed"] + advance
                if completed != nil:
                    task["completed"] = completed
                if description != nil:
                    task["description"] = description
                if total != nil:
                    task["total"] = total
                return

    # Get a single render line for a task
    proc _render_task(self, task, width):
        let bar_width = width - 30
        if bar_width < 10:
            bar_width = 10

        let completed = task["completed"]
        let total = task["total"]
        if total == 0:
            total = 1
        let pct = (completed * 100) / total

        # Bar chars
        let filled = (pct * bar_width) / 100 | 0
        if filled > bar_width:
            filled = bar_width
        let empty = bar_width - filled

        let bar_filled = ""
        for i in range(filled):
            bar_filled = bar_filled + chr(9608)  # Full block
        let bar_empty = ""
        for i in range(empty):
            bar_empty = bar_empty + chr(9617)  # Light shade

        let spinner_char = self._spinner[self._spinner_idx]
        self._spinner_idx = (self._spinner_idx + 1) % len(self._spinner)

        # Format percentage
        let pct_str = str(pct | 0) + "%"
        let padded_pct = ""
        let pct_len = 4 - len(pct_str)
        for i in range(pct_len):
            padded_pct = padded_pct + " "
        padded_pct = padded_pct + pct_str

        # Format counts
        let count_str = str(completed | 0) + "/" + str(total | 0)

        let desc = task["description"]
        if len(desc) > 25:
            desc_t = ""
            for i in range(22):
                desc_t = desc_t + desc[i]
            desc = desc_t + "..."

        let result = "  " + spinner_char + " " + desc + " " + bar_filled + bar_empty + " " + count_str + " " + padded_pct
        return result

    # Iterate through all tasks and render
    proc render(self, console):
        let width = console.width if console != nil else 80
        let lines = []
        for i in range(len(self._tasks)):
            push(lines, self._render_task(self._tasks[i], width))
        let result = ""
        for i in range(len(lines)):
            if i > 0:
                result = result + chr(10)
            result = result + lines[i]
        return result

    proc __rich__(self, console):
        return self.render(console)

    proc __str__(self):
        return self.render(nil)

# Simple progress bar (standalone)
class ProgressBar:
    proc init(self, total, width, complete_style, finished_style, pulse_style, style, show_percent):
        self.total = total if total != nil else 100
        self.completed = 0
        self.width = width if width != nil else 40
        self.complete_style = complete_style if complete_style != nil else "green"
        self.finished_style = finished_style if finished_style != nil else "bright_green"
        self.pulse_style = pulse_style if pulse_style != nil else "blue"
        self.style = style if style != nil else ""
        self.show_percent = show_percent if show_percent != nil else true

    proc update(self, completed):
        self.completed = completed

    proc advance(self, amount):
        if amount == nil:
            amount = 1
        self.completed = self.completed + amount

    proc render(self, console):
        let pct = (self.completed * 100) / (1 if self.total <= 0 else self.total)
        let filled = (pct * self.width) / 100 | 0
        if filled > self.width:
            filled = self.width
        let empty = self.width - filled

        let filled_ch = chr(9608)
        let empty_ch = chr(9617)

        let bar = rich.style.render_styled(
            self._repeat_char(filled_ch, filled),
            rich.style.parse_style(self.complete_style))
        bar = bar + rich.style.render_styled(
            self._repeat_char(empty_ch, empty),
            rich.style.parse_style("dim"))

        if self.show_percent:
            bar = bar + " " + str(pct | 0) + "%"

        return bar

    proc _repeat_char(self, ch, n):
        let result = ""
        for i in range(n):
            result = result + ch
        return result

    proc __rich__(self, console):
        return self.render(console)

    proc __str__(self):
        return self.render(nil)

# Create a simple progress bar
proc create_progress_bar(total, width):
    return ProgressBar(total, width, nil, nil, nil, nil, true)

# Status display
class Status:
    proc init(self, status, console, spinner):
        self.status = status
        self.console = console
        self.spinner = spinner if spinner != nil else SPINNER_DOTS
        self._idx = 0
        self._visible = false

    proc start(self):
        self._visible = true
        self._render()

    proc stop(self):
        if self._visible:
            self.console.cursor_up(1)
            self.console.clear_line()
            self._visible = false

    proc update(self, status):
        self.status = status
        if self._visible:
            self._render()

    proc _render(self):
        let ch = self.spinner[self._idx]
        self._idx = (self._idx + 1) % len(self.spinner)
        self.console._output(ch + " " + self.status)

    proc __enter__(self):
        self.start()
        return self

    proc __exit__(self):
        self.stop()
