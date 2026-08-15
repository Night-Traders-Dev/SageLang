import rich.emoji as emoji

# 1. Test get_emoji
print("Testing get_emoji...")
let e1 = emoji.get_emoji("rocket")
if e1 != "🚀":
    print("FAIL: get_emoji('rocket') got: " + e1)
else:
    print("PASS: get_emoji('rocket')")

let e2 = emoji.get_emoji(":smile:")
if e2 != "🙂":
    print("FAIL: get_emoji(':smile:') got: " + e2)
else:
    print("PASS: get_emoji(':smile:')")

let e3 = emoji.get_emoji("nonexistent_emoji_name_123")
if e3 != "":
    print("FAIL: get_emoji('nonexistent') got: " + e3)
else:
    print("PASS: get_emoji('nonexistent')")

# 2. Test has_emoji
print("Testing has_emoji...")
if emoji.has_emoji("bug") != true:
    print("FAIL: has_emoji('bug') should be true")
else:
    print("PASS: has_emoji('bug')")

if emoji.has_emoji("invalid_emoji_foo") != false:
    print("FAIL: has_emoji('invalid') should be false")
else:
    print("PASS: has_emoji('invalid')")

# 3. Test emoji_replace
print("Testing emoji_replace...")

# Case A: Plain text without colons
let plain = "Hello world! No emojis here."
let res_plain = emoji.emoji_replace(plain)
if res_plain != plain:
    print("FAIL: emoji_replace(plain) got: " + res_plain)
else:
    print("PASS: emoji_replace(plain)")

# Case B: Single emoji shortcode
let single = "Blast off! :rocket:"
let res_single = emoji.emoji_replace(single)
if res_single != "Blast off! 🚀":
    print("FAIL: emoji_replace(single) got: " + res_single)
else:
    print("PASS: emoji_replace(single)")

# Case C: Multiple emoji shortcodes
let multi = "I :heart: coding with :bug: fixes and :fire: optimizations!"
let res_multi = emoji.emoji_replace(multi)
if res_multi != "I ❤ coding with 🐛 fixes and 🔥 optimizations!":
    print("FAIL: emoji_replace(multi) got: " + res_multi)
else:
    print("PASS: emoji_replace(multi)")

# Case D: Colons that do not match valid emojis
let no_match = "This:is:a:test:with:unknown:colons"
let res_no_match = emoji.emoji_replace(no_match)
if res_no_match != no_match:
    print("FAIL: emoji_replace(no_match) got: " + res_no_match)
else:
    print("PASS: emoji_replace(no_match)")

# Case E: Empty string
let res_empty = emoji.emoji_replace("")
if res_empty != "":
    print("FAIL: emoji_replace('') got: " + res_empty)
else:
    print("PASS: emoji_replace('')")

print("All emoji tests completed successfully!")
