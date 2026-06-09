# EXPECT: true
# EXPECT: true
# Test: POSIX semaphore operations
let s = sem_new(2)

# Acquire two permits
sem_wait(s)
sem_wait(s)

# Try to acquire third (should fail — non-blocking)
let got = sem_trywait(s)
print got == false

# Release one
sem_post(s)

# Now trywait should succeed
let got2 = sem_trywait(s)
print got2 == true
