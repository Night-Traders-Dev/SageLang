# Comprehensive string operations demo
print "=== String Operations Demo ==="
print ""

# String concatenation
print "1. String Concatenation:"
let first = "Hello"
let last = "World"
let greeting = first + " " + last
print greeting

print ""
print "2. String Length:"
let text = "SageLang"
print "Length of 'SageLang':"
print len(text)

print ""
print "3. Split:"
let sentence = "The quick brown fox"
let words = split(sentence, " ")
print "Split by space:"
for word in words:
    print word

print ""
print "4. Join:"
let joined = join(words, "-")
print "Joined with dashes:"
print joined

print ""
print "5. Replace:"
let original = "Hello World"
let replaced = replace(original, "World", "SageLang")
print replaced

print ""
print "6. Upper/Lower Case:"
let mixed = "SageLang Rocks"
print "Original:"
print mixed
print "Uppercase:"
print upper(mixed)
print "Lowercase:"
print lower(mixed)

print ""
print "7. Strip Whitespace:"
let padded = "   trimmed   "
print "Before strip: '"
print padded
print "'"
print "After strip: '"
print strip(padded)
print "'"

print ""
print "String operations complete!"