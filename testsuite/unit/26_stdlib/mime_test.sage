gc_disable()
# EXPECT: text/html
# EXPECT: application/json
# EXPECT: image/png
# EXPECT: application/pdf
# EXPECT: text/css
# EXPECT: true
# EXPECT: true
# EXPECT: image

import net.mime

print mime.lookup("html")
print mime.lookup("json")
print mime.from_filename("photo.png")
print mime.from_filename("document.pdf")
print mime.from_filename("styles.CSS")

print mime.is_text("application/json")
print mime.is_image("image/png")
print mime.category("image/png")
