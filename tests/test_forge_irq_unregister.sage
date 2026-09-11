# EXPECT: Registering handler for vector 33...
# EXPECT: Dispatching vector 33...
# EXPECT: Handler A called for vector 33
# EXPECT: Unregistering vector 33...
# EXPECT: Unregistered status: true
# EXPECT: Dispatching vector 33 after unregister...
# EXPECT: Unhandled interrupt: 33
# EXPECT: Re-registering vector 33 with Handler B...
# EXPECT: Dispatching vector 33...
# EXPECT: Handler B called for vector 33
# EXPECT: Unregistering non-existent vector 99...
# EXPECT: Unregistered status: false

import metal.irq

proc handler_a(vector):
    print "Handler A called for vector " + str(vector)

proc handler_b(vector):
    print "Handler B called for vector " + str(vector)

print "Registering handler for vector 33..."
irq.register_handler(33, handler_a)

print "Dispatching vector 33..."
irq.dispatch(33)

print "Unregistering vector 33..."
let res1 = irq.unregister_handler(33)
print "Unregistered status: " + str(res1)

print "Dispatching vector 33 after unregister..."
irq.dispatch(33)

print "Re-registering vector 33 with Handler B..."
irq.register_handler(33, handler_b)

print "Dispatching vector 33..."
irq.dispatch(33)

print "Unregistering non-existent vector 99..."
let res2 = irq.unregister_handler(99)
print "Unregistered status: " + str(res2)
