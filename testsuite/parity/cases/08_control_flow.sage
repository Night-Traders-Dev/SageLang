let i = 0
while i < 10:
    i = i + 1
    if i == 2:
        continue
    if i == 8:
        break
print i
if i > 5:
    print "big"
elif i == 5:
    print "five"
else:
    print "small"
