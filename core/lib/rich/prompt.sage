gc_disable()
import rich.style
import rich.text

# Prompt utilities for interactive CLI

# Create an input prompt with style
proc Prompt(prompt_text, password, choices, default, show_default, show_choices,
            confirm, stream):
    let prompt = {}
    prompt["prompt"] = prompt_text if prompt_text != nil else "> "
    prompt["password"] = password if password != nil else false
    prompt["choices"] = choices if choices != nil else nil
    prompt["default"] = default if default != nil else nil
    prompt["show_default"] = show_default if show_default != nil else true
    prompt["show_choices"] = show_choices if show_choices != nil else true
    prompt["confirm"] = confirm if confirm != nil else false
    return prompt

# Ask the user for input with a styled prompt
proc ask(prompt, console):
    let prompt_text = prompt["prompt"]
    let default = prompt["default"]
    let choices = prompt["choices"]

    # Build prompt string
    let display = ""

    if choices != nil and prompt["show_choices"]:
        let choices_str = ""
        for i in range(len(choices)):
            if i > 0:
                choices_str = choices_str + "/"
            choices_str = choices_str + str(choices[i])
        display = display + "[" + choices_str + "] "

    display = display + prompt_text

    if default != nil and prompt["show_default"]:
        display = display + " [" + str(default) + "]"
    display = display + ": "

    # Print styled prompt
    let styled = rich.style.render_styled(display, rich.style.parse_style("bold"))
    if console != nil:
        console._output(styled)
    else:
        print(styled)

    # Read input (basic - uses built-in input)
    return input()

# Ask for confirmation (y/n)
proc confirm(prompt_text, default, console):
    let choices = ["y", "n"]
    let default_str = "y" if default else "n"
    let prompt_obj = Prompt(prompt_text, false, choices, default_str, true, true, false, nil)
    let result = ask(prompt_obj, console)
    if result == "" and default != nil:
        return default
    return lower(result) == "y" or lower(result) == "yes"

# Ask to select from a list (returns index)
proc select(prompt_text, options, default, console):
    let prompt_obj = Prompt(prompt_text + " (1-" + str(len(options)) + ")", false, nil, default, true, false, false, nil)
    let result = ask(prompt_obj, console)
    if result == "" and default != nil:
        return default
    let num = tonumber(result)
    return num
