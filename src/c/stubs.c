#include <stdio.h>
#include <stdint.h>

void jit_init() {}
void jit_shutdown() {}
const char* jit_type_name(int t) { (void)t; return "unknown"; }
void jit_record_call() {}
void* jit_get_profile() { return NULL; }
int jit_should_compile() { return 0; }
void jit_compile_function() {}
void jit_record_return() {}

void lsp_run() { fprintf(stderr, "LSP not supported in this build\n"); }
int compile_source_to_llvm_ir() { return -1; }
int compile_source_to_llvm_executable() { return -1; }

void create_socket_module() {}
void create_tcp_module() {}
void create_http_module() {}
void create_ssl_module() {}
void create_graphics_module() {}
void create_ml_native_module() {}

/* GPU stubs */
void sgpu_cmd_bind_index_buffer() {}
void sgpu_cmd_set_viewport() {}
void sgpu_cmd_set_scissor() {}
void sgpu_cmd_draw_indexed() {}
void sgpu_cmd_draw() {}
void sgpu_submit_with_sync() {}
void sgpu_cmd_dispatch() {}
void sgpu_acquire_next_image() {}
void sgpu_wait_fence() {}
void sgpu_cmd_bind_descriptor_set() {}
void sgpu_cmd_push_constants() {}
void sgpu_update_uniform() {}

int sgpu_window_should_close() { return 0; }
double sgpu_get_time() { return 0; }
void sgpu_mouse_pos() { }
void sgpu_update_input() {}
void sgpu_poll_events() {}
void sgpu_mouse_delta() {}
int sgpu_key_pressed() { return 0; }
void sgpu_cmd_begin_render_pass() {}
void sgpu_cmd_end_render_pass() {}
void sgpu_cmd_bind_graphics_pipeline() {}
void sgpu_cmd_bind_vertex_buffer() {}
void sgpu_present() {}
void sgpu_reset_fence() {}
int sgpu_key_down() { return 0; }
void sgpu_begin_commands() {}
void sgpu_end_commands() {}
