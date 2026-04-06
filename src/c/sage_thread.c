// src/c/sage_thread.c
// Platform abstraction for threading primitives
//
// Desktop: delegates to pthreads
// RP2040:  stubs that return errors (single-threaded environment)

#ifndef PICO_BUILD
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#endif

#include "sage_thread.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

int sage_mutex_trylock(sage_mutex_t* mutex) {
    return pthread_mutex_trylock(mutex);
}

// Condition variables
int sage_cond_init(sage_cond_t* cond)      { return pthread_cond_init(cond, NULL); }
int sage_cond_destroy(sage_cond_t* cond)   { return pthread_cond_destroy(cond); }
int sage_cond_wait(sage_cond_t* cond, sage_mutex_t* mutex) { return pthread_cond_wait(cond, mutex); }
int sage_cond_signal(sage_cond_t* cond)    { return pthread_cond_signal(cond); }
int sage_cond_broadcast(sage_cond_t* cond) { return pthread_cond_broadcast(cond); }

// Read-write locks
int sage_rwlock_init(sage_rwlock_t* rw)       { return pthread_rwlock_init(rw, NULL); }
int sage_rwlock_destroy(sage_rwlock_t* rw)    { return pthread_rwlock_destroy(rw); }
int sage_rwlock_rdlock(sage_rwlock_t* rw)     { return pthread_rwlock_rdlock(rw); }
int sage_rwlock_wrlock(sage_rwlock_t* rw)     { return pthread_rwlock_wrlock(rw); }
int sage_rwlock_unlock(sage_rwlock_t* rw)     { return pthread_rwlock_unlock(rw); }
int sage_rwlock_tryrdlock(sage_rwlock_t* rw)  { return pthread_rwlock_tryrdlock(rw); }
int sage_rwlock_trywrlock(sage_rwlock_t* rw)  { return pthread_rwlock_trywrlock(rw); }

// Semaphores
int sage_sem_init(sage_sem_t* sem, int value) { return sem_init(sem, 0, (unsigned)value); }
int sage_sem_destroy(sage_sem_t* sem)         { return sem_destroy(sem); }
int sage_sem_wait(sage_sem_t* sem)            { return sem_wait(sem); }
int sage_sem_post(sage_sem_t* sem)            { return sem_post(sem); }
int sage_sem_trywait(sage_sem_t* sem)         { return sem_trywait(sem); }
int sage_sem_getvalue(sage_sem_t* sem, int* value) { return sem_getvalue(sem, value); }

// CPU topology
#include <string.h>
int sage_cpu_count(void) {
    return (int)sysconf(_SC_NPROCESSORS_ONLN);
}

int sage_cpu_physical_cores(void) {
    // Parse /proc/cpuinfo for unique physical core IDs
    FILE* f = fopen("/proc/cpuinfo", "r");
    if (!f) return sage_cpu_count(); // fallback
    int physical = 0;
    int seen_ids[4096];
    memset(seen_ids, 0, sizeof(seen_ids));
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "core id", 7) == 0) {
            const char* p = strchr(line, ':');
            if (p) {
                int id = atoi(p + 1);
                if (id >= 0 && id < 4096 && !seen_ids[id]) {
                    seen_ids[id] = 1;
                    physical++;
                }
            }
        }
    }
    fclose(f);
    return physical > 0 ? physical : sage_cpu_count();
}

int sage_cpu_has_hyperthreading(void) {
    int logical = sage_cpu_count();
    int physical = sage_cpu_physical_cores();
    return logical > physical ? 1 : 0;
}

#ifdef __linux__
#include <sched.h>
int sage_thread_set_affinity(int core_id) {
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(core_id, &cpuset);
    return pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
}

int sage_thread_get_core(void) {
    return sched_getcpu();
}
#else
int sage_thread_set_affinity(int core_id) { (void)core_id; return -1; }
int sage_thread_get_core(void) { return -1; }
#endif

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
    return 0;
}
int sage_mutex_trylock(sage_mutex_t* m) { (void)m; return 0; }
int sage_cond_init(sage_cond_t* c) { (void)c; return 0; }
int sage_cond_destroy(sage_cond_t* c) { (void)c; return 0; }
int sage_cond_wait(sage_cond_t* c, sage_mutex_t* m) { (void)c; (void)m; return 0; }
int sage_cond_signal(sage_cond_t* c) { (void)c; return 0; }
int sage_cond_broadcast(sage_cond_t* c) { (void)c; return 0; }
int sage_rwlock_init(sage_rwlock_t* r) { (void)r; return 0; }
int sage_rwlock_destroy(sage_rwlock_t* r) { (void)r; return 0; }
int sage_rwlock_rdlock(sage_rwlock_t* r) { (void)r; return 0; }
int sage_rwlock_wrlock(sage_rwlock_t* r) { (void)r; return 0; }
int sage_rwlock_unlock(sage_rwlock_t* r) { (void)r; return 0; }
int sage_rwlock_tryrdlock(sage_rwlock_t* r) { (void)r; return 0; }
int sage_rwlock_trywrlock(sage_rwlock_t* r) { (void)r; return 0; }
int sage_sem_init(sage_sem_t* s, int v) { (void)s; (void)v; return 0; }
int sage_sem_destroy(sage_sem_t* s) { (void)s; return 0; }
int sage_sem_wait(sage_sem_t* s) { (void)s; return 0; }
int sage_sem_post(sage_sem_t* s) { (void)s; return 0; }
int sage_sem_trywait(sage_sem_t* s) { (void)s; return 0; }
int sage_sem_getvalue(sage_sem_t* s, int* v) { (void)s; if(v)*v=1; return 0; }
int sage_cpu_count(void) { return 1; }
int sage_cpu_physical_cores(void) { return 1; }
int sage_cpu_has_hyperthreading(void) { return 0; }
int sage_thread_set_affinity(int c) { (void)c; return -1; }
int sage_thread_get_core(void) { return 0; }

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
