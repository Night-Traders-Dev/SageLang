## Shared helpers and error type for the AVR assembler.

## Assembler error carrying source line context.
class AsmError:
    def init(self, msg, line=0):
        self.msg = msg
        self.line = line

    def __str__(self):
        if self.line > 0:
            return "error at line " + str(self.line) + ": " + self.msg
        return self.msg

## Strip comments and whitespace from a raw source line.
## ';' begins a comment in AVR assembly.
proc strip_comment(s):
    let idx = string.find(s, ";")
    if idx >= 0:
        s = string.slice(s, 0, idx)
    return string.strip(s)