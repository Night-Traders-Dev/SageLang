# -----------------------------------------
# generator_scheduler.sage
# -----------------------------------------
# Tiny cooperative scheduler built on generators.

proc make_counter(name, limit):
    let i = 0
    while i < limit:
        # Each yield is a "step" in the task.
        yield name + " step " + str(i)
        i = i + 1
    # When the loop ends, next(gen) will return nil.

class Task:
    proc init(name, gen):
        self.name = name
        self.gen = gen
        self.done = false

class Scheduler:
    proc init():
        self.tasks = []

    proc add_task(task):
        push(self.tasks, task)

    proc run():
        # Simple round-robin over all tasks until all are done.
        while true:
            let all_done = true

            for t in self.tasks:
                if not t.done:
                    all_done = false
                    let value = next(t.gen)
                    if value == nil:
                        # Generator exhausted.
                        t.done = true
                    else:
                        print "[" + t.name + "] " + value

            if all_done:
                break

# Demo: three counters with different limits.
proc main():
    let s = Scheduler()

    let t1 = Task("A", make_counter("A", 5))
    let t2 = Task("B", make_counter("B", 3))
    let t3 = Task("C", make_counter("C", 7))

    s.add_task(t1)
    s.add_task(t2)
    s.add_task(t3)

    s.run()

main()
