# EXPECT: Drawable
# EXPECT: 2
# Test trait declaration
trait Drawable:
    proc draw(self):
        pass
    proc resize(self, w, h):
        pass

print Drawable["__name__"]
print len(Drawable["__methods__"])
