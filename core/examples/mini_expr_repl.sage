# -----------------------------------------
# mini_expr_repl.sage
# -----------------------------------------
# A tiny interactive arithmetic expression evaluator:
# supports +, -, *, /, parentheses, and integer literals.

# Grammar (informal):
#   expr   -> term (("+" | "-") term)*
#   term   -> factor (("*" | "/") factor)*
#   factor -> NUMBER | "(" expr ")"

class Parser:
    proc init(text):
        self.text = text
        self.pos = 0
        self.len = len(text)

    proc current_char():
        if self.pos >= self.len:
            return nil
        return self.text[self.pos]

    proc advance():
        self.pos = self.pos + 1

    proc skip_ws():
        while true:
            let c = self.current_char()
            if c == nil:
                break
            if c == " ":
                self.advance()
            else:
                break

    proc parse_number():
        self.skip_ws()
        let start = self.pos
        while true:
            let c = self.current_char()
            if c == nil:
                break
            if c >= "0" and c <= "9":
                self.advance()
            else:
                break
        if self.pos == start:
            raise "Expected number"
        let s = slice(self.text, start, self.pos)
        return tonumber(s)

    proc parse_factor():
        self.skip_ws()
        let c = self.current_char()

        if c == "(":
            self.advance()
            let value = self.parse_expr()
            self.skip_ws()
            if self.current_char() != ")":
                raise "Expected ')'"
            self.advance()
            return value

        # Unary minus
        if c == "-":
            self.advance()
            let v = self.parse_factor()
            return -v

        return self.parse_number()

    proc parse_term():
        let value = self.parse_factor()
        while true:
            self.skip_ws()
            let c = self.current_char()
            if c == "*" or c == "/":
                self.advance()
                let rhs = self.parse_factor()
                if c == "*":
                    value = value * rhs
                else:
                    value = value / rhs
            else:
                break
        return value

    proc parse_expr():
        let value = self.parse_term()
        while true:
            self.skip_ws()
            let c = self.current_char()
            if c == "+" or c == "-":
                self.advance()
                let rhs = self.parse_term()
                if c == "+":
                    value = value + rhs
                else:
                    value = value - rhs
            else:
                break
        return value

proc eval_expr(line):
    let p = Parser(line)
    let result = p.parse_expr()
    # Ensure we've consumed the whole line (ignoring trailing whitespace).
    p.skip_ws()
    if p.current_char() != nil:
        raise "Unexpected trailing input"
    return result

proc repl():
    print "Mini expression REPL. Empty line to exit."
    while true:
        print "> "
        let line = input()
        if line == nil:
            break
        if len(line) == 0:
            break

        try:
            let value = eval_expr(line)
            print "= " + str(value)
        catch e:
            print "Error: " + e

proc main():
    repl()

main()
