gc_disable()
import rich.style
import rich.text

# Prompt utilities for interactive CLI

# Create an input prompt with style
proc Prompt(prompt_text, password, choices, default_val, show_default, show_choices,
            confirm_val, stream):
    let prompt = {}
    prompt["prompt"] = "> "
    if prompt_text != nil:
        prompt["prompt"] = prompt_text
    prompt["password"] = false
    if password != nil:
        prompt["password"] = password
    prompt["choices"] = nil
    if choices != nil:
        prompt["choices"] = choices
    prompt["default"] = nil
    if default_val != nil:
        prompt["default"] = default_val
    prompt["show_default"] = true
    if show_default != nil:
        prompt["show_default"] = show_default
    prompt["show_choices"] = true
    if show_choices != nil:
        prompt["show_choices"] = show_choices
    prompt["confirm"] = false
    if confirm_val != nil:
        prompt["confirm"] = confirm_val
    return prompt

# Ask the user for input with a styled prompt
proc ask(prompt, console):
    let prompt_text = prompt["prompt"]
    let def_val = prompt["default"]
    let choices = prompt["choices"]

    let display = ""

    if choices != nil and prompt["show_choices"]:
        let choices_str = ""
        for i in range(len(choices)):
            if i > 0:
                choices_str = choices_str + "/"
            choices_str = choices_str + str(choices[i])
        display = display + "[" + choices_str + "] "

    display = display + prompt_text

    if def_val != nil and prompt["show_default"]:
        display = display + " [" + str(def_val) + "]"
    display = display + ": "

    let styled = rich.style.render_styled(display, rich.style.parse_style("bold"))
    if console != nil:
        console._output(styled)
    else:
        print(styled)

    return input()

# Ask for confirmation (y/n)
proc confirm(prompt_text, default_val, console):
    let choices = ["y", "n"]
    let default_str = "n"
    if default_val:
        default_str = "y"
    let prompt_obj = Prompt(prompt_text, false, choices, default_str, true, true, false, nil)
    let result = ask(prompt_obj, console)
    if result == "" and default_val != nil:
        return default_val
    return lower(result) == "y" or lower(result) == "yes"

# Ask to select from a list (returns index)
proc select(prompt_text, options, default_val, console):
    let prompt_obj = Prompt(prompt_text + " (1-" + str(len(options)) + ")", false, nil, default_val, true, false, false, nil)
    let result = ask(prompt_obj, console)
    if result == "" and default_val != nil:
        return default_val
    let num = tonumber(result)
    return num

# Render a styled prompt string (returns ANSI string, does not read input)
proc render_prompt(parts):
    let result = ""
    for i in range(len(parts)):
        let p = parts[i]
        if type(p) == "array" and len(p) == 2:
            result = result + rich.style.render_styled(str(p[0]), rich.style.parse_style(p[1]))
        else:
            result = result + str(p)
    return result
