## os.boot.config — Boot Configuration Parser
## Parses simple boot.cfg files.

## Parse configuration string
proc parse(text):
    let conf = {}
    let lines = split(text, chr(10))
    for line in lines:
        let trimmed = strip(line)
        if len(trimmed) == 0 or trimmed[0] == "#":
            continue
        end
        let parts = split(trimmed, "=")
        if len(parts) == 2:
            conf[strip(parts[0])] = strip(parts[1])
        end
    end
    return conf
end

## Get a string value from config
proc get(conf, key, default_val):
    if has(conf, key):
        return conf[key]
    end
    return default_val
end

## Get an integer value from config
proc get_int(conf, key, default_val):
    if has(conf, key):
        return tonumber(conf[key])
    end
    return default_val
end
