## Example: Hello World Android App in Sage
##
## Build with:
##   sage --compile-android examples/android_hello.sage -o hello_app \
##        --package com.sage.hello --app-name "Hello Sage"
##
## Then:
##   cd hello_app && ./gradlew assembleDebug
##
## This demonstrates how Sage reduces Android boilerplate.
## In Sage: ~30 lines. Equivalent Kotlin/XML: ~100+ lines.

## ---- Data ----

let app_name = "Hello Sage"
let version = "1.0.0"
let features = [
    "Write Android apps in Sage",
    "Transpile to Kotlin automatically",
    "Full Gradle project generation",
    "Material 3 theming built-in",
    "No XML layout files needed"
]

## ---- Logic ----

proc format_feature(index, feature):
    return str(index + 1) + ". " + feature

proc get_greeting():
    return "Welcome to " + app_name + " v" + version

## ---- Output ----

print(get_greeting())
print("")
print("Features:")

for i in range(len(features)):
    print(format_feature(i, features[i]))

print("")
print("Total features: " + str(len(features)))

## ---- Demo: Collections & Control Flow ----

let scores = {"Alice": 95, "Bob": 87, "Charlie": 92}

print("")
print("Scores:")
for name in dict_keys(scores):
    let score = scores[name]
    let grade = "C"
    if score >= 90:
        grade = "A"
    if score >= 80:
        if score < 90:
            grade = "B"
    print("  " + name + ": " + str(score) + " (" + grade + ")")
