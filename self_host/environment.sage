gc_disable()
# -----------------------------------------
# environment.sage - Scope/environment management for SageLang interpreter
# -----------------------------------------

class Environment:
    proc init(parent):
        self.parent = parent
        self.values = {}

    proc define(name, value):
        self.values[name] = value

    proc get(name):
        if dict_has(self.values, name):
            return self.values[name]
        if self.parent != nil:
            return self.parent.get(name)
        raise "Undefined variable '" + name + "'"

    proc set(name, value):
        if dict_has(self.values, name):
            self.values[name] = value
            return true
        if self.parent != nil:
            return self.parent.set(name, value)
        raise "Undefined variable '" + name + "'"

    proc has(name):
        if dict_has(self.values, name):
            return true
        if self.parent != nil:
            return self.parent.has(name)
        return false
