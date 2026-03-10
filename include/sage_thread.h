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

typedef pthread_t       sage_thread_t;
typedef pthread_mutex_t sage_mutex_t;

#define SAGE_MUTEX_INITIALIZER PTHREAD_MUTEX_INITIALIZER

#else // No threads (RP2040)

// Stub types - same size so struct layouts don't change
typedef unsigned long   sage_thread_t;
typedef int             sage_mutex_t;

#define SAGE_MUTEX_INITIALIZER 0

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

// ============================================================================
// Sleep API
// ============================================================================

// Sleep for the given number of microseconds.
void sage_usleep(unsigned int usec);

// Sleep for the given number of seconds (fractional).
void sage_sleep_secs(double seconds);

#ifdef __cplusplus
}
#endif

#endif // SAGE_THREAD_H
