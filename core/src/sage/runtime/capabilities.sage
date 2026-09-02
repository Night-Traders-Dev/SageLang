// ============================================================================
# Runtime Capabilities - Capability-based security model
# ============================================================================
// Host APIs must be capability-controlled:
//   SAFE: pure computation, data transforms
//   HOST: clock, filesystem, operating-system APIs
//   UNSAFE: FFI, dynamic libraries, raw memory, host addresses
// Before executing privileged operations:
//   capability_check(), argument_validation(), resource_check()
// Restricted runtimes must fail with explicit errors
// ============================================================================

// Capability levels (from pipeline.md lines 750-763)
let CAP_SAFE = 0      // Pure computation, data transforms
let CAP_HOST = 1      // Clock, filesystem, OS APIs
let CAP_UNSAFE = 2    // FFI, dynamic libraries, raw memory, host addresses

// Capability names
let CAP_NAMES = ["SAFE", "HOST", "UNSAFE"]

// Capability structure
class Capability {
    let level: Int          // CAP_SAFE, CAP_HOST, CAP_UNSAFE
    let name: String        // Human-readable name
    let description: String // Description of what this capability allows
}

// Predefined capabilities
let CAP_CLOCK = Capability(CAP_HOST, "clock", "Access system clock/time")
let CAP_FILESYSTEM = Capability(CAP_HOST, "filesystem", "File system operations")
let CAP_OS_API = Capability(CAP_HOST, "os", "Operating system APIs")
let CAP_FFI = Capability(CAP_UNSAFE, "ffi", "Foreign function interface")
let CAP_DYNAMIC_LIB = Capability(CAP_UNSAFE, "dynamic_lib", "Dynamic library loading")
let CAP_RAW_MEMORY = Capability(CAP_UNSAFE, "raw_memory", "Raw memory access")
let CAP_HOST_ADDRESS = Capability(CAP_UNSAFE, "host_address", "Host address manipulation")
let CAP_CRYPTO = Capability(CAP_SAFE, "crypto", "Deterministic cryptography")
let CAP_NETWORK = Capability(CAP_HOST, "network", "Network operations")
let CAP_PROCESS = Capability(CAP_HOST, "process", "Process execution")
let CAP_THREAD = Capability(CAP_HOST, "thread", "Thread management")
let CAP_GPU = Capability(CAP_HOST, "gpu", "GPU/Vulkan operations")

// Host capabilities in InterpreterContext
class HostCapabilities {
    let allowed: Set<Capability>      // Capabilities granted to this context
    let profile: CapabilityProfile    // Profile that defined allowed capabilities
}

// Capability profiles (from pipeline.md lines 777-823)
// General: SAFE + HOST + selected UNSAFE (for desktop/server)
// Embedded: SAFE + selected HOST (small binary, bounded memory)
// Deterministic: SAFE only (no ambient host access)

let PROFILE_GENERAL = "general"
let PROFILE_EMBEDDED = "embedded"
let PROFILE_DETERMINISTIC = "deterministic"

// Create capabilities for a profile
proc make_capabilities(profile: String): Set<Capability> =
    match profile:
        PROFILE_GENERAL:
            return {
                CAP_CLOCK, CAP_FILESYSTEM, CAP_OS_API,
                CAP_FFI, CAP_DYNAMIC_LIB, CAP_RAW_MEMORY, CAP_HOST_ADDRESS,
                CAP_CRYPTO, CAP_NETWORK, CAP_PROCESS, CAP_THREAD, CAP_GPU
            }
        PROFILE_EMBEDDED:
            return {
                CAP_FILESYSTEM, CAP_OS_API, CAP_CRYPTO, CAP_NETWORK
            }
        PROFILE_DETERMINISTIC:
            return {
                CAP_CRYPTO
            }
    return {}

// Check if a capability is granted
proc capability_check(caps: HostCapabilities, req: Capability): Bool =
    req in caps.allowed

// Resource configuration (from pipeline.md lines 827-854)
// Each InterpreterContext configures:
//   max_steps, max_recursion_depth, max_memory, max_stack,
//   max_generator_steps, max_module_count, max_output_bytes, max_call_depth

class ResourceLimits {
    let max_steps: Int
    let max_recursion_depth: Int
    let max_memory: Int
    let max_stack: Int
    let max_generator_steps: Int
    let max_module_count: Int
    let max_output_bytes: Int
    let max_call_depth: Int
}

// Default resource limits for profiles
proc make_resource_limits(profile: String): ResourceLimits =
    match profile:
        PROFILE_GENERAL:
            return ResourceLimits(
                max_steps: -1,
                max_recursion_depth: 12000,
                max_memory: -1,
                max_stack: -1,
                max_generator_steps: -1,
                max_module_count: -1,
                max_output_bytes: -1,
                max_call_depth: 10000
            )
        PROFILE_EMBEDDED:
            return ResourceLimits(
                max_steps: 1000000,
                max_recursion_depth: 1000,
                max_memory: 16 * 1024 * 1024,  // 16MB
                max_stack: 1024 * 1024,         // 1MB
                max_generator_steps: 10000,
                max_module_count: 50,
                max_output_bytes: 1024 * 1024,  // 1MB
                max_call_depth: 5000
            )
        PROFILE_DETERMINISTIC:
            return ResourceLimits(
                max_steps: 10000000,
                max_recursion_depth: 1000,
                max_memory: 32 * 1024 * 1024,   // 32MB
                max_stack: 2 * 1024 * 1024,     // 2MB
                max_generator_steps: 10000,
                max_module_count: 10,
                max_output_bytes: 512 * 1024,   // 512KB
                max_call_depth: 1000
            )
    return make_resource_limits(PROFILE_GENERAL)

// Check resource limits
proc resource_check(limits: ResourceLimits, resource: String): Bool =
    // Check if the resource is within limits
    // Return true if allowed, false if limit exceeded
    match resource:
        "steps": return limits.max_steps == -1 or g_steps_used < limits.max_steps
        "recursion": return g_recursion_depth < limits.max_recursion_depth
        "memory": return limits.max_memory == -1 or g_memory_used < limits.max_memory
        "stack": return limits.max_stack == -1 or g_stack_used < limits.max_stack
        "generator": return limits.max_generator_steps == -1 or g_gen_steps < limits.max_generator_steps
        "modules": return limits.max_module_count == -1 or g_module_count < limits.max_module_count
        "output": return limits.max_output_bytes == -1 or g_output_bytes < limits.max_output_bytes
        "calls": return limits.max_call_depth == -1 or g_call_depth < limits.max_call_depth
    return true

// Raise resource limit error
proc raise_resource_limit(resource: String): Value =
    raise ResourceLimitError("Resource limit exceeded: " + resource)
