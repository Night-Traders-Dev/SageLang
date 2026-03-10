// src/c/sage_thread.c
// Platform abstraction for threading primitives
//
// Desktop: delegates to pthreads
// RP2040:  stubs that return errors (single-threaded environment)

#ifndef PICO_BUILD
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#endif

#include "sage_thread.h"
#include <stdio.h>

// ============================================================================
// Desktop Implementation (pthreads)
// ============================================================================

#if SAGE_HAS_THREADS

#include <time.h>
#include <unistd.h>

int sage_thread_create(sage_thread_t* thread, void* (*start_routine)(void*), void* arg) {
    return pthread_create(thread, NULL, start_routine, arg);
}

int sage_thread_join(sage_thread_t thread, void** retval) {
    return pthread_join(thread, retval);
}

uintptr_t sage_thread_id(void) {
    return (uintptr_t)pthread_self();
}

int sage_mutex_init(sage_mutex_t* mutex) {
    return pthread_mutex_init(mutex, NULL);
}

int sage_mutex_destroy(sage_mutex_t* mutex) {
    return pthread_mutex_destroy(mutex);
}

int sage_mutex_lock(sage_mutex_t* mutex) {
    return pthread_mutex_lock(mutex);
}

int sage_mutex_unlock(sage_mutex_t* mutex) {
    return pthread_mutex_unlock(mutex);
}

void sage_usleep(unsigned int usec) {
    usleep(usec);
}

void sage_sleep_secs(double seconds) {
    if (seconds <= 0) return;
    struct timespec ts;
    ts.tv_sec = (time_t)seconds;
    ts.tv_nsec = (long)((seconds - (double)ts.tv_sec) * 1e9);
    nanosleep(&ts, NULL);
}

// ============================================================================
// RP2040 Stub Implementation
// ============================================================================

#else // SAGE_PLATFORM_PICO

#ifdef PICO_BUILD
#include "pico/stdlib.h"
#endif

int sage_thread_create(sage_thread_t* thread, void* (*start_routine)(void*), void* arg) {
    (void)thread; (void)start_routine; (void)arg;
    fprintf(stderr, "Runtime Error: Threads are not supported on RP2040.\n");
    return -1;  // Failure
}

int sage_thread_join(sage_thread_t thread, void** retval) {
    (void)thread; (void)retval;
    return -1;  // Failure
}

uintptr_t sage_thread_id(void) {
    return 0;  // Single core ID
}

int sage_mutex_init(sage_mutex_t* mutex) {
    if (mutex) *mutex = 0;
    return 0;  // No-op success (single-threaded, no contention)
}

int sage_mutex_destroy(sage_mutex_t* mutex) {
    (void)mutex;
    return 0;
}

int sage_mutex_lock(sage_mutex_t* mutex) {
    (void)mutex;
    return 0;  // No-op (single-threaded)
}

int sage_mutex_unlock(sage_mutex_t* mutex) {
    (void)mutex;
    return 0;  // No-op (single-threaded)
}

void sage_usleep(unsigned int usec) {
#ifdef PICO_BUILD
    sleep_us(usec);
#else
    (void)usec;
#endif
}

void sage_sleep_secs(double seconds) {
#ifdef PICO_BUILD
    if (seconds > 0) {
        sleep_ms((uint32_t)(seconds * 1000));
    }
#else
    (void)seconds;
#endif
}

#endif // SAGE_HAS_THREADS
