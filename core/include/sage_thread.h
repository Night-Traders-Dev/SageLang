// include/sage_thread.h
// Platform abstraction for threading primitives
//
// Desktop (Linux/macOS/Windows): Uses pthreads
// RP2040 (PICO_BUILD):          Stubs (single-threaded) or Pico SDK multicore
//
// All threading consumers should include this header instead of <pthread.h>

#ifndef SAGE_THREAD_H
#define SAGE_THREAD_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Platform Detection
// ============================================================================

#if defined(PICO_BUILD)
    #define SAGE_PLATFORM_PICO  1
    #define SAGE_HAS_THREADS    0   // RP2040 has no pthreads
#else
    #define SAGE_PLATFORM_PICO  0
    #define SAGE_HAS_THREADS    1   // Desktop has pthreads
#endif

// ============================================================================
// Thread Types (opaque)
// ============================================================================

#if SAGE_HAS_THREADS

#include <pthread.h>
#include <semaphore.h>

typedef pthread_t        sage_thread_t;
typedef pthread_mutex_t  sage_mutex_t;
typedef pthread_cond_t   sage_cond_t;
typedef pthread_rwlock_t sage_rwlock_t;
typedef sem_t            sage_sem_t;

#define SAGE_MUTEX_INITIALIZER  PTHREAD_MUTEX_INITIALIZER
#define SAGE_COND_INITIALIZER   PTHREAD_COND_INITIALIZER
#define SAGE_RWLOCK_INITIALIZER PTHREAD_RWLOCK_INITIALIZER

#else // No threads (RP2040)

typedef unsigned long sage_thread_t;
typedef int           sage_mutex_t;
typedef int           sage_cond_t;
typedef int           sage_rwlock_t;
typedef int           sage_sem_t;

#define SAGE_MUTEX_INITIALIZER  0
#define SAGE_COND_INITIALIZER   0
#define SAGE_RWLOCK_INITIALIZER 0

#endif

// ============================================================================
// Thread API
// ============================================================================

// Create a new thread. Returns 0 on success.
int sage_thread_create(sage_thread_t* thread, void* (*start_routine)(void*), void* arg);

// Wait for a thread to finish. Returns 0 on success.
int sage_thread_join(sage_thread_t thread, void** retval);

// Get current thread ID as a numeric value.
uintptr_t sage_thread_id(void);

// ============================================================================
// Mutex API
// ============================================================================

// Initialize a mutex. Returns 0 on success.
int sage_mutex_init(sage_mutex_t* mutex);

// Destroy a mutex.
int sage_mutex_destroy(sage_mutex_t* mutex);

// Lock a mutex (blocking).
int sage_mutex_lock(sage_mutex_t* mutex);

// Unlock a mutex.
int sage_mutex_unlock(sage_mutex_t* mutex);

// Try to lock a mutex without blocking. Returns 0 if locked, non-zero if busy.
int sage_mutex_trylock(sage_mutex_t* mutex);

// ============================================================================
// Condition Variable API
// ============================================================================

int sage_cond_init(sage_cond_t* cond);
int sage_cond_destroy(sage_cond_t* cond);
int sage_cond_wait(sage_cond_t* cond, sage_mutex_t* mutex);
int sage_cond_signal(sage_cond_t* cond);
int sage_cond_broadcast(sage_cond_t* cond);

// ============================================================================
// Read-Write Lock API
// ============================================================================

int sage_rwlock_init(sage_rwlock_t* rwlock);
int sage_rwlock_destroy(sage_rwlock_t* rwlock);
int sage_rwlock_rdlock(sage_rwlock_t* rwlock);
int sage_rwlock_wrlock(sage_rwlock_t* rwlock);
int sage_rwlock_unlock(sage_rwlock_t* rwlock);
int sage_rwlock_tryrdlock(sage_rwlock_t* rwlock);
int sage_rwlock_trywrlock(sage_rwlock_t* rwlock);

// ============================================================================
// Semaphore API
// ============================================================================

int sage_sem_init(sage_sem_t* sem, int value);
int sage_sem_destroy(sage_sem_t* sem);
int sage_sem_wait(sage_sem_t* sem);
int sage_sem_post(sage_sem_t* sem);
int sage_sem_trywait(sage_sem_t* sem);
int sage_sem_getvalue(sage_sem_t* sem, int* value);

// ============================================================================
// Atomic Operations (compiler intrinsics)
// ============================================================================

// All operations use __atomic builtins (GCC/Clang) for true atomicity.
typedef struct { volatile long value; } sage_atomic_t;

static inline long sage_atomic_load(sage_atomic_t* a) {
    return __atomic_load_n(&a->value, __ATOMIC_SEQ_CST);
}
static inline void sage_atomic_store(sage_atomic_t* a, long v) {
    __atomic_store_n(&a->value, v, __ATOMIC_SEQ_CST);
}
static inline long sage_atomic_add(sage_atomic_t* a, long v) {
    return __atomic_fetch_add(&a->value, v, __ATOMIC_SEQ_CST);
}
static inline long sage_atomic_sub(sage_atomic_t* a, long v) {
    return __atomic_fetch_sub(&a->value, v, __ATOMIC_SEQ_CST);
}
static inline int sage_atomic_cas(sage_atomic_t* a, long expected, long desired) {
    return __atomic_compare_exchange_n(&a->value, &expected, desired,
                                       0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}
static inline long sage_atomic_exchange(sage_atomic_t* a, long v) {
    return __atomic_exchange_n(&a->value, v, __ATOMIC_SEQ_CST);
}
static inline long sage_atomic_fetch_and(sage_atomic_t* a, long v) {
    return __atomic_fetch_and(&a->value, v, __ATOMIC_SEQ_CST);
}
static inline long sage_atomic_fetch_or(sage_atomic_t* a, long v) {
    return __atomic_fetch_or(&a->value, v, __ATOMIC_SEQ_CST);
}

// ============================================================================
// CPU Topology / SMP Detection
// ============================================================================

// Returns number of logical processors (includes hyperthreads).
int sage_cpu_count(void);

// Returns number of physical cores (excludes hyperthreads).
int sage_cpu_physical_cores(void);

// Returns 1 if hyperthreading is detected, 0 otherwise.
int sage_cpu_has_hyperthreading(void);

// Set CPU affinity for the current thread (pin to specific core).
// core_id: 0-based core index. Returns 0 on success.
int sage_thread_set_affinity(int core_id);

// Get the core the current thread is running on. Returns -1 on error.
int sage_thread_get_core(void);

// ============================================================================
// Sleep API
// ============================================================================

void sage_usleep(unsigned int usec);
void sage_sleep_secs(double seconds);

#ifdef __cplusplus
}
#endif

#endif // SAGE_THREAD_H
