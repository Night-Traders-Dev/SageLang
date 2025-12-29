// include/heartbeat.h
// Cross-platform heartbeat API

#ifndef HEARTBEAT_H
#define HEARTBEAT_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Initialize the heartbeat system
 * 
 * Pico: Launches core 1 with GPIO heartbeat
 * Linux: Creates background thread
 */
void heartbeat_init(void);

/**
 * @brief Update the main heartbeat (call from main loop)
 * 
 * Pico: Updates core 0 LED
 * Linux: Prints periodic status
 */
void heartbeat_update(void);

/**
 * @brief Check if secondary core/thread is alive
 * 
 * @return true if running, false otherwise
 */
bool heartbeat_core1_alive(void);

/**
 * @brief Print heartbeat statistics
 */
void heartbeat_stats(void);

#ifndef PICO_BUILD
/**
 * @brief Cleanup heartbeat system (Linux only)
 * Must be called before program exit on Linux
 */
void heartbeat_cleanup(void);
#endif

#ifdef __cplusplus
}
#endif

#endif // HEARTBEAT_H