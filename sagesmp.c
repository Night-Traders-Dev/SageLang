#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>

/* Sage AOT Runtime */
typedef struct { int type; union { double number; int boolean; const char* string; void* ptr; } as; } SageValue;
enum { SAGE_NIL=0, SAGE_NUM=1, SAGE_BOOL=2, SAGE_STR=3 };
static SageValue sage_number(double n) { SageValue v; v.type=SAGE_NUM; v.as.number=n; return v; }
static SageValue sage_bool(int b) { SageValue v; v.type=SAGE_BOOL; v.as.boolean=b; return v; }
static SageValue sage_string(const char* s) { SageValue v; v.type=SAGE_STR; v.as.string=s; return v; }
static SageValue sage_nil(void) { SageValue v; v.type=SAGE_NIL; return v; }
static int sage_truthy(SageValue v) { if(v.type==SAGE_NIL) return 0; if(v.type==SAGE_BOOL) return v.as.boolean; if(v.type==SAGE_NUM) return v.as.number!=0.0; return 1; }
static SageValue sage_str(SageValue v);  /* forward decl */
static SageValue sage_strcat(SageValue a, SageValue b);  /* forward decl */
static SageValue sage_add(SageValue a, SageValue b) { if(a.type==SAGE_NUM&&b.type==SAGE_NUM) return sage_number(a.as.number+b.as.number); if(a.type==SAGE_STR&&b.type==SAGE_STR) return sage_strcat(a,b); if(a.type==SAGE_STR||b.type==SAGE_STR){SageValue sa=sage_str(a),sb=sage_str(b);return sage_strcat(sa,sb);} return sage_nil(); }
static SageValue sage_sub(SageValue a, SageValue b) { return sage_number(a.as.number-b.as.number); }
static SageValue sage_mul(SageValue a, SageValue b) { return sage_number(a.as.number*b.as.number); }
static SageValue sage_div(SageValue a, SageValue b) { return sage_number(a.as.number/b.as.number); }
static SageValue sage_mod(SageValue a, SageValue b) { return sage_number(fmod(a.as.number,b.as.number)); }
static SageValue sage_eq(SageValue a, SageValue b) { if(a.type!=b.type) return sage_bool(0); if(a.type==SAGE_NIL) return sage_bool(1); if(a.type==SAGE_BOOL) return sage_bool(a.as.boolean==b.as.boolean); if(a.type==SAGE_NUM) return sage_bool(a.as.number==b.as.number); if(a.type==SAGE_STR) return sage_bool(strcmp(a.as.string,b.as.string)==0); return sage_bool(0); }
static SageValue sage_neq(SageValue a, SageValue b) { return sage_bool(!sage_eq(a,b).as.boolean); }
static SageValue sage_gt(SageValue a, SageValue b) { return sage_bool(a.as.number>b.as.number); }
static SageValue sage_lt(SageValue a, SageValue b) { return sage_bool(a.as.number<b.as.number); }
static SageValue sage_strcat(SageValue a, SageValue b) { if(a.type!=SAGE_STR||b.type!=SAGE_STR) return sage_nil(); size_t la=strlen(a.as.string),lb=strlen(b.as.string); char* r=malloc(la+lb+1); memcpy(r,a.as.string,la); memcpy(r+la,b.as.string,lb); r[la+lb]=0; SageValue v; v.type=SAGE_STR; v.as.string=r; return v; }

enum { SAGE_ARR=4, SAGE_DICT=5, SAGE_TUPLE=6 };
typedef struct { SageValue* elems; int count; int cap; } SageArr;
typedef struct { char** keys; SageValue* vals; int count; int cap; } SageDict;
static SageValue sage_array(int n, ...) { SageArr* a=malloc(sizeof(SageArr)); a->cap=n>4?n:4; a->count=n; a->elems=malloc(sizeof(SageValue)*a->cap); va_list ap; va_start(ap,n); for(int i=0;i<n;i++) a->elems[i]=va_arg(ap,SageValue); va_end(ap); SageValue v; v.type=SAGE_ARR; v.as.ptr=a; return v; }
static int sage_array_len(SageValue v) { if(v.type==SAGE_ARR) return ((SageArr*)v.as.ptr)->count; return 0; }
static SageValue sage_array_get(SageValue v, int i) { if(v.type==SAGE_ARR || v.type==SAGE_TUPLE){SageArr*a=(SageArr*)v.as.ptr; if(i>=0&&i<a->count) return a->elems[i];} return sage_nil(); }
static SageValue sage_index(SageValue c, SageValue i) { if(c.type==SAGE_ARR || c.type==SAGE_TUPLE) return sage_array_get(c,(int)i.as.number); if(c.type==SAGE_DICT){SageDict*d=(SageDict*)c.as.ptr; if(i.type==SAGE_STR) for(int k=0;k<d->count;k++) if(strcmp(d->keys[k],i.as.string)==0) return d->vals[k];} return sage_nil(); }
static SageValue sage_index_set(SageValue c, SageValue i, SageValue val) { if(c.type==SAGE_ARR){SageArr*a=(SageArr*)c.as.ptr; int idx=(int)i.as.number; if(idx>=0&&idx<a->count) a->elems[idx]=val;} if(c.type==SAGE_DICT){SageDict*d=(SageDict*)c.as.ptr; if(i.type==SAGE_STR){for(int k=0;k<d->count;k++) if(strcmp(d->keys[k],i.as.string)==0){d->vals[k]=val;return val;} if(d->count>=d->cap){d->cap=d->cap?d->cap*2:4;d->keys=realloc(d->keys,sizeof(char*)*d->cap);d->vals=realloc(d->vals,sizeof(SageValue)*d->cap);}d->keys[d->count]=strdup(i.as.string);d->vals[d->count]=val;d->count++;}} return val; }
static SageValue sage_dict(int n, ...) { SageDict*d=calloc(1,sizeof(SageDict)); d->cap=n>2?n:2; d->keys=malloc(sizeof(char*)*d->cap); d->vals=malloc(sizeof(SageValue)*d->cap); va_list ap; va_start(ap,n); for(int i=0;i<n;i++){d->keys[i]=strdup(va_arg(ap,const char*));d->vals[i]=va_arg(ap,SageValue);d->count++;} va_end(ap); SageValue v; v.type=SAGE_DICT; v.as.ptr=d; return v; }
static SageValue sage_tuple(int n, ...) { SageArr*a=malloc(sizeof(SageArr)); a->cap=n; a->count=n; a->elems=malloc(sizeof(SageValue)*n); va_list ap; va_start(ap,n); for(int i=0;i<n;i++) a->elems[i]=va_arg(ap,SageValue); va_end(ap); SageValue v; v.type=SAGE_TUPLE; v.as.ptr=a; return v; }
static SageValue sage_slice(SageValue c, SageValue s, SageValue e) { if(c.type!=SAGE_ARR) return sage_nil(); SageArr*a=(SageArr*)c.as.ptr; int si=(int)s.as.number,ei=e.type==SAGE_NIL?a->count:(int)e.as.number; if(si<0)si=0;if(ei>a->count)ei=a->count; int n=ei-si;if(n<0)n=0; return sage_array(0); /* simplified */ }
static void sage_push(SageValue arr, SageValue val) { if(arr.type==SAGE_ARR){SageArr*a=(SageArr*)arr.as.ptr;if(a->count>=a->cap){a->cap=a->cap?a->cap*2:4;a->elems=realloc(a->elems,sizeof(SageValue)*a->cap);}a->elems[a->count++]=val;} }
static SageValue sage_pop(SageValue arr) { if(arr.type==SAGE_ARR){SageArr*a=(SageArr*)arr.as.ptr;if(a->count>0)return a->elems[--a->count];} return sage_nil(); }
static SageValue sage_len(SageValue v) { if(v.type==SAGE_ARR) return sage_number(((SageArr*)v.as.ptr)->count); if(v.type==SAGE_STR) return sage_number(strlen(v.as.string)); if(v.type==SAGE_DICT) return sage_number(((SageDict*)v.as.ptr)->count); return sage_number(0); }
static SageValue sage_range(int n) { SageArr*a=malloc(sizeof(SageArr)); a->cap=n>4?n:4; a->count=n; a->elems=malloc(sizeof(SageValue)*a->cap); for(int i=0;i<n;i++) a->elems[i]=sage_number(i); SageValue v; v.type=SAGE_ARR; v.as.ptr=a; return v; }
static SageValue sage_get_property(SageValue obj, const char* name) { if(obj.type==SAGE_DICT){SageDict*d=(SageDict*)obj.as.ptr; for(int i=0;i<d->count;i++) if(strcmp(d->keys[i],name)==0) return d->vals[i];} return sage_nil(); }
static SageValue sage_dict_keys(SageValue d) { if(d.type!=SAGE_DICT) return sage_array(0); SageDict*dd=(SageDict*)d.as.ptr; SageArr*a=malloc(sizeof(SageArr)); a->cap=dd->count>4?dd->count:4; a->count=dd->count; a->elems=malloc(sizeof(SageValue)*a->cap); for(int i=0;i<dd->count;i++) a->elems[i]=sage_string(dd->keys[i]); SageValue v; v.type=SAGE_ARR; v.as.ptr=a; return v; }
static SageValue sage_str(SageValue v) { char buf[256]; switch(v.type){case SAGE_NUM:{double d=v.as.number;if(d==(double)(long long)d&&d>=-1e15&&d<=1e15)snprintf(buf,sizeof(buf),"%lld",(long long)d);else snprintf(buf,sizeof(buf),"%g",d);break;}case SAGE_STR:return v;case SAGE_BOOL:return sage_string(v.as.boolean?"true":"false");default:return sage_string("nil");}return sage_string(strdup(buf));}
static SageValue sage_tonumber(SageValue v) { if(v.type==SAGE_NUM)return v; if(v.type==SAGE_STR)return sage_number(atof(v.as.string)); return sage_number(0);}
static SageValue sage_type(SageValue v) { switch(v.type){case SAGE_NUM:return sage_string("number");case SAGE_STR:return sage_string("string");case SAGE_BOOL:return sage_string("bool");case SAGE_ARR:return sage_string("array");case SAGE_DICT:return sage_string("dict");default:return sage_string("nil");} }
static SageValue s_dict_has(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_DICT||a[1].type!=SAGE_STR)return sage_bool(0); SageDict*d=(SageDict*)a[0].as.ptr; for(int i=0;i<d->count;i++)if(strcmp(d->keys[i],a[1].as.string)==0)return sage_bool(1); return sage_bool(0); }
static SageValue s_dict_delete(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_DICT||a[1].type!=SAGE_STR)return sage_nil(); SageDict*d=(SageDict*)a[0].as.ptr; for(int i=0;i<d->count;i++)if(strcmp(d->keys[i],a[1].as.string)==0){SageValue v=d->vals[i];for(int j=i;j<d->count-1;j++){d->keys[j]=d->keys[j+1];d->vals[j]=d->vals[j+1];}d->count--;return v;} return sage_nil(); }
static SageValue s_gc_collect(int c, SageValue* a) { (void)c; (void)a; return sage_nil(); }
static SageValue s_range(int c, SageValue* a) { int n=0; if(c>0)n=(int)a[0].as.number; if(c>1)n=(int)a[1].as.number-(int)a[0].as.number; return sage_range(n>0?n:0); }
static SageValue s_input(int c, SageValue* a) { if(c>0&&a[0].type==SAGE_STR)fputs(a[0].as.string,stdout); char b[1024]; if(!fgets(b,sizeof(b),stdin))return sage_string(""); int l=strlen(b);if(l>0&&b[l-1]=='\n')b[l-1]=0; return sage_string(strdup(b)); }
static SageValue s_split(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_STR||a[1].type!=SAGE_STR)return sage_array(0); SageArr*r=malloc(sizeof(SageArr)); r->cap=16; r->count=0; r->elems=malloc(sizeof(SageValue)*r->cap); char*str=strdup(a[0].as.string); char*tok=strtok(str,a[1].as.string); while(tok){if(r->count>=r->cap){r->cap*=2;r->elems=realloc(r->elems,sizeof(SageValue)*r->cap);}r->elems[r->count++]=sage_string(strdup(tok)); tok=strtok(NULL,a[1].as.string);} free(str); SageValue v;v.type=SAGE_ARR;v.as.ptr=r;return v; }
static SageValue s_chr(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_NUM)return sage_string(""); char b[2]={(char)a[0].as.number,0}; return sage_string(strdup(b)); }
static SageValue s_join(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_ARR||a[1].type!=SAGE_STR)return sage_string(""); SageArr*arr=(SageArr*)a[0].as.ptr; if(arr->count==0)return sage_string(""); int len=0; for(int i=0;i<arr->count;i++){SageValue sa=sage_str(arr->elems[i]); len+=strlen(sa.as.string);} len+=strlen(a[1].as.string)*arr->count; char*b=malloc(len+1); b[0]=0; for(int i=0;i<arr->count;i++){SageValue sa=sage_str(arr->elems[i]); strcat(b,sa.as.string); if(i<arr->count-1)strcat(b,a[1].as.string);} SageValue v; v.type=SAGE_STR; v.as.string=b; return v; }
static SageValue s_replace(int c, SageValue* a) { if(c<3||a[0].type!=SAGE_STR||a[1].type!=SAGE_STR||a[2].type!=SAGE_STR)return a[0]; const char*str=a[0].as.string; const char*f=a[1].as.string; const char*r=a[2].as.string; if(strlen(f)==0)return a[0]; char*b=malloc(strlen(str)*4+1); b[0]=0; const char*p=str; while(1){const char*m=strstr(p,f); if(!m){strcat(b,p);break;} strncat(b,p,m-p); strcat(b,r); p=m+strlen(f);} SageValue v; v.type=SAGE_STR; v.as.string=b; return v; }
static SageValue s_clock(int c, SageValue* a) { (void)c; (void)a; return sage_number(1234.5); }
static SageValue s_ord(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR||strlen(a[0].as.string)==0)return sage_number(0); return sage_number((unsigned char)a[0].as.string[0]); }
static void sage_print_value(SageValue v) { switch(v.type) { case SAGE_NUM: { double d=v.as.number; if(d==(double)(long long)d&&d>=-1e15&&d<=1e15) printf("%lld",(long long)d); else printf("%g",d); break; } case SAGE_BOOL: fputs(v.as.boolean?"true":"false",stdout); break; case SAGE_STR: fputs(v.as.string,stdout); break; case SAGE_ARR: { SageArr*a=(SageArr*)v.as.ptr; printf("["); for(int i=0;i<a->count;i++){if(i)printf(", ");sage_print_value(a->elems[i]);} printf("]"); break; } case SAGE_DICT: { SageDict*d=(SageDict*)v.as.ptr; printf("{"); for(int i=0;i<d->count;i++){if(i)printf(", ");printf("\"%s\": ",d->keys[i]);sage_print_value(d->vals[i]);} printf("}"); break; } default: fputs("nil",stdout); } }

static SageValue s_substring(int argc, SageValue* argv);
static SageValue s_DQ;
static SageValue s_json_escape(int argc, SageValue* argv);
static SageValue s_json_encode(int argc, SageValue* argv);
static SageValue s_json_skip_ws(int argc, SageValue* argv);
static SageValue s_json_parse_value(int argc, SageValue* argv);
static SageValue s_json_decode(int argc, SageValue* argv);
static SageValue s_SMP_SECRET;
static SageValue s_RELAY_PORT;
static SageValue s_clients;
static SageValue s_clients_mutex;
static SageValue s_handle_client(int argc, SageValue* argv);
static SageValue s_status_printer(int argc, SageValue* argv);
static SageValue s_run_orangepi(int argc, SageValue* argv);
static SageValue s_ORANGEPI_HOST;
static SageValue s_ORANGEPI_PORT;
static SageValue s_CLIENT_ID;
static SageValue s_HEARTBEAT_INTERVAL;
static SageValue s_rpi2_read_sys_file(int argc, SageValue* argv);
static SageValue s_rpi2_stripnl(int argc, SageValue* argv);
static SageValue s_rpi2_get_cpu_temp(int argc, SageValue* argv);
static SageValue s_rpi2_get_cpu_load(int argc, SageValue* argv);
static SageValue s_rpi2_get_memory_info(int argc, SageValue* argv);
static SageValue s_get_pihole_info(int argc, SageValue* argv);
static SageValue s_rpi2_parse_mem_line(int argc, SageValue* argv);
static SageValue s_rpi2_get_dynamic_telemetry(int argc, SageValue* argv);
static SageValue s_get_rpi2_info(int argc, SageValue* argv);
static SageValue s_rpi2_send_heartbeat(int argc, SageValue* argv);
static SageValue s_run_rpi2(int argc, SageValue* argv);
static SageValue s_ORANGEPI_HOST;
static SageValue s_ORANGEPI_PORT;
static SageValue s_CLIENT_ID;
static SageValue s_HEARTBEAT_INTERVAL;
static SageValue s_rpi4_read_sys_file(int argc, SageValue* argv);
static SageValue s_rpi4_stripnl(int argc, SageValue* argv);
static SageValue s_rpi4_get_cpu_temp(int argc, SageValue* argv);
static SageValue s_rpi4_get_cpu_load(int argc, SageValue* argv);
static SageValue s_rpi4_get_memory_info(int argc, SageValue* argv);
static SageValue s_get_gpu_temp(int argc, SageValue* argv);
static SageValue s_get_throttling(int argc, SageValue* argv);
static SageValue s_get_services_info(int argc, SageValue* argv);
static SageValue s_get_compile_info(int argc, SageValue* argv);
static SageValue s_rpi4_parse_mem_line(int argc, SageValue* argv);
static SageValue s_rpi4_get_dynamic_telemetry(int argc, SageValue* argv);
static SageValue s_get_rpi4_info(int argc, SageValue* argv);
static SageValue s_rpi4_send_heartbeat(int argc, SageValue* argv);
static SageValue s_run_rpi4(int argc, SageValue* argv);
static SageValue s_SMP_VERSION;
static SageValue s_SMP_OP_HEARTBEAT;
static SageValue s_SMP_OP_MESSAGE;
static SageValue s_SMP_OP_JOIN;
static SageValue s_SMP_OP_LEAVE;
static SageValue s_SMP_OP_ASSIGN;
static SageValue s_SMP_OP_FORWARD;
static SageValue s_NODE_STATE_DISCONNECTED;
static SageValue s_NODE_STATE_CONNECTED;
static SageValue s_NODE_STATE_READY;
static SageValue s_DEFAULT_HOST;
static SageValue s_DEFAULT_PORT;
static SageValue s_DEFAULT_MAX_NODES;
static SageValue s_RTOS_MAX_TASKS;
static SageValue s_RTOS_MAX_PRIORITY;
static SageValue s_RTOS_GC_INTERVAL;
static SageValue s_TASK_READY;
static SageValue s_TASK_RUNNING;
static SageValue s_TASK_SLEEPING;
static SageValue s_TASK_BLOCKED;
static SageValue s_TASK_SUSPENDED;
static SageValue s_TASK_ACCEPT;
static SageValue s_TASK_MESSAGE;
static SageValue s_TASK_HEARTBEAT;
static SageValue s_rtos_tasks;
static SageValue s_rtos_task_count;
static SageValue s_rtos_current;
static SageValue s_rtos_tick;
static SageValue s_rtos_gc_ticks;
static SageValue s_rtos_running;
static SageValue s_rtos_init(int argc, SageValue* argv);
static SageValue s_rtos_task_create(int argc, SageValue* argv);
static SageValue s_rtos_sleep_task(int argc, SageValue* argv);
static SageValue s_rtos_suspend_task(int argc, SageValue* argv);
static SageValue s_rtos_resume_task(int argc, SageValue* argv);
static SageValue s_rtos_halt(int argc, SageValue* argv);
static SageValue s_rtos_print_tasks(int argc, SageValue* argv);
static SageValue s__simple_hash(int argc, SageValue* argv);
static SageValue s__generate_otp_key(int argc, SageValue* argv);
static SageValue s__sign(int argc, SageValue* argv);
static SageValue s__verify_sig(int argc, SageValue* argv);
static SageValue s__otp_encrypt(int argc, SageValue* argv);
static SageValue s__otp_decrypt(int argc, SageValue* argv);
static SageValue s_crypto_seal(int argc, SageValue* argv);
static SageValue s_crypto_open(int argc, SageValue* argv);
static SageValue s_router_state;
static SageValue s_router_mailboxes;
static SageValue s_router_conn_queue;
static SageValue s_mb_create(int argc, SageValue* argv);
static SageValue s_mb_send(int argc, SageValue* argv);
static SageValue s_mb_recv(int argc, SageValue* argv);
static SageValue s_mb_pending(int argc, SageValue* argv);
static SageValue s_router_register(int argc, SageValue* argv);
static SageValue s_router_unregister(int argc, SageValue* argv);
static SageValue s_router_route(int argc, SageValue* argv);
static SageValue s_task_body_accept(int argc, SageValue* argv);
static SageValue s_task_body_message(int argc, SageValue* argv);
static SageValue s_task_body_heartbeat(int argc, SageValue* argv);
static SageValue s_rtos_dispatch_task(int argc, SageValue* argv);
static SageValue s_rtos_tick_once(int argc, SageValue* argv);
static SageValue s_session;
static SageValue s_cmd_connect(int argc, SageValue* argv);
static SageValue s_cmd_disconnect(int argc, SageValue* argv);
static SageValue s_cmd_send(int argc, SageValue* argv);
static SageValue s_cmd_broadcast(int argc, SageValue* argv);
static SageValue s_cmd_recv_simulate(int argc, SageValue* argv);
static SageValue s__poll_router_mailbox(int argc, SageValue* argv);
static SageValue s_cmd_inbox(int argc, SageValue* argv);
static SageValue s_cmd_outbox(int argc, SageValue* argv);
static SageValue s_cmd_log(int argc, SageValue* argv);
static SageValue s_cmd_set_secret(int argc, SageValue* argv);
static SageValue s_cmd_set_otp_pass(int argc, SageValue* argv);
static SageValue s_cmd_set_otp_seed(int argc, SageValue* argv);
static SageValue s_cmd_show_crypto(int argc, SageValue* argv);
static SageValue s_relay_rules;
static SageValue s_relay_enabled;
static SageValue s_cmd_relay_on(int argc, SageValue* argv);
static SageValue s_cmd_relay_off(int argc, SageValue* argv);
static SageValue s_cmd_add_sender_rule(int argc, SageValue* argv);
static SageValue s_cmd_add_content_rule(int argc, SageValue* argv);
static SageValue s_cmd_remove_rule(int argc, SageValue* argv);
static SageValue s_cmd_list_rules(int argc, SageValue* argv);
static SageValue s__auto_relay_check(int argc, SageValue* argv);
static SageValue s_cmd_status(int argc, SageValue* argv);
static SageValue s_cmd_help(int argc, SageValue* argv);
static SageValue s__join_parts(int argc, SageValue* argv);
static SageValue s_dispatch(int argc, SageValue* argv);
static SageValue s_router_cmd_clients(int argc, SageValue* argv);
static SageValue s_router_cmd_queue(int argc, SageValue* argv);
static SageValue s_router_cmd_mailboxes(int argc, SageValue* argv);
static SageValue s_router_cmd_route(int argc, SageValue* argv);
static SageValue s_router_cmd_log(int argc, SageValue* argv);
static SageValue s_router_cmd_tasks(int argc, SageValue* argv);
static SageValue s_router_cmd_tick(int argc, SageValue* argv);
static SageValue s_router_cmd_status(int argc, SageValue* argv);
static SageValue s_router_cmd_help(int argc, SageValue* argv);
static SageValue s_router_dispatch(int argc, SageValue* argv);
static SageValue s__start_as_router;
static SageValue s_parse_args(int argc, SageValue* argv);
static SageValue s_run_router_shell(int argc, SageValue* argv);
static SageValue s_run_client_shell(int argc, SageValue* argv);
static SageValue s_main(int argc, SageValue* argv);
static SageValue s_ends_with(int argc, SageValue* argv);

static SageValue s_substring(int argc, SageValue* argv) {
    SageValue s_s = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_start = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_length = (argc > 2) ? argv[2] : sage_nil();
    SageValue s_res = sage_string("");
    { SageValue _iter_t0 = sage_range((int)s_length.as.number);
        for (int t0 = 0; t0 < sage_array_len(_iter_t0); t0++) {
            SageValue s_i = sage_array_get(_iter_t0, t0);
            if (sage_truthy(sage_lt(sage_add(s_start, s_i), sage_len(s_s)))) {
                (s_res = sage_add(s_res, sage_index(s_s, sage_add(s_start, s_i))));
            }
            sage_nil();
        }
    }
    sage_nil();
    return s_res;
    return sage_nil();
}

static SageValue s_json_escape(int argc, SageValue* argv) {
    SageValue s_s = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_r = ({ SageValue _args[3]; _args[0] = s_s; _args[1] = ({ SageValue _args[1]; _args[0] = sage_number(92); s_chr(1, _args); }); _args[2] = sage_add(({ SageValue _args[1]; _args[0] = sage_number(92); s_chr(1, _args); }), ({ SageValue _args[1]; _args[0] = sage_number(92); s_chr(1, _args); })); s_replace(3, _args); });
    (s_r = ({ SageValue _args[3]; _args[0] = s_r; _args[1] = ({ SageValue _args[1]; _args[0] = sage_number(34); s_chr(1, _args); }); _args[2] = sage_add(({ SageValue _args[1]; _args[0] = sage_number(92); s_chr(1, _args); }), ({ SageValue _args[1]; _args[0] = sage_number(34); s_chr(1, _args); })); s_replace(3, _args); }));
    (s_r = ({ SageValue _args[3]; _args[0] = s_r; _args[1] = ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); }); _args[2] = sage_add(({ SageValue _args[1]; _args[0] = sage_number(92); s_chr(1, _args); }), sage_string("n")); s_replace(3, _args); }));
    (s_r = ({ SageValue _args[3]; _args[0] = s_r; _args[1] = ({ SageValue _args[1]; _args[0] = sage_number(9); s_chr(1, _args); }); _args[2] = sage_add(({ SageValue _args[1]; _args[0] = sage_number(92); s_chr(1, _args); }), sage_string("t")); s_replace(3, _args); }));
    (s_r = ({ SageValue _args[3]; _args[0] = s_r; _args[1] = ({ SageValue _args[1]; _args[0] = sage_number(13); s_chr(1, _args); }); _args[2] = sage_add(({ SageValue _args[1]; _args[0] = sage_number(92); s_chr(1, _args); }), sage_string("r")); s_replace(3, _args); }));
    return s_r;
    return sage_nil();
}

static SageValue s_json_encode(int argc, SageValue* argv) {
    SageValue s_val = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_t = sage_type(s_val);
    if (sage_truthy(sage_eq(s_t, sage_string("nil")))) {
        return sage_string("null");
    }
    if (sage_truthy(sage_eq(s_t, sage_string("number")))) {
        return sage_str(s_val);
    }
    if (sage_truthy(sage_eq(s_t, sage_string("string")))) {
        return sage_add(sage_add(s_DQ, ({ SageValue _args[1]; _args[0] = s_val; s_json_escape(1, _args); })), s_DQ);
    }
    if (sage_truthy(sage_eq(s_t, sage_string("array")))) {
        SageValue s_parts = sage_array(1, sage_string("["));
        { SageValue _iter_t1 = sage_range((int)sage_len(s_val).as.number);
            for (int t1 = 0; t1 < sage_array_len(_iter_t1); t1++) {
                SageValue s_i = sage_array_get(_iter_t1, t1);
                if (sage_truthy(sage_gt(s_i, sage_number(0)))) {
                    (sage_push(s_parts, sage_string(",")), sage_nil());
                }
                (sage_push(s_parts, ({ SageValue _args[1]; _args[0] = sage_index(s_val, s_i); s_json_encode(1, _args); })), sage_nil());
            }
        }
        (sage_push(s_parts, sage_string("]")), sage_nil());
        return ({ SageValue _args[2]; _args[0] = s_parts; _args[1] = sage_string(""); s_join(2, _args); });
    }
    if (sage_truthy(sage_eq(s_t, sage_string("dict")))) {
        SageValue s_parts = sage_array(1, sage_string("{"));
        SageValue s_keys = sage_dict_keys(s_val);
        { SageValue _iter_t2 = sage_range((int)sage_len(s_keys).as.number);
            for (int t2 = 0; t2 < sage_array_len(_iter_t2); t2++) {
                SageValue s_i = sage_array_get(_iter_t2, t2);
                if (sage_truthy(sage_gt(s_i, sage_number(0)))) {
                    (sage_push(s_parts, sage_string(",")), sage_nil());
                }
                (sage_push(s_parts, sage_add(sage_add(sage_add(s_DQ, sage_index(s_keys, s_i)), s_DQ), sage_string(":"))), sage_nil());
                (sage_push(s_parts, ({ SageValue _args[1]; _args[0] = sage_index(s_val, sage_index(s_keys, s_i)); s_json_encode(1, _args); })), sage_nil());
            }
        }
        (sage_push(s_parts, sage_string("}")), sage_nil());
        return ({ SageValue _args[2]; _args[0] = s_parts; _args[1] = sage_string(""); s_join(2, _args); });
    }
    return sage_add(sage_add(s_DQ, ({ SageValue _args[1]; _args[0] = sage_str(s_val); s_json_escape(1, _args); })), s_DQ);
    return sage_nil();
}

static SageValue s_json_skip_ws(int argc, SageValue* argv) {
    SageValue s_raw = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_i = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_n = (argc > 2) ? argv[2] : sage_nil();
    while (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? (sage_truthy((sage_truthy((sage_truthy(sage_eq(sage_index(s_raw, s_i), sage_string(" "))) ? sage_eq(sage_index(s_raw, s_i), sage_string(" ")) : sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); })))) ? (sage_truthy(sage_eq(sage_index(s_raw, s_i), sage_string(" "))) ? sage_eq(sage_index(s_raw, s_i), sage_string(" ")) : sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); }))) : sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(13); s_chr(1, _args); })))) ? (sage_truthy((sage_truthy(sage_eq(sage_index(s_raw, s_i), sage_string(" "))) ? sage_eq(sage_index(s_raw, s_i), sage_string(" ")) : sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); })))) ? (sage_truthy(sage_eq(sage_index(s_raw, s_i), sage_string(" "))) ? sage_eq(sage_index(s_raw, s_i), sage_string(" ")) : sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); }))) : sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(13); s_chr(1, _args); }))) : sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(9); s_chr(1, _args); }))) : sage_lt(s_i, s_n)))) {
        (s_i = sage_add(s_i, sage_number(1)));
    }
    sage_nil();
    return s_i;
    return sage_nil();
}

static SageValue s_json_parse_value(int argc, SageValue* argv) {
    SageValue s_raw = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_i = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_n = (argc > 2) ? argv[2] : sage_nil();
    (s_i = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = s_i; _args[2] = s_n; s_json_skip_ws(3, _args); }));
    if (sage_truthy(sage_bool(s_i.as.number >= s_n.as.number))) {
        return sage_dict(2, "value", sage_nil(), "next", s_i);
    }
    sage_nil();
    SageValue s_c = sage_index(s_raw, s_i);
    if (sage_truthy(sage_eq(s_c, sage_string("{")))) {
        SageValue s_obj = sage_dict(0);
        (s_i = sage_add(s_i, sage_number(1)));
        (s_i = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = s_i; _args[2] = s_n; s_json_skip_ws(3, _args); }));
        if (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? sage_eq(sage_index(s_raw, s_i), sage_string("}")) : sage_lt(s_i, s_n)))) {
            return sage_dict(2, "value", s_obj, "next", sage_add(s_i, sage_number(1)));
        }
        sage_nil();
        while (sage_truthy(sage_lt(s_i, s_n))) {
            (s_i = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = s_i; _args[2] = s_n; s_json_skip_ws(3, _args); }));
            if (sage_truthy((sage_truthy(sage_bool(s_i.as.number >= s_n.as.number)) ? sage_bool(s_i.as.number >= s_n.as.number) : sage_eq(sage_index(s_raw, s_i), sage_string("}"))))) {
                break;
            }
            sage_nil();
            if (sage_truthy(sage_neq(sage_index(s_raw, s_i), s_DQ))) {
                return sage_dict(2, "value", sage_nil(), "next", s_i);
            }
            sage_nil();
            (s_i = sage_add(s_i, sage_number(1)));
            SageValue s_key = sage_string("");
            while (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? sage_neq(sage_index(s_raw, s_i), s_DQ) : sage_lt(s_i, s_n)))) {
                if (sage_truthy(sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(92); s_chr(1, _args); })))) {
                    (s_i = sage_add(s_i, sage_number(1)));
                }
                sage_nil();
                (s_key = sage_add(s_key, sage_index(s_raw, s_i)));
                (s_i = sage_add(s_i, sage_number(1)));
            }
            sage_nil();
            (s_i = sage_add(s_i, sage_number(1)));
            (s_i = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = s_i; _args[2] = s_n; s_json_skip_ws(3, _args); }));
            while (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? sage_eq(sage_index(s_raw, s_i), sage_string(":")) : sage_lt(s_i, s_n)))) {
                (s_i = sage_add(s_i, sage_number(1)));
            }
            sage_nil();
            SageValue s_res = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = s_i; _args[2] = s_n; s_json_parse_value(3, _args); });
            sage_index_set(s_obj, s_key, sage_index(s_res, sage_string("value")));
            (s_i = sage_index(s_res, sage_string("next")));
            (s_i = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = s_i; _args[2] = s_n; s_json_skip_ws(3, _args); }));
            while (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? sage_eq(sage_index(s_raw, s_i), sage_string(",")) : sage_lt(s_i, s_n)))) {
                (s_i = sage_add(s_i, sage_number(1)));
            }
            sage_nil();
        }
        sage_nil();
        if (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? sage_eq(sage_index(s_raw, s_i), sage_string("}")) : sage_lt(s_i, s_n)))) {
            (s_i = sage_add(s_i, sage_number(1)));
        }
        sage_nil();
        return sage_dict(2, "value", s_obj, "next", s_i);
    } else {
        if (sage_truthy(sage_eq(s_c, sage_string("[")))) {
            SageValue s_arr = sage_array(0);
            (s_i = sage_add(s_i, sage_number(1)));
            (s_i = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = s_i; _args[2] = s_n; s_json_skip_ws(3, _args); }));
            if (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? sage_eq(sage_index(s_raw, s_i), sage_string("]")) : sage_lt(s_i, s_n)))) {
                return sage_dict(2, "value", s_arr, "next", sage_add(s_i, sage_number(1)));
            }
            sage_nil();
            while (sage_truthy(sage_lt(s_i, s_n))) {
                (s_i = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = s_i; _args[2] = s_n; s_json_skip_ws(3, _args); }));
                if (sage_truthy((sage_truthy(sage_bool(s_i.as.number >= s_n.as.number)) ? sage_bool(s_i.as.number >= s_n.as.number) : sage_eq(sage_index(s_raw, s_i), sage_string("]"))))) {
                    break;
                }
                sage_nil();
                SageValue s_res = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = s_i; _args[2] = s_n; s_json_parse_value(3, _args); });
                (sage_push(s_arr, sage_index(s_res, sage_string("value"))), sage_nil());
                (s_i = sage_index(s_res, sage_string("next")));
                (s_i = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = s_i; _args[2] = s_n; s_json_skip_ws(3, _args); }));
                while (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? sage_eq(sage_index(s_raw, s_i), sage_string(",")) : sage_lt(s_i, s_n)))) {
                    (s_i = sage_add(s_i, sage_number(1)));
                }
                sage_nil();
            }
            sage_nil();
            if (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? sage_eq(sage_index(s_raw, s_i), sage_string("]")) : sage_lt(s_i, s_n)))) {
                (s_i = sage_add(s_i, sage_number(1)));
            }
            sage_nil();
            return sage_dict(2, "value", s_arr, "next", s_i);
        } else {
            if (sage_truthy(sage_eq(s_c, s_DQ))) {
                (s_i = sage_add(s_i, sage_number(1)));
                SageValue s_s = sage_string("");
                while (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? sage_neq(sage_index(s_raw, s_i), s_DQ) : sage_lt(s_i, s_n)))) {
                    if (sage_truthy(sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(92); s_chr(1, _args); })))) {
                        (s_i = sage_add(s_i, sage_number(1)));
                        if (sage_truthy(sage_lt(s_i, s_n))) {
                            SageValue s_ec = sage_index(s_raw, s_i);
                            if (sage_truthy(sage_eq(s_ec, sage_string("n")))) {
                                (s_s = sage_add(s_s, ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); })));
                            } else {
                                if (sage_truthy(sage_eq(s_ec, sage_string("t")))) {
                                    (s_s = sage_add(s_s, ({ SageValue _args[1]; _args[0] = sage_number(9); s_chr(1, _args); })));
                                } else {
                                    if (sage_truthy(sage_eq(s_ec, sage_string("r")))) {
                                        (s_s = sage_add(s_s, ({ SageValue _args[1]; _args[0] = sage_number(13); s_chr(1, _args); })));
                                    } else {
                                        (s_s = sage_add(sage_add(s_s, ({ SageValue _args[1]; _args[0] = sage_number(92); s_chr(1, _args); })), s_ec));
                                    }
                                }
                            }
                            sage_nil();
                            (s_i = sage_add(s_i, sage_number(1)));
                        }
                        sage_nil();
                    } else {
                        (s_s = sage_add(s_s, sage_index(s_raw, s_i)));
                        (s_i = sage_add(s_i, sage_number(1)));
                    }
                    sage_nil();
                }
                sage_nil();
                if (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? sage_eq(sage_index(s_raw, s_i), s_DQ) : sage_lt(s_i, s_n)))) {
                    (s_i = sage_add(s_i, sage_number(1)));
                }
                sage_nil();
                return sage_dict(2, "value", s_s, "next", s_i);
            } else {
                if (sage_truthy(sage_eq(s_c, sage_string("t")))) {
                    return sage_dict(2, "value", sage_number(1), "next", sage_add(s_i, sage_number(4)));
                } else {
                    if (sage_truthy(sage_eq(s_c, sage_string("f")))) {
                        return sage_dict(2, "value", sage_number(0), "next", sage_add(s_i, sage_number(5)));
                    } else {
                        if (sage_truthy(sage_eq(s_c, sage_string("n")))) {
                            return sage_dict(2, "value", sage_nil(), "next", sage_add(s_i, sage_number(4)));
                        } else {
                            SageValue s_num_str = sage_string("");
                            while (sage_truthy((sage_truthy(sage_lt(s_i, s_n)) ? (sage_truthy((sage_truthy((sage_truthy((sage_truthy((sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string(".")))) ? (sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string("."))) : sage_eq(sage_index(s_raw, s_i), sage_string("-")))) ? (sage_truthy((sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string(".")))) ? (sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string("."))) : sage_eq(sage_index(s_raw, s_i), sage_string("-"))) : sage_eq(sage_index(s_raw, s_i), sage_string("+")))) ? (sage_truthy((sage_truthy((sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string(".")))) ? (sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string("."))) : sage_eq(sage_index(s_raw, s_i), sage_string("-")))) ? (sage_truthy((sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string(".")))) ? (sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string("."))) : sage_eq(sage_index(s_raw, s_i), sage_string("-"))) : sage_eq(sage_index(s_raw, s_i), sage_string("+"))) : sage_eq(sage_index(s_raw, s_i), sage_string("e")))) ? (sage_truthy((sage_truthy((sage_truthy((sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string(".")))) ? (sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string("."))) : sage_eq(sage_index(s_raw, s_i), sage_string("-")))) ? (sage_truthy((sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string(".")))) ? (sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string("."))) : sage_eq(sage_index(s_raw, s_i), sage_string("-"))) : sage_eq(sage_index(s_raw, s_i), sage_string("+")))) ? (sage_truthy((sage_truthy((sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string(".")))) ? (sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string("."))) : sage_eq(sage_index(s_raw, s_i), sage_string("-")))) ? (sage_truthy((sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string(".")))) ? (sage_truthy((sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number))) ? (sage_truthy(sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) ? sage_bool(sage_index(s_raw, s_i).as.number <= sage_string("9").as.number) : sage_bool(sage_index(s_raw, s_i).as.number >= sage_string("0").as.number)) : sage_eq(sage_index(s_raw, s_i), sage_string("."))) : sage_eq(sage_index(s_raw, s_i), sage_string("-"))) : sage_eq(sage_index(s_raw, s_i), sage_string("+"))) : sage_eq(sage_index(s_raw, s_i), sage_string("e"))) : sage_eq(sage_index(s_raw, s_i), sage_string("E"))) : sage_lt(s_i, s_n)))) {
                                (s_num_str = sage_add(s_num_str, sage_index(s_raw, s_i)));
                                (s_i = sage_add(s_i, sage_number(1)));
                            }
                            sage_nil();
                            if (sage_truthy(sage_gt(sage_len(s_num_str), sage_number(0)))) {
                                return sage_dict(2, "value", sage_tonumber(s_num_str), "next", s_i);
                            }
                            sage_nil();
                            return sage_dict(2, "value", sage_nil(), "next", s_i);
                        }
                    }
                }
            }
        }
    }
    sage_nil();
    return sage_nil();
}

static SageValue s_json_decode(int argc, SageValue* argv) {
    SageValue s_raw = (argc > 0) ? argv[0] : sage_nil();
    if (sage_truthy((sage_truthy(sage_eq(s_raw, sage_nil())) ? sage_eq(s_raw, sage_nil()) : sage_eq(sage_len(s_raw), sage_number(0))))) {
        return sage_nil();
    }
    sage_nil();
    SageValue s_n = sage_len(s_raw);
    SageValue s_res = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = sage_number(0); _args[2] = s_n; s_json_parse_value(3, _args); });
    return sage_index(s_res, sage_string("value"));
    return sage_nil();
}

static SageValue s_handle_client(int argc, SageValue* argv) {
    SageValue s_client_fd = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_raw = sage_nil() /* unsupported call: sage_get_property(s_tcp, "recv") */;
    if (sage_truthy((sage_truthy(sage_eq(s_raw, sage_nil())) ? sage_eq(s_raw, sage_nil()) : sage_eq(sage_len(s_raw), sage_number(0))))) {
        sage_nil() /* unsupported call: sage_get_property(s_tcp, "close") */;
        return sage_nil();
    }
    sage_nil();
    SageValue s_msg = ({ SageValue _args[1]; _args[0] = s_raw; s_json_decode(1, _args); });
    if (sage_truthy(sage_eq(s_msg, sage_nil()))) {
        sage_nil() /* unsupported call: sage_get_property(s_tcp, "sendall") */;
        sage_nil() /* unsupported call: sage_get_property(s_tcp, "close") */;
        return sage_nil();
    }
    sage_nil();
    SageValue s_cid = sage_index(s_msg, sage_string("client_id"));
    SageValue s_platform = sage_index(s_msg, sage_string("platform"));
    SageValue s_info_str = sage_index(s_msg, sage_string("info"));
    sage_nil() /* unsupported call: sage_get_property(s_thread, "lock") */;
    sage_index_set(s_clients, sage_str(s_cid), sage_dict(4, "id", s_cid, "platform", s_platform, "info", s_info_str, "last_seen", ({ SageValue _args[1]; s_clock(0, _args); })));
    SageValue s_count = sage_len(sage_dict_keys(s_clients));
    sage_nil() /* unsupported call: sage_get_property(s_thread, "unlock") */;
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("[HEARTBEAT] "), s_platform), sage_string(" (id=")), sage_str(s_cid)), sage_string(") -> ")), s_info_str)); printf("\n");
    SageValue s_services = sage_index(s_msg, sage_string("services"));
    if (sage_truthy(sage_neq(s_services, sage_nil()))) {
        sage_print_value(sage_add(sage_add(sage_add(sage_string("[SERVICES] "), s_platform), sage_string(" -> ")), ({ SageValue _args[1]; _args[0] = s_services; s_json_encode(1, _args); }))); printf("\n");
    }
    sage_nil();
    SageValue s_compile = sage_index(s_msg, sage_string("compile"));
    if (sage_truthy(sage_neq(s_compile, sage_nil()))) {
        sage_print_value(sage_add(sage_add(sage_add(sage_string("[COMPILE] "), s_platform), sage_string(" -> ")), ({ SageValue _args[1]; _args[0] = s_compile; s_json_encode(1, _args); }))); printf("\n");
    }
    sage_nil();
    SageValue s_resp = sage_add(sage_add(sage_add(sage_add(sage_string("{\"status\":\"ok\",\"node_count\":"), sage_str(s_count)), sage_string(",\"server_ts\":")), sage_str(({ SageValue _args[1]; s_clock(0, _args); }))), sage_string("}"));
    sage_nil() /* unsupported call: sage_get_property(s_tcp, "sendall") */;
    sage_nil() /* unsupported call: sage_get_property(s_tcp, "recv") */;
    sage_nil() /* unsupported call: sage_get_property(s_tcp, "close") */;
    return sage_nil();
}

static SageValue s_status_printer(int argc, SageValue* argv) {
    SageValue s__ = (argc > 0) ? argv[0] : sage_nil();
    while (sage_truthy(sage_bool(1))) {
        sage_nil() /* unsupported call: sage_get_property(s_thread, "sleep") */;
        sage_nil() /* unsupported call: sage_get_property(s_thread, "lock") */;
        sage_print_value(sage_string("=== OrangePi Relay Status ===")); printf("\n");
        SageValue s_ids = sage_dict_keys(s_clients);
        sage_print_value(sage_add(sage_string("Connected clients: "), sage_str(sage_len(s_ids)))); printf("\n");
        { SageValue _iter_t3 = sage_range((int)sage_len(s_ids).as.number);
            for (int t3 = 0; t3 < sage_array_len(_iter_t3); t3++) {
                SageValue s_i = sage_array_get(_iter_t3, t3);
                SageValue s_c = sage_index(s_clients, sage_index(s_ids, s_i));
                sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  ["), sage_index(s_c, sage_string("platform"))), sage_string("] id=")), sage_str(sage_index(s_c, sage_string("id")))), sage_string(" last_seen=")), sage_str(sage_index(s_c, sage_string("last_seen")))), sage_string(" -> ")), sage_index(s_c, sage_string("info")))); printf("\n");
            }
        }
        sage_nil();
        sage_nil() /* unsupported call: sage_get_property(s_thread, "unlock") */;
    }
    sage_nil();
    return sage_nil();
}

static SageValue s_run_orangepi(int argc, SageValue* argv) {
    SageValue s_mode_idx = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_argv = sage_nil() /* unsupported call: sage_get_property(s_sys, "args") */;
    if (sage_truthy(sage_bool(sage_len(s_argv).as.number >= sage_add(s_mode_idx, sage_number(2)).as.number))) {
        (s_RELAY_PORT = sage_tonumber(sage_index(s_argv, sage_add(s_mode_idx, sage_number(1)))));
    }
    sage_nil();
    SageValue s_port_str = sage_nil() /* unsupported call: sage_get_property(s_sys, "getenv") */;
    SageValue s_port = s_RELAY_PORT;
    if (sage_truthy(sage_neq(s_port_str, sage_nil()))) {
        (s_port = sage_tonumber(s_port_str));
    }
    sage_nil();
    sage_print_value(sage_string("=== OrangePi Relay Server (Real TCP) ===")); printf("\n");
    sage_print_value(sage_add(sage_string("Listening on 0.0.0.0:"), sage_str(s_port))); printf("\n");
    SageValue s_listener = sage_nil() /* unsupported call: sage_get_property(s_tcp, "listen") */;
    if (sage_truthy(sage_eq(s_listener, sage_number(sage_number(0).as.number - sage_number(1).as.number)))) {
        sage_print_value(sage_add(sage_string("FATAL: Cannot listen on port "), sage_str(s_port))); printf("\n");
        return sage_nil();
    }
    sage_nil();
    sage_nil() /* unsupported call: sage_get_property(s_thread, "spawn") */;
    while (sage_truthy(sage_bool(1))) {
        SageValue s_client_fd = sage_nil() /* unsupported call: sage_get_property(s_tcp, "accept") */;
        if (sage_truthy(sage_neq(s_client_fd, sage_number(sage_number(0).as.number - sage_number(1).as.number)))) {
            sage_nil() /* unsupported call: sage_get_property(s_thread, "spawn") */;
        }
        sage_nil();
    }
    sage_nil();
    sage_nil() /* unsupported call: sage_get_property(s_tcp, "close") */;
    return sage_nil();
}

static SageValue s_rpi2_read_sys_file(int argc, SageValue* argv) {
    SageValue s_path = (argc > 0) ? argv[0] : sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(sage_nil() /* unsupported call: sage_get_property(s_io, "exists") */)))) {
        return sage_nil();
    }
    return sage_nil() /* unsupported call: sage_get_property(s_io, "readfile") */;
    return sage_nil();
}

static SageValue s_rpi2_stripnl(int argc, SageValue* argv) {
    SageValue s_s = (argc > 0) ? argv[0] : sage_nil();
    return ({ SageValue _args[3]; _args[0] = ({ SageValue _args[3]; _args[0] = s_s; _args[1] = ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); }); _args[2] = sage_string(""); s_replace(3, _args); }); _args[1] = ({ SageValue _args[1]; _args[0] = sage_number(13); s_chr(1, _args); }); _args[2] = sage_string(""); s_replace(3, _args); });
    return sage_nil();
}

static SageValue s_rpi2_get_cpu_temp(int argc, SageValue* argv) {
    SageValue s_raw = ({ SageValue _args[1]; _args[0] = sage_string("/sys/class/thermal/thermal_zone0/temp"); s_rpi2_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_raw, sage_nil()))) {
        SageValue s_cleaned = ({ SageValue _args[1]; _args[0] = s_raw; s_rpi2_stripnl(1, _args); });
        SageValue s_millideg = sage_tonumber(s_cleaned);
        if (sage_truthy(sage_neq(s_millideg, sage_nil()))) {
            return sage_div(s_millideg, sage_number(1000));
        }
        sage_nil();
    }
    sage_nil();
    return sage_add(sage_number(45), sage_mod(({ SageValue _args[1]; s_clock(0, _args); }), sage_number(5)));
    return sage_nil();
}

static SageValue s_rpi2_get_cpu_load(int argc, SageValue* argv) {
    SageValue s_raw = ({ SageValue _args[1]; _args[0] = sage_string("/proc/loadavg"); s_rpi2_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_raw, sage_nil()))) {
        SageValue s_parts = sage_array(0);
        SageValue s_cur = sage_string("");
        { SageValue _iter_t4 = sage_range((int)sage_len(s_raw).as.number);
            for (int t4 = 0; t4 < sage_array_len(_iter_t4); t4++) {
                SageValue s_i = sage_array_get(_iter_t4, t4);
                if (sage_truthy(sage_eq(sage_index(s_raw, s_i), sage_string(" ")))) {
                    (sage_push(s_parts, s_cur), sage_nil());
                    (s_cur = sage_string(""));
                } else {
                    (s_cur = sage_add(s_cur, sage_index(s_raw, s_i)));
                }
            }
        }
        if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
            (sage_push(s_parts, s_cur), sage_nil());
        }
        if (sage_truthy(sage_bool(sage_len(s_parts).as.number >= sage_number(1).as.number))) {
            SageValue s_load = sage_tonumber(sage_index(s_parts, sage_number(0)));
            if (sage_truthy(sage_neq(s_load, sage_nil()))) {
                return s_load;
            }
            sage_nil();
        }
        sage_nil();
    }
    sage_nil();
    return sage_add(sage_number(0.40000000000000002), sage_div(sage_mod(({ SageValue _args[1]; s_clock(0, _args); }), sage_number(10)), sage_number(100)));
    return sage_nil();
}

static SageValue s_rpi2_get_memory_info(int argc, SageValue* argv) {
    SageValue s_raw = ({ SageValue _args[1]; _args[0] = sage_string("/proc/meminfo"); s_rpi2_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_raw, sage_nil()))) {
        SageValue s_lines = sage_array(0);
        SageValue s_cur = sage_string("");
        { SageValue _iter_t5 = sage_range((int)sage_len(s_raw).as.number);
            for (int t5 = 0; t5 < sage_array_len(_iter_t5); t5++) {
                SageValue s_i = sage_array_get(_iter_t5, t5);
                if (sage_truthy(sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); })))) {
                    (sage_push(s_lines, s_cur), sage_nil());
                    (s_cur = sage_string(""));
                } else {
                    (s_cur = sage_add(s_cur, sage_index(s_raw, s_i)));
                }
            }
        }
        if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
            (sage_push(s_lines, s_cur), sage_nil());
        }
        if (sage_truthy(sage_bool(sage_len(s_lines).as.number >= sage_number(2).as.number))) {
            SageValue s_mem_avail = sage_index(s_lines, sage_number(1));
            SageValue s_parts = sage_array(0);
            (s_cur = sage_string(""));
            { SageValue _iter_t6 = sage_range((int)sage_len(s_mem_avail).as.number);
                for (int t6 = 0; t6 < sage_array_len(_iter_t6); t6++) {
                    SageValue s_i = sage_array_get(_iter_t6, t6);
                    if (sage_truthy(sage_eq(sage_index(s_mem_avail, s_i), sage_string(" ")))) {
                        if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
                            (sage_push(s_parts, s_cur), sage_nil());
                        }
                        (s_cur = sage_string(""));
                    } else {
                        (s_cur = sage_add(s_cur, sage_index(s_mem_avail, s_i)));
                    }
                }
            }
            if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
                (sage_push(s_parts, s_cur), sage_nil());
            }
            if (sage_truthy(sage_bool(sage_len(s_parts).as.number >= sage_number(2).as.number))) {
                return sage_add(sage_add(sage_string("Available: "), sage_index(s_parts, sage_number(1))), sage_string("kB"));
            }
            sage_nil();
        }
        sage_nil();
    }
    sage_nil();
    return sage_string("Available: 768MB");
    return sage_nil();
}

static SageValue s_get_pihole_info(int argc, SageValue* argv) {
    SageValue s_raw = sage_nil() /* unsupported call: sage_get_property(s_io, "readfile") */;
    if (sage_truthy(sage_eq(s_raw, sage_nil()))) {
        return sage_nil();
    }
    sage_nil();
    SageValue s_cleaned = ({ SageValue _args[3]; _args[0] = ({ SageValue _args[3]; _args[0] = s_raw; _args[1] = ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); }); _args[2] = sage_string(""); s_replace(3, _args); }); _args[1] = ({ SageValue _args[1]; _args[0] = sage_number(13); s_chr(1, _args); }); _args[2] = sage_string(""); s_replace(3, _args); });
    return ({ SageValue _args[1]; _args[0] = s_cleaned; s_json_decode(1, _args); });
    return sage_nil();
}

static SageValue s_rpi2_parse_mem_line(int argc, SageValue* argv) {
    SageValue s_line = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_parts = sage_array(0);
    SageValue s_cur = sage_string("");
    { SageValue _iter_t7 = sage_range((int)sage_len(s_line).as.number);
        for (int t7 = 0; t7 < sage_array_len(_iter_t7); t7++) {
            SageValue s_i = sage_array_get(_iter_t7, t7);
            SageValue s_c = sage_index(s_line, s_i);
            if (sage_truthy((sage_truthy((sage_truthy(sage_eq(s_c, sage_string(" "))) ? sage_eq(s_c, sage_string(" ")) : sage_eq(s_c, sage_string(":")))) ? (sage_truthy(sage_eq(s_c, sage_string(" "))) ? sage_eq(s_c, sage_string(" ")) : sage_eq(s_c, sage_string(":"))) : sage_eq(s_c, ({ SageValue _args[1]; _args[0] = sage_number(9); s_chr(1, _args); }))))) {
                if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
                    (sage_push(s_parts, s_cur), sage_nil());
                }
                sage_nil();
                (s_cur = sage_string(""));
            } else {
                (s_cur = sage_add(s_cur, s_c));
            }
            sage_nil();
        }
    }
    sage_nil();
    if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
        (sage_push(s_parts, s_cur), sage_nil());
    }
    sage_nil();
    if (sage_truthy(sage_bool(sage_len(s_parts).as.number >= sage_number(2).as.number))) {
        return sage_tonumber(sage_index(s_parts, sage_number(1)));
    }
    sage_nil();
    return sage_nil();
    return sage_nil();
}

static SageValue s_rpi2_get_dynamic_telemetry(int argc, SageValue* argv) {
    SageValue s_telem = sage_dict(0);
    SageValue s_temp_raw = ({ SageValue _args[1]; _args[0] = sage_string("/sys/class/thermal/thermal_zone0/temp"); s_rpi2_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_temp_raw, sage_nil()))) {
        SageValue s_temp_num = sage_tonumber(({ SageValue _args[1]; _args[0] = s_temp_raw; s_rpi2_stripnl(1, _args); }));
        if (sage_truthy(sage_neq(s_temp_num, sage_nil()))) {
            sage_index_set(s_telem, sage_string("cpu_temp"), sage_div(s_temp_num, sage_number(1000)));
        }
        sage_nil();
    }
    sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_telem; _args[1] = sage_string("cpu_temp"); s_dict_has(2, _args); }))))) {
        sage_index_set(s_telem, sage_string("cpu_temp"), sage_number(42));
    }
    sage_nil();
    SageValue s_load_raw = ({ SageValue _args[1]; _args[0] = sage_string("/proc/loadavg"); s_rpi2_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_load_raw, sage_nil()))) {
        SageValue s_parts = sage_array(0);
        SageValue s_cur = sage_string("");
        { SageValue _iter_t8 = sage_range((int)sage_len(s_load_raw).as.number);
            for (int t8 = 0; t8 < sage_array_len(_iter_t8); t8++) {
                SageValue s_i = sage_array_get(_iter_t8, t8);
                if (sage_truthy(sage_eq(sage_index(s_load_raw, s_i), sage_string(" ")))) {
                    if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
                        (sage_push(s_parts, s_cur), sage_nil());
                    }
                    sage_nil();
                    (s_cur = sage_string(""));
                } else {
                    (s_cur = sage_add(s_cur, sage_index(s_load_raw, s_i)));
                }
                sage_nil();
            }
        }
        sage_nil();
        if (sage_truthy(sage_bool(sage_len(s_parts).as.number >= sage_number(1).as.number))) {
            SageValue s_load_val = sage_tonumber(sage_index(s_parts, sage_number(0)));
            if (sage_truthy(sage_neq(s_load_val, sage_nil()))) {
                sage_index_set(s_telem, sage_string("cpu_load"), s_load_val);
            }
            sage_nil();
        }
        sage_nil();
    }
    sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_telem; _args[1] = sage_string("cpu_load"); s_dict_has(2, _args); }))))) {
        sage_index_set(s_telem, sage_string("cpu_load"), sage_number(0.25));
    }
    sage_nil();
    SageValue s_freq_raw = ({ SageValue _args[1]; _args[0] = sage_string("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"); s_rpi2_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_freq_raw, sage_nil()))) {
        SageValue s_freq_num = sage_tonumber(({ SageValue _args[1]; _args[0] = s_freq_raw; s_rpi2_stripnl(1, _args); }));
        if (sage_truthy(sage_neq(s_freq_num, sage_nil()))) {
            sage_index_set(s_telem, sage_string("cpu_mhz"), sage_div(s_freq_num, sage_number(1000)));
        }
        sage_nil();
    }
    sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_telem; _args[1] = sage_string("cpu_mhz"); s_dict_has(2, _args); }))))) {
        sage_index_set(s_telem, sage_string("cpu_mhz"), sage_number(800));
    }
    sage_nil();
    SageValue s_mem_raw = ({ SageValue _args[1]; _args[0] = sage_string("/proc/meminfo"); s_rpi2_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_mem_raw, sage_nil()))) {
        SageValue s_lines = sage_array(0);
        SageValue s_cur = sage_string("");
        { SageValue _iter_t9 = sage_range((int)sage_len(s_mem_raw).as.number);
            for (int t9 = 0; t9 < sage_array_len(_iter_t9); t9++) {
                SageValue s_i = sage_array_get(_iter_t9, t9);
                SageValue s_c = sage_index(s_mem_raw, s_i);
                if (sage_truthy(sage_eq(s_c, ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); })))) {
                    (sage_push(s_lines, s_cur), sage_nil());
                    (s_cur = sage_string(""));
                } else {
                    (s_cur = sage_add(s_cur, s_c));
                }
                sage_nil();
            }
        }
        sage_nil();
        if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
            (sage_push(s_lines, s_cur), sage_nil());
        }
        sage_nil();
        SageValue s_total_kb = sage_nil();
        SageValue s_avail_kb = sage_nil();
        { SageValue _iter_t10 = sage_range((int)sage_len(s_lines).as.number);
            for (int t10 = 0; t10 < sage_array_len(_iter_t10); t10++) {
                SageValue s_i = sage_array_get(_iter_t10, t10);
                SageValue s_line = sage_index(s_lines, s_i);
                if (sage_truthy((sage_truthy(sage_bool(sage_len(s_line).as.number >= sage_number(8).as.number)) ? sage_eq(({ SageValue _args[3]; _args[0] = s_line; _args[1] = sage_number(0); _args[2] = sage_number(8); s_substring(3, _args); }), sage_string("MemTotal")) : sage_bool(sage_len(s_line).as.number >= sage_number(8).as.number)))) {
                    (s_total_kb = ({ SageValue _args[1]; _args[0] = s_line; s_rpi2_parse_mem_line(1, _args); }));
                } else {
                    if (sage_truthy((sage_truthy(sage_bool(sage_len(s_line).as.number >= sage_number(12).as.number)) ? sage_eq(({ SageValue _args[3]; _args[0] = s_line; _args[1] = sage_number(0); _args[2] = sage_number(12); s_substring(3, _args); }), sage_string("MemAvailable")) : sage_bool(sage_len(s_line).as.number >= sage_number(12).as.number)))) {
                        (s_avail_kb = ({ SageValue _args[1]; _args[0] = s_line; s_rpi2_parse_mem_line(1, _args); }));
                    }
                }
                sage_nil();
            }
        }
        sage_nil();
        if (sage_truthy(sage_neq(s_total_kb, sage_nil()))) {
            sage_index_set(s_telem, sage_string("ram_total_mb"), sage_div(s_total_kb, sage_number(1024)));
        }
        sage_nil();
        if (sage_truthy(sage_neq(s_avail_kb, sage_nil()))) {
            sage_index_set(s_telem, sage_string("ram_avail_mb"), sage_div(s_avail_kb, sage_number(1024)));
        }
        sage_nil();
    }
    sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_telem; _args[1] = sage_string("ram_total_mb"); s_dict_has(2, _args); }))))) {
        sage_index_set(s_telem, sage_string("ram_total_mb"), sage_number(1024));
    }
    sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_telem; _args[1] = sage_string("ram_avail_mb"); s_dict_has(2, _args); }))))) {
        sage_index_set(s_telem, sage_string("ram_avail_mb"), sage_number(768));
    }
    sage_nil();
    return s_telem;
    return sage_nil();
}

static SageValue s_get_rpi2_info(int argc, SageValue* argv) {
    SageValue s_telem = ({ SageValue _args[1]; s_rpi2_get_dynamic_telemetry(0, _args); });
    return sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("Temp: "), sage_str(sage_index(s_telem, sage_string("cpu_temp")))), sage_string("C, Load: ")), sage_str(sage_index(s_telem, sage_string("cpu_load")))), sage_string(", Available: ")), sage_str(sage_index(s_telem, sage_string("ram_avail_mb")))), sage_string("MB, CpuFreq: ")), sage_str(sage_index(s_telem, sage_string("cpu_mhz")))), sage_string("MHz, TotalRam: ")), sage_str(sage_index(s_telem, sage_string("ram_total_mb")))), sage_string("MB"));
    return sage_nil();
}

static SageValue s_rpi2_send_heartbeat(int argc, SageValue* argv) {
    SageValue s_host = s_ORANGEPI_HOST;
    SageValue s_host_override = sage_nil() /* unsupported call: sage_get_property(s_sys, "getenv") */;
    if (sage_truthy(sage_neq(s_host_override, sage_nil()))) {
        (s_host = s_host_override);
    }
    sage_nil();
    SageValue s_port = s_ORANGEPI_PORT;
    SageValue s_port_str = sage_nil() /* unsupported call: sage_get_property(s_sys, "getenv") */;
    if (sage_truthy(sage_neq(s_port_str, sage_nil()))) {
        (s_port = sage_tonumber(s_port_str));
    }
    sage_nil();
    SageValue s_fd = sage_nil() /* unsupported call: sage_get_property(s_tcp, "connect") */;
    if (sage_truthy(sage_eq(s_fd, sage_number(sage_number(0).as.number - sage_number(1).as.number)))) {
        sage_print_value(sage_add(sage_add(sage_add(sage_string("[ERROR] Cannot connect to OrangePi at "), s_host), sage_string(":")), sage_str(s_port))); printf("\n");
        return sage_nil();
    }
    sage_nil();
    SageValue s_info = ({ SageValue _args[1]; s_get_rpi2_info(0, _args); });
    SageValue s_msg = sage_dict(4, "client_id", s_CLIENT_ID, "platform", sage_string("RPi2"), "info", s_info, "timestamp", ({ SageValue _args[1]; s_clock(0, _args); }));
    SageValue s_pihole = ({ SageValue _args[1]; s_get_pihole_info(0, _args); });
    if (sage_truthy(sage_neq(s_pihole, sage_nil()))) {
        sage_index_set(s_msg, sage_string("services"), s_pihole);
    }
    sage_nil();
    sage_nil() /* unsupported call: sage_get_property(s_tcp, "sendall") */;
    SageValue s_raw = sage_nil() /* unsupported call: sage_get_property(s_tcp, "recv") */;
    if (sage_truthy(sage_neq(s_raw, sage_nil()))) {
        SageValue s_resp = ({ SageValue _args[1]; _args[0] = s_raw; s_json_decode(1, _args); });
        if (sage_truthy(sage_neq(s_resp, sage_nil()))) {
            sage_print_value(sage_add(sage_add(sage_add(sage_string("[HEARTBEAT OK] nodes="), sage_str(sage_index(s_resp, sage_string("node_count")))), sage_string(" ts=")), sage_str(sage_index(s_resp, sage_string("server_ts"))))); printf("\n");
        } else {
            sage_print_value(sage_add(sage_string("[WARN] Bad response: "), s_raw)); printf("\n");
        }
        sage_nil();
    } else {
        sage_print_value(sage_string("[WARN] No response from OrangePi")); printf("\n");
    }
    sage_nil();
    sage_nil() /* unsupported call: sage_get_property(s_tcp, "close") */;
    return sage_nil();
}

static SageValue s_run_rpi2(int argc, SageValue* argv) {
    SageValue s_mode_idx = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_argv = sage_nil() /* unsupported call: sage_get_property(s_sys, "args") */;
    if (sage_truthy(sage_bool(sage_len(s_argv).as.number >= sage_add(s_mode_idx, sage_number(2)).as.number))) {
        (s_ORANGEPI_HOST = sage_index(s_argv, sage_add(s_mode_idx, sage_number(1))));
    }
    sage_nil();
    if (sage_truthy(sage_bool(sage_len(s_argv).as.number >= sage_add(s_mode_idx, sage_number(3)).as.number))) {
        (s_ORANGEPI_PORT = sage_tonumber(sage_index(s_argv, sage_add(s_mode_idx, sage_number(2)))));
    }
    sage_nil();
    sage_print_value(sage_string("=== RPi2 Client Starting (Real TCP) ===")); printf("\n");
    sage_print_value(sage_add(sage_strcat(sage_strcat(sage_string("Target: "), s_ORANGEPI_HOST), sage_string(":")), sage_str(s_ORANGEPI_PORT))); printf("\n");
    sage_print_value(sage_add(sage_add(sage_string("Heartbeat interval: "), sage_str(s_HEARTBEAT_INTERVAL)), sage_string("s"))); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    while (sage_truthy(sage_bool(1))) {
        ({ SageValue _args[1]; s_rpi2_send_heartbeat(0, _args); });
        sage_nil() /* unsupported call: sage_get_property(s_thread, "sleep") */;
    }
    sage_nil();
    return sage_nil();
}

static SageValue s_rpi4_read_sys_file(int argc, SageValue* argv) {
    SageValue s_path = (argc > 0) ? argv[0] : sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(sage_nil() /* unsupported call: sage_get_property(s_io, "exists") */)))) {
        return sage_nil();
    }
    return sage_nil() /* unsupported call: sage_get_property(s_io, "readfile") */;
    return sage_nil();
}

static SageValue s_rpi4_stripnl(int argc, SageValue* argv) {
    SageValue s_s = (argc > 0) ? argv[0] : sage_nil();
    return ({ SageValue _args[3]; _args[0] = ({ SageValue _args[3]; _args[0] = s_s; _args[1] = ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); }); _args[2] = sage_string(""); s_replace(3, _args); }); _args[1] = ({ SageValue _args[1]; _args[0] = sage_number(13); s_chr(1, _args); }); _args[2] = sage_string(""); s_replace(3, _args); });
    return sage_nil();
}

static SageValue s_rpi4_get_cpu_temp(int argc, SageValue* argv) {
    SageValue s_raw = ({ SageValue _args[1]; _args[0] = sage_string("/sys/class/thermal/thermal_zone0/temp"); s_rpi4_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_raw, sage_nil()))) {
        SageValue s_cleaned = ({ SageValue _args[1]; _args[0] = s_raw; s_rpi4_stripnl(1, _args); });
        SageValue s_millideg = sage_tonumber(s_cleaned);
        if (sage_truthy(sage_neq(s_millideg, sage_nil()))) {
            return sage_div(s_millideg, sage_number(1000));
        }
        sage_nil();
    }
    sage_nil();
    return sage_add(sage_number(45), sage_mod(({ SageValue _args[1]; s_clock(0, _args); }), sage_number(5)));
    return sage_nil();
}

static SageValue s_rpi4_get_cpu_load(int argc, SageValue* argv) {
    SageValue s_raw = ({ SageValue _args[1]; _args[0] = sage_string("/proc/loadavg"); s_rpi4_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_raw, sage_nil()))) {
        SageValue s_parts = sage_array(0);
        SageValue s_cur = sage_string("");
        { SageValue _iter_t11 = sage_range((int)sage_len(s_raw).as.number);
            for (int t11 = 0; t11 < sage_array_len(_iter_t11); t11++) {
                SageValue s_i = sage_array_get(_iter_t11, t11);
                if (sage_truthy(sage_eq(sage_index(s_raw, s_i), sage_string(" ")))) {
                    (sage_push(s_parts, s_cur), sage_nil());
                    (s_cur = sage_string(""));
                } else {
                    (s_cur = sage_add(s_cur, sage_index(s_raw, s_i)));
                }
            }
        }
        if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
            (sage_push(s_parts, s_cur), sage_nil());
        }
        if (sage_truthy(sage_bool(sage_len(s_parts).as.number >= sage_number(1).as.number))) {
            SageValue s_load = sage_tonumber(sage_index(s_parts, sage_number(0)));
            if (sage_truthy(sage_neq(s_load, sage_nil()))) {
                return s_load;
            }
            sage_nil();
        }
        sage_nil();
    }
    sage_nil();
    return sage_add(sage_number(0.40000000000000002), sage_div(sage_mod(({ SageValue _args[1]; s_clock(0, _args); }), sage_number(10)), sage_number(100)));
    return sage_nil();
}

static SageValue s_rpi4_get_memory_info(int argc, SageValue* argv) {
    SageValue s_raw = ({ SageValue _args[1]; _args[0] = sage_string("/proc/meminfo"); s_rpi4_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_raw, sage_nil()))) {
        SageValue s_lines = sage_array(0);
        SageValue s_cur = sage_string("");
        { SageValue _iter_t12 = sage_range((int)sage_len(s_raw).as.number);
            for (int t12 = 0; t12 < sage_array_len(_iter_t12); t12++) {
                SageValue s_i = sage_array_get(_iter_t12, t12);
                if (sage_truthy(sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); })))) {
                    (sage_push(s_lines, s_cur), sage_nil());
                    (s_cur = sage_string(""));
                } else {
                    (s_cur = sage_add(s_cur, sage_index(s_raw, s_i)));
                }
            }
        }
        if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
            (sage_push(s_lines, s_cur), sage_nil());
        }
        if (sage_truthy(sage_bool(sage_len(s_lines).as.number >= sage_number(2).as.number))) {
            SageValue s_mem_avail = sage_index(s_lines, sage_number(1));
            SageValue s_parts = sage_array(0);
            (s_cur = sage_string(""));
            { SageValue _iter_t13 = sage_range((int)sage_len(s_mem_avail).as.number);
                for (int t13 = 0; t13 < sage_array_len(_iter_t13); t13++) {
                    SageValue s_i = sage_array_get(_iter_t13, t13);
                    if (sage_truthy(sage_eq(sage_index(s_mem_avail, s_i), sage_string(" ")))) {
                        if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
                            (sage_push(s_parts, s_cur), sage_nil());
                        }
                        (s_cur = sage_string(""));
                    } else {
                        (s_cur = sage_add(s_cur, sage_index(s_mem_avail, s_i)));
                    }
                }
            }
            if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
                (sage_push(s_parts, s_cur), sage_nil());
            }
            if (sage_truthy(sage_bool(sage_len(s_parts).as.number >= sage_number(2).as.number))) {
                return sage_add(sage_add(sage_string("Available: "), sage_index(s_parts, sage_number(1))), sage_string("kB"));
            }
            sage_nil();
        }
        sage_nil();
    }
    sage_nil();
    return sage_string("Available: 768MB");
    return sage_nil();
}

static SageValue s_get_gpu_temp(int argc, SageValue* argv) {
    SageValue s_raw = ({ SageValue _args[1]; _args[0] = sage_string("/sys/class/thermal/thermal_zone1/temp"); s_rpi4_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_raw, sage_nil()))) {
        SageValue s_cleaned = ({ SageValue _args[1]; _args[0] = s_raw; s_rpi4_stripnl(1, _args); });
        SageValue s_millideg = sage_tonumber(s_cleaned);
        if (sage_truthy(sage_neq(s_millideg, sage_nil()))) {
            return sage_add(sage_add(sage_string("GPU: "), sage_str(sage_div(s_millideg, sage_number(1000)))), sage_string("C"));
        }
        sage_nil();
    }
    sage_nil();
    return sage_string("GPU: N/A");
    return sage_nil();
}

static SageValue s_get_throttling(int argc, SageValue* argv) {
    SageValue s_raw = ({ SageValue _args[1]; _args[0] = sage_string("/sys/devices/platform/soc/soc:firmware/get_throttled"); s_rpi4_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_raw, sage_nil()))) {
        SageValue s_cleaned = ({ SageValue _args[1]; _args[0] = s_raw; s_rpi4_stripnl(1, _args); });
        SageValue s_val = sage_tonumber(s_cleaned);
        if (sage_truthy((sage_truthy(sage_neq(s_val, sage_nil())) ? sage_gt(s_val, sage_number(0)) : sage_neq(s_val, sage_nil())))) {
            return sage_string("THROTTLED");
        }
        sage_nil();
    }
    sage_nil();
    return sage_string("OK");
    return sage_nil();
}

static SageValue s_get_services_info(int argc, SageValue* argv) {
    SageValue s_raw = sage_nil() /* unsupported call: sage_get_property(s_io, "readfile") */;
    if (sage_truthy(sage_eq(s_raw, sage_nil()))) {
        return sage_nil();
    }
    return ({ SageValue _args[1]; _args[0] = s_raw; s_json_decode(1, _args); });
    return sage_nil();
}

static SageValue s_get_compile_info(int argc, SageValue* argv) {
    SageValue s_raw = sage_nil() /* unsupported call: sage_get_property(s_io, "readfile") */;
    if (sage_truthy(sage_eq(s_raw, sage_nil()))) {
        return sage_nil();
    }
    return ({ SageValue _args[1]; _args[0] = s_raw; s_json_decode(1, _args); });
    return sage_nil();
}

static SageValue s_rpi4_parse_mem_line(int argc, SageValue* argv) {
    SageValue s_line = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_parts = sage_array(0);
    SageValue s_cur = sage_string("");
    { SageValue _iter_t14 = sage_range((int)sage_len(s_line).as.number);
        for (int t14 = 0; t14 < sage_array_len(_iter_t14); t14++) {
            SageValue s_i = sage_array_get(_iter_t14, t14);
            SageValue s_c = sage_index(s_line, s_i);
            if (sage_truthy((sage_truthy((sage_truthy(sage_eq(s_c, sage_string(" "))) ? sage_eq(s_c, sage_string(" ")) : sage_eq(s_c, sage_string(":")))) ? (sage_truthy(sage_eq(s_c, sage_string(" "))) ? sage_eq(s_c, sage_string(" ")) : sage_eq(s_c, sage_string(":"))) : sage_eq(s_c, ({ SageValue _args[1]; _args[0] = sage_number(9); s_chr(1, _args); }))))) {
                if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
                    (sage_push(s_parts, s_cur), sage_nil());
                }
                sage_nil();
                (s_cur = sage_string(""));
            } else {
                (s_cur = sage_add(s_cur, s_c));
            }
            sage_nil();
        }
    }
    sage_nil();
    if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
        (sage_push(s_parts, s_cur), sage_nil());
    }
    sage_nil();
    if (sage_truthy(sage_bool(sage_len(s_parts).as.number >= sage_number(2).as.number))) {
        return sage_tonumber(sage_index(s_parts, sage_number(1)));
    }
    sage_nil();
    return sage_nil();
    return sage_nil();
}

static SageValue s_rpi4_get_dynamic_telemetry(int argc, SageValue* argv) {
    SageValue s_telem = sage_dict(0);
    SageValue s_temp_raw = ({ SageValue _args[1]; _args[0] = sage_string("/sys/class/thermal/thermal_zone0/temp"); s_rpi4_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_temp_raw, sage_nil()))) {
        SageValue s_temp_num = sage_tonumber(({ SageValue _args[1]; _args[0] = s_temp_raw; s_rpi4_stripnl(1, _args); }));
        if (sage_truthy(sage_neq(s_temp_num, sage_nil()))) {
            sage_index_set(s_telem, sage_string("cpu_temp"), sage_div(s_temp_num, sage_number(1000)));
        }
        sage_nil();
    }
    sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_telem; _args[1] = sage_string("cpu_temp"); s_dict_has(2, _args); }))))) {
        sage_index_set(s_telem, sage_string("cpu_temp"), sage_number(42));
    }
    sage_nil();
    SageValue s_load_raw = ({ SageValue _args[1]; _args[0] = sage_string("/proc/loadavg"); s_rpi4_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_load_raw, sage_nil()))) {
        SageValue s_parts = sage_array(0);
        SageValue s_cur = sage_string("");
        { SageValue _iter_t15 = sage_range((int)sage_len(s_load_raw).as.number);
            for (int t15 = 0; t15 < sage_array_len(_iter_t15); t15++) {
                SageValue s_i = sage_array_get(_iter_t15, t15);
                if (sage_truthy(sage_eq(sage_index(s_load_raw, s_i), sage_string(" ")))) {
                    if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
                        (sage_push(s_parts, s_cur), sage_nil());
                    }
                    sage_nil();
                    (s_cur = sage_string(""));
                } else {
                    (s_cur = sage_add(s_cur, sage_index(s_load_raw, s_i)));
                }
                sage_nil();
            }
        }
        sage_nil();
        if (sage_truthy(sage_bool(sage_len(s_parts).as.number >= sage_number(1).as.number))) {
            SageValue s_load_val = sage_tonumber(sage_index(s_parts, sage_number(0)));
            if (sage_truthy(sage_neq(s_load_val, sage_nil()))) {
                sage_index_set(s_telem, sage_string("cpu_load"), s_load_val);
            }
            sage_nil();
        }
        sage_nil();
    }
    sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_telem; _args[1] = sage_string("cpu_load"); s_dict_has(2, _args); }))))) {
        sage_index_set(s_telem, sage_string("cpu_load"), sage_number(0.25));
    }
    sage_nil();
    SageValue s_freq_raw = ({ SageValue _args[1]; _args[0] = sage_string("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"); s_rpi4_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_freq_raw, sage_nil()))) {
        SageValue s_freq_num = sage_tonumber(({ SageValue _args[1]; _args[0] = s_freq_raw; s_rpi4_stripnl(1, _args); }));
        if (sage_truthy(sage_neq(s_freq_num, sage_nil()))) {
            sage_index_set(s_telem, sage_string("cpu_mhz"), sage_div(s_freq_num, sage_number(1000)));
        }
        sage_nil();
    }
    sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_telem; _args[1] = sage_string("cpu_mhz"); s_dict_has(2, _args); }))))) {
        sage_index_set(s_telem, sage_string("cpu_mhz"), sage_number(1500));
    }
    sage_nil();
    SageValue s_mem_raw = ({ SageValue _args[1]; _args[0] = sage_string("/proc/meminfo"); s_rpi4_read_sys_file(1, _args); });
    if (sage_truthy(sage_neq(s_mem_raw, sage_nil()))) {
        SageValue s_lines = sage_array(0);
        SageValue s_cur = sage_string("");
        { SageValue _iter_t16 = sage_range((int)sage_len(s_mem_raw).as.number);
            for (int t16 = 0; t16 < sage_array_len(_iter_t16); t16++) {
                SageValue s_i = sage_array_get(_iter_t16, t16);
                SageValue s_c = sage_index(s_mem_raw, s_i);
                if (sage_truthy(sage_eq(s_c, ({ SageValue _args[1]; _args[0] = sage_number(10); s_chr(1, _args); })))) {
                    (sage_push(s_lines, s_cur), sage_nil());
                    (s_cur = sage_string(""));
                } else {
                    (s_cur = sage_add(s_cur, s_c));
                }
                sage_nil();
            }
        }
        sage_nil();
        if (sage_truthy(sage_gt(sage_len(s_cur), sage_number(0)))) {
            (sage_push(s_lines, s_cur), sage_nil());
        }
        sage_nil();
        SageValue s_total_kb = sage_nil();
        SageValue s_avail_kb = sage_nil();
        { SageValue _iter_t17 = sage_range((int)sage_len(s_lines).as.number);
            for (int t17 = 0; t17 < sage_array_len(_iter_t17); t17++) {
                SageValue s_i = sage_array_get(_iter_t17, t17);
                SageValue s_line = sage_index(s_lines, s_i);
                if (sage_truthy((sage_truthy(sage_bool(sage_len(s_line).as.number >= sage_number(8).as.number)) ? sage_eq(({ SageValue _args[3]; _args[0] = s_line; _args[1] = sage_number(0); _args[2] = sage_number(8); s_substring(3, _args); }), sage_string("MemTotal")) : sage_bool(sage_len(s_line).as.number >= sage_number(8).as.number)))) {
                    (s_total_kb = ({ SageValue _args[1]; _args[0] = s_line; s_rpi4_parse_mem_line(1, _args); }));
                } else {
                    if (sage_truthy((sage_truthy(sage_bool(sage_len(s_line).as.number >= sage_number(12).as.number)) ? sage_eq(({ SageValue _args[3]; _args[0] = s_line; _args[1] = sage_number(0); _args[2] = sage_number(12); s_substring(3, _args); }), sage_string("MemAvailable")) : sage_bool(sage_len(s_line).as.number >= sage_number(12).as.number)))) {
                        (s_avail_kb = ({ SageValue _args[1]; _args[0] = s_line; s_rpi4_parse_mem_line(1, _args); }));
                    }
                }
                sage_nil();
            }
        }
        sage_nil();
        if (sage_truthy(sage_neq(s_total_kb, sage_nil()))) {
            sage_index_set(s_telem, sage_string("ram_total_mb"), sage_div(s_total_kb, sage_number(1024)));
        }
        sage_nil();
        if (sage_truthy(sage_neq(s_avail_kb, sage_nil()))) {
            sage_index_set(s_telem, sage_string("ram_avail_mb"), sage_div(s_avail_kb, sage_number(1024)));
        }
        sage_nil();
    }
    sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_telem; _args[1] = sage_string("ram_total_mb"); s_dict_has(2, _args); }))))) {
        sage_index_set(s_telem, sage_string("ram_total_mb"), sage_number(2048));
    }
    sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_telem; _args[1] = sage_string("ram_avail_mb"); s_dict_has(2, _args); }))))) {
        sage_index_set(s_telem, sage_string("ram_avail_mb"), sage_number(1536));
    }
    sage_nil();
    return s_telem;
    return sage_nil();
}

static SageValue s_get_rpi4_info(int argc, SageValue* argv) {
    SageValue s_telem = ({ SageValue _args[1]; s_rpi4_get_dynamic_telemetry(0, _args); });
    SageValue s_gpu = ({ SageValue _args[1]; s_get_gpu_temp(0, _args); });
    SageValue s_throttle = ({ SageValue _args[1]; s_get_throttling(0, _args); });
    return sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("Temp: "), sage_str(sage_index(s_telem, sage_string("cpu_temp")))), sage_string("C, Load: ")), sage_str(sage_index(s_telem, sage_string("cpu_load")))), sage_string(", Available: ")), sage_str(sage_index(s_telem, sage_string("ram_avail_mb")))), sage_string("MB, ")), s_gpu), sage_string(", ")), s_throttle), sage_string(", CpuFreq: ")), sage_str(sage_index(s_telem, sage_string("cpu_mhz")))), sage_string("MHz, TotalRam: ")), sage_str(sage_index(s_telem, sage_string("ram_total_mb")))), sage_string("MB"));
    return sage_nil();
}

static SageValue s_rpi4_send_heartbeat(int argc, SageValue* argv) {
    SageValue s_host = s_ORANGEPI_HOST;
    SageValue s_host_override = sage_nil() /* unsupported call: sage_get_property(s_sys, "getenv") */;
    if (sage_truthy(sage_neq(s_host_override, sage_nil()))) {
        (s_host = s_host_override);
    }
    sage_nil();
    SageValue s_port = s_ORANGEPI_PORT;
    SageValue s_port_str = sage_nil() /* unsupported call: sage_get_property(s_sys, "getenv") */;
    if (sage_truthy(sage_neq(s_port_str, sage_nil()))) {
        (s_port = sage_tonumber(s_port_str));
    }
    sage_nil();
    SageValue s_fd = sage_nil() /* unsupported call: sage_get_property(s_tcp, "connect") */;
    if (sage_truthy(sage_eq(s_fd, sage_number(sage_number(0).as.number - sage_number(1).as.number)))) {
        sage_print_value(sage_add(sage_add(sage_add(sage_string("[ERROR] Cannot connect to OrangePi at "), s_host), sage_string(":")), sage_str(s_port))); printf("\n");
        return sage_nil();
    }
    sage_nil();
    SageValue s_info = ({ SageValue _args[1]; s_get_rpi4_info(0, _args); });
    SageValue s_msg = sage_dict(4, "client_id", s_CLIENT_ID, "platform", sage_string("RPi4"), "info", s_info, "timestamp", ({ SageValue _args[1]; s_clock(0, _args); }));
    SageValue s_services = ({ SageValue _args[1]; s_get_services_info(0, _args); });
    if (sage_truthy(sage_neq(s_services, sage_nil()))) {
        sage_index_set(s_msg, sage_string("services"), s_services);
    }
    sage_nil();
    SageValue s_compile = ({ SageValue _args[1]; s_get_compile_info(0, _args); });
    if (sage_truthy(sage_neq(s_compile, sage_nil()))) {
        sage_index_set(s_msg, sage_string("compile"), s_compile);
    }
    sage_nil();
    sage_nil() /* unsupported call: sage_get_property(s_tcp, "sendall") */;
    SageValue s_raw = sage_nil() /* unsupported call: sage_get_property(s_tcp, "recv") */;
    if (sage_truthy(sage_neq(s_raw, sage_nil()))) {
        SageValue s_resp = ({ SageValue _args[1]; _args[0] = s_raw; s_json_decode(1, _args); });
        if (sage_truthy(sage_neq(s_resp, sage_nil()))) {
            sage_print_value(sage_add(sage_add(sage_add(sage_string("[HEARTBEAT OK] nodes="), sage_str(sage_index(s_resp, sage_string("node_count")))), sage_string(" ts=")), sage_str(sage_index(s_resp, sage_string("server_ts"))))); printf("\n");
        } else {
            sage_print_value(sage_add(sage_string("[WARN] Bad response: "), s_raw)); printf("\n");
        }
        sage_nil();
    } else {
        sage_print_value(sage_string("[WARN] No response from OrangePi")); printf("\n");
    }
    sage_nil();
    sage_nil() /* unsupported call: sage_get_property(s_tcp, "close") */;
    return sage_nil();
}

static SageValue s_run_rpi4(int argc, SageValue* argv) {
    SageValue s_mode_idx = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_argv = sage_nil() /* unsupported call: sage_get_property(s_sys, "args") */;
    if (sage_truthy(sage_bool(sage_len(s_argv).as.number >= sage_add(s_mode_idx, sage_number(2)).as.number))) {
        (s_ORANGEPI_HOST = sage_index(s_argv, sage_add(s_mode_idx, sage_number(1))));
    }
    sage_nil();
    if (sage_truthy(sage_bool(sage_len(s_argv).as.number >= sage_add(s_mode_idx, sage_number(3)).as.number))) {
        (s_ORANGEPI_PORT = sage_tonumber(sage_index(s_argv, sage_add(s_mode_idx, sage_number(2)))));
    }
    sage_nil();
    sage_print_value(sage_string("=== RPi4 Client Starting (Real TCP) ===")); printf("\n");
    sage_print_value(sage_add(sage_strcat(sage_strcat(sage_string("Target: "), s_ORANGEPI_HOST), sage_string(":")), sage_str(s_ORANGEPI_PORT))); printf("\n");
    sage_print_value(sage_add(sage_add(sage_string("Heartbeat interval: "), sage_str(s_HEARTBEAT_INTERVAL)), sage_string("s"))); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    while (sage_truthy(sage_bool(1))) {
        ({ SageValue _args[1]; s_rpi4_send_heartbeat(0, _args); });
        sage_nil() /* unsupported call: sage_get_property(s_thread, "sleep") */;
    }
    sage_nil();
    return sage_nil();
}

static SageValue s_rtos_init(int argc, SageValue* argv) {
    (s_rtos_tasks = sage_array(0));
    (s_rtos_task_count = sage_number(0));
    (s_rtos_current = sage_number(0));
    (s_rtos_tick = sage_number(0));
    (s_rtos_gc_ticks = sage_number(0));
    (s_rtos_running = sage_bool(1));
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_string("[RTOS] Scheduler initialized ("), sage_str(s_RTOS_MAX_TASKS)), sage_string(" slots, ")), sage_str(s_RTOS_MAX_PRIORITY)), sage_string(" priorities)"))); printf("\n");
    return sage_nil();
}

static SageValue s_rtos_task_create(int argc, SageValue* argv) {
    SageValue s_name = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_priority = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_period_ticks = (argc > 2) ? argv[2] : sage_nil();
    if (sage_truthy(sage_bool(s_rtos_task_count.as.number >= s_RTOS_MAX_TASKS.as.number))) {
        sage_print_value(sage_add(sage_add(sage_string("[RTOS] Cannot create task '"), s_name), sage_string("': task limit reached"))); printf("\n");
        return sage_number(sage_number(0).as.number - sage_number(1).as.number);
    }
    if (sage_truthy(sage_bool(s_priority.as.number >= s_RTOS_MAX_PRIORITY.as.number))) {
        (s_priority = sage_number(s_RTOS_MAX_PRIORITY.as.number - sage_number(1).as.number));
    }
    SageValue s_tcb = sage_dict(8, "name", s_name, "priority", s_priority, "period", s_period_ticks, "state", s_TASK_READY, "last_run", sage_number(0), "run_count", sage_number(0), "sleep_until", sage_number(0), "id", s_rtos_task_count);
    (sage_push(s_rtos_tasks, s_tcb), sage_nil());
    (s_rtos_task_count = sage_number(s_rtos_task_count.as.number + sage_number(1).as.number));
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("[RTOS] Task created: '"), s_name), sage_string("'  prio=")), sage_str(s_priority)), sage_string("  period=")), sage_str(s_period_ticks)), sage_string(" ticks  id=")), sage_str(sage_index(s_tcb, sage_string("id"))))); printf("\n");
    return sage_index(s_tcb, sage_string("id"));
    return sage_nil();
}

static SageValue s_rtos_sleep_task(int argc, SageValue* argv) {
    SageValue s_task_id = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_ticks = (argc > 1) ? argv[1] : sage_nil();
    if (sage_truthy((sage_truthy(sage_bool(s_task_id.as.number >= sage_number(0).as.number)) ? sage_lt(s_task_id, s_rtos_task_count) : sage_bool(s_task_id.as.number >= sage_number(0).as.number)))) {
        sage_index_set(sage_index(s_rtos_tasks, s_task_id), sage_string("state"), s_TASK_SLEEPING);
        sage_index_set(sage_index(s_rtos_tasks, s_task_id), sage_string("sleep_until"), sage_add(s_rtos_tick, s_ticks));
    }
    return sage_nil();
}

static SageValue s_rtos_suspend_task(int argc, SageValue* argv) {
    SageValue s_task_id = (argc > 0) ? argv[0] : sage_nil();
    if (sage_truthy((sage_truthy(sage_bool(s_task_id.as.number >= sage_number(0).as.number)) ? sage_lt(s_task_id, s_rtos_task_count) : sage_bool(s_task_id.as.number >= sage_number(0).as.number)))) {
        sage_index_set(sage_index(s_rtos_tasks, s_task_id), sage_string("state"), s_TASK_SUSPENDED);
    }
    return sage_nil();
}

static SageValue s_rtos_resume_task(int argc, SageValue* argv) {
    SageValue s_task_id = (argc > 0) ? argv[0] : sage_nil();
    if (sage_truthy((sage_truthy(sage_bool(s_task_id.as.number >= sage_number(0).as.number)) ? sage_lt(s_task_id, s_rtos_task_count) : sage_bool(s_task_id.as.number >= sage_number(0).as.number)))) {
        if (sage_truthy(sage_eq(sage_index(sage_index(s_rtos_tasks, s_task_id), sage_string("state")), s_TASK_SUSPENDED))) {
            sage_index_set(sage_index(s_rtos_tasks, s_task_id), sage_string("state"), s_TASK_READY);
        }
    }
    return sage_nil();
}

static SageValue s_rtos_halt(int argc, SageValue* argv) {
    (s_rtos_running = sage_bool(0));
    sage_print_value(sage_add(sage_string("[RTOS] Scheduler halted at tick "), sage_str(s_rtos_tick))); printf("\n");
    return sage_nil();
}

static SageValue s_rtos_print_tasks(int argc, SageValue* argv) {
    SageValue s_state_names = sage_array(5, sage_string("READY"), sage_string("RUNNING"), sage_string("SLEEPING"), sage_string("BLOCKED"), sage_string("SUSPENDED"));
    sage_print_value(sage_add(sage_add(sage_string("[RTOS] Task list (tick="), sage_str(s_rtos_tick)), sage_string("):"))); printf("\n");
    { SageValue _iter_t18 = sage_range((int)s_rtos_task_count.as.number);
        for (int t18 = 0; t18 < sage_array_len(_iter_t18); t18++) {
            SageValue s_i = sage_array_get(_iter_t18, t18);
            SageValue s_t = sage_index(s_rtos_tasks, s_i);
            SageValue s_sn = sage_index(s_state_names, sage_index(s_t, sage_string("state")));
            sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  ["), sage_str(sage_index(s_t, sage_string("id")))), sage_string("] ")), sage_index(s_t, sage_string("name"))), sage_string("  state=")), s_sn), sage_string("  prio=")), sage_str(sage_index(s_t, sage_string("priority")))), sage_string("  runs=")), sage_str(sage_index(s_t, sage_string("run_count")))), sage_string("  period=")), sage_str(sage_index(s_t, sage_string("period"))))); printf("\n");
        }
    }
    return sage_nil();
}

static SageValue s__simple_hash(int argc, SageValue* argv) {
    SageValue s_value = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_seed = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_h = s_seed;
    { SageValue _iter_t19 = sage_range((int)sage_len(sage_str(s_value)).as.number);
        for (int t19 = 0; t19 < sage_array_len(_iter_t19); t19++) {
            SageValue s_i = sage_array_get(_iter_t19, t19);
            (s_h = sage_mod(sage_add(sage_mul(s_h, sage_number(33)), ({ SageValue _args[1]; _args[0] = sage_index(sage_str(s_value), s_i); s_ord(1, _args); })), sage_number(1000000007)));
        }
    }
    return s_h;
    return sage_nil();
}

static SageValue s__generate_otp_key(int argc, SageValue* argv) {
    SageValue s_passphrase = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_length = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_seed = (argc > 2) ? argv[2] : sage_nil();
    SageValue s_key = sage_array(0);
    { SageValue _iter_t20 = sage_range((int)s_length.as.number);
        for (int t20 = 0; t20 < sage_array_len(_iter_t20); t20++) {
            SageValue s_i = sage_array_get(_iter_t20, t20);
            SageValue s_h = ({ SageValue _args[2]; _args[0] = sage_add(s_passphrase, sage_str(s_i)); _args[1] = s_seed; s__simple_hash(2, _args); });
            (sage_push(s_key, sage_sub(sage_mod(s_h, sage_number(127)), sage_number(63))), sage_nil());
        }
    }
    return s_key;
    return sage_nil();
}

static SageValue s__sign(int argc, SageValue* argv) {
    SageValue s_message = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_secret_key = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_node_id = (argc > 2) ? argv[2] : sage_nil();
    SageValue s_s1 = ({ SageValue _args[2]; _args[0] = sage_add(sage_add(s_message, s_secret_key), sage_str(s_node_id)); _args[1] = sage_number(12345); s__simple_hash(2, _args); });
    SageValue s_s2 = ({ SageValue _args[2]; _args[0] = sage_str(s_s1); _args[1] = sage_number(54321); s__simple_hash(2, _args); });
    return sage_array(2, s_s1, s_s2);
    return sage_nil();
}

static SageValue s__verify_sig(int argc, SageValue* argv) {
    SageValue s_message = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_sig = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_secret_key = (argc > 2) ? argv[2] : sage_nil();
    SageValue s_node_id = (argc > 3) ? argv[3] : sage_nil();
    SageValue s_expected = ({ SageValue _args[3]; _args[0] = s_message; _args[1] = s_secret_key; _args[2] = s_node_id; s__sign(3, _args); });
    return (sage_truthy(sage_eq(sage_index(s_sig, sage_number(0)), sage_index(s_expected, sage_number(0)))) ? sage_eq(sage_index(s_sig, sage_number(1)), sage_index(s_expected, sage_number(1))) : sage_eq(sage_index(s_sig, sage_number(0)), sage_index(s_expected, sage_number(0))));
    return sage_nil();
}

static SageValue s__otp_encrypt(int argc, SageValue* argv) {
    SageValue s_message = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_key = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_out = sage_string("");
    { SageValue _iter_t21 = sage_range((int)sage_len(sage_str(s_message)).as.number);
        for (int t21 = 0; t21 < sage_array_len(_iter_t21); t21++) {
            SageValue s_i = sage_array_get(_iter_t21, t21);
            SageValue s_mb = ({ SageValue _args[1]; _args[0] = sage_index(sage_str(s_message), s_i); s_ord(1, _args); });
            SageValue s_kb = sage_index(s_key, sage_mod(s_i, sage_len(s_key)));
            (s_out = sage_add(s_out, ({ SageValue _args[1]; _args[0] = sage_mod(sage_add(s_mb, s_kb), sage_number(256)); s_chr(1, _args); })));
        }
    }
    return s_out;
    return sage_nil();
}

static SageValue s__otp_decrypt(int argc, SageValue* argv) {
    SageValue s_encrypted = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_key = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_out = sage_string("");
    { SageValue _iter_t22 = sage_range((int)sage_len(sage_str(s_encrypted)).as.number);
        for (int t22 = 0; t22 < sage_array_len(_iter_t22); t22++) {
            SageValue s_i = sage_array_get(_iter_t22, t22);
            SageValue s_eb = ({ SageValue _args[1]; _args[0] = sage_index(sage_str(s_encrypted), s_i); s_ord(1, _args); });
            SageValue s_kb = sage_index(s_key, sage_mod(s_i, sage_len(s_key)));
            (s_out = sage_add(s_out, ({ SageValue _args[1]; _args[0] = sage_mod(sage_add(sage_sub(s_eb, s_kb), sage_number(256)), sage_number(256)); s_chr(1, _args); })));
        }
    }
    return s_out;
    return sage_nil();
}

static SageValue s_crypto_seal(int argc, SageValue* argv) {
    SageValue s_message = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_secret_key = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_otp_pass = (argc > 2) ? argv[2] : sage_nil();
    SageValue s_otp_seed = (argc > 3) ? argv[3] : sage_nil();
    SageValue s_sender_id = (argc > 4) ? argv[4] : sage_nil();
    SageValue s_recipient_id = (argc > 5) ? argv[5] : sage_nil();
    SageValue s_key = ({ SageValue _args[3]; _args[0] = s_otp_pass; _args[1] = sage_len(sage_str(s_message)); _args[2] = s_otp_seed; s__generate_otp_key(3, _args); });
    SageValue s_encrypted = ({ SageValue _args[2]; _args[0] = s_message; _args[1] = s_key; s__otp_encrypt(2, _args); });
    SageValue s_sig = ({ SageValue _args[3]; _args[0] = s_encrypted; _args[1] = s_secret_key; _args[2] = s_sender_id; s__sign(3, _args); });
    return sage_dict(6, "payload", s_encrypted, "otp", s_key, "sig", s_sig, "key_len", sage_len(sage_str(s_message)), "from", s_sender_id, "to", s_recipient_id);
    return sage_nil();
}

static SageValue s_crypto_open(int argc, SageValue* argv) {
    SageValue s_envelope = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_secret_key = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_otp_pass = (argc > 2) ? argv[2] : sage_nil();
    SageValue s_otp_seed = (argc > 3) ? argv[3] : sage_nil();
    SageValue s_expected_sender = (argc > 4) ? argv[4] : sage_nil();
    if (sage_truthy((sage_truthy(sage_eq(sage_index(s_envelope, sage_string("sig")), sage_nil())) ? sage_eq(sage_index(s_envelope, sage_string("sig")), sage_nil()) : sage_lt(sage_len(sage_index(s_envelope, sage_string("sig"))), sage_number(2))))) {
        return sage_nil();
    }
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[4]; _args[0] = sage_index(s_envelope, sage_string("payload")); _args[1] = sage_index(s_envelope, sage_string("sig")); _args[2] = s_secret_key; _args[3] = s_expected_sender; s__verify_sig(4, _args); }))))) {
        return sage_nil();
    }
    SageValue s_key_len = sage_index(s_envelope, sage_string("key_len"));
    SageValue s_key = ({ SageValue _args[3]; _args[0] = s_otp_pass; _args[1] = s_key_len; _args[2] = s_otp_seed; s__generate_otp_key(3, _args); });
    return ({ SageValue _args[2]; _args[0] = sage_index(s_envelope, sage_string("payload")); _args[1] = s_key; s__otp_decrypt(2, _args); });
    return sage_nil();
}

static SageValue s_mb_create(int argc, SageValue* argv) {
    SageValue s_node_id = (argc > 0) ? argv[0] : sage_nil();
    return sage_dict(3, "id", s_node_id, "queue", sage_array(0), "stats", sage_dict(2, "sent", sage_number(0), "received", sage_number(0)));
    return sage_nil();
}

static SageValue s_mb_send(int argc, SageValue* argv) {
    SageValue s_mb = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_msg = (argc > 1) ? argv[1] : sage_nil();
    (sage_push(sage_index(s_mb, sage_string("queue")), s_msg), sage_nil());
    sage_index_set(sage_index(s_mb, sage_string("stats")), sage_string("sent"), sage_add(sage_index(sage_index(s_mb, sage_string("stats")), sage_string("sent")), sage_number(1)));
    return sage_nil();
}

static SageValue s_mb_recv(int argc, SageValue* argv) {
    SageValue s_mb = (argc > 0) ? argv[0] : sage_nil();
    if (sage_truthy(sage_eq(sage_len(sage_index(s_mb, sage_string("queue"))), sage_number(0)))) {
        return sage_nil();
    }
    SageValue s_msg = sage_index(sage_index(s_mb, sage_string("queue")), sage_number(0));
    SageValue s_new_q = sage_array(0);
    { SageValue _iter_t23 = sage_range((int)sage_sub(sage_len(sage_index(s_mb, sage_string("queue"))), sage_number(1)).as.number);
        for (int t23 = 0; t23 < sage_array_len(_iter_t23); t23++) {
            SageValue s_i = sage_array_get(_iter_t23, t23);
            (sage_push(s_new_q, sage_index(sage_index(s_mb, sage_string("queue")), sage_add(s_i, sage_number(1)))), sage_nil());
        }
    }
    sage_index_set(s_mb, sage_string("queue"), s_new_q);
    sage_index_set(sage_index(s_mb, sage_string("stats")), sage_string("received"), sage_add(sage_index(sage_index(s_mb, sage_string("stats")), sage_string("received")), sage_number(1)));
    return s_msg;
    return sage_nil();
}

static SageValue s_mb_pending(int argc, SageValue* argv) {
    SageValue s_mb = (argc > 0) ? argv[0] : sage_nil();
    return sage_len(sage_index(s_mb, sage_string("queue")));
    return sage_nil();
}

static SageValue s_router_register(int argc, SageValue* argv) {
    SageValue s_host = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_port = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_name = (argc > 2) ? argv[2] : sage_nil();
    SageValue s_id = sage_index(s_router_state, sage_string("next_id"));
    sage_index_set(s_router_state, sage_string("next_id"), sage_add(sage_index(s_router_state, sage_string("next_id")), sage_number(1)));
    SageValue s_client = sage_dict(7, "id", s_id, "host", s_host, "port", s_port, "name", s_name, "connected", sage_bool(1), "last_seen", s_rtos_tick, "msg_count", sage_number(0));
    sage_index_set(sage_index(s_router_state, sage_string("clients")), sage_str(s_id), s_client);
    sage_index_set(s_router_mailboxes, sage_str(s_id), ({ SageValue _args[1]; _args[0] = s_id; s_mb_create(1, _args); }));
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("[Router] Registered node-"), sage_str(s_id)), sage_string(" \"")), s_name), sage_string("\" @ ")), s_host), sage_string(":")), sage_str(s_port))); printf("\n");
    return s_id;
    return sage_nil();
}

static SageValue s_router_unregister(int argc, SageValue* argv) {
    SageValue s_node_id = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_key = sage_str(s_node_id);
    if (sage_truthy(({ SageValue _args[2]; _args[0] = sage_index(s_router_state, sage_string("clients")); _args[1] = s_key; s_dict_has(2, _args); }))) {
        SageValue s_c = sage_index(sage_index(s_router_state, sage_string("clients")), s_key);
        sage_index_set(s_c, sage_string("connected"), sage_bool(0));
        if (sage_truthy(({ SageValue _args[2]; _args[0] = s_router_mailboxes; _args[1] = s_key; s_dict_has(2, _args); }))) {
            ({ SageValue _args[2]; _args[0] = s_router_mailboxes; _args[1] = s_key; s_dict_delete(2, _args); });
        }
        ({ SageValue _args[2]; _args[0] = sage_index(s_router_state, sage_string("clients")); _args[1] = s_key; s_dict_delete(2, _args); });
        sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_string("[Router] Removed node-"), sage_str(s_node_id)), sage_string(" \"")), sage_index(s_c, sage_string("name"))), sage_string("\""))); printf("\n");
        return sage_bool(1);
    }
    return sage_bool(0);
    return sage_nil();
}

static SageValue s_router_route(int argc, SageValue* argv) {
    SageValue s_src_id = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_dst_id = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_payload = (argc > 2) ? argv[2] : sage_nil();
    SageValue s_sig = (argc > 3) ? argv[3] : sage_nil();
    SageValue s_key_len = (argc > 4) ? argv[4] : sage_nil();
    SageValue s_key = sage_str(s_dst_id);
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = sage_index(s_router_state, sage_string("clients")); _args[1] = s_key; s_dict_has(2, _args); }))))) {
        sage_print_value(sage_add(sage_add(sage_string("[Router] Route FAILED: node-"), sage_str(s_dst_id)), sage_string(" not registered"))); printf("\n");
        return sage_bool(0);
    }
    SageValue s_dst = sage_index(sage_index(s_router_state, sage_string("clients")), s_key);
    if (sage_truthy(sage_bool(!sage_truthy(sage_index(s_dst, sage_string("connected")))))) {
        sage_print_value(sage_add(sage_add(sage_string("[Router] Route FAILED: node-"), sage_str(s_dst_id)), sage_string(" offline"))); printf("\n");
        return sage_bool(0);
    }
    SageValue s_mb = sage_index(s_router_mailboxes, s_key);
    SageValue s_sig_val = s_sig;
    SageValue s_key_len_val = s_key_len;
    if (sage_truthy(sage_eq(s_sig_val, sage_nil()))) {
        (s_sig_val = sage_array(0));
    }
    if (sage_truthy(sage_eq(s_key_len_val, sage_nil()))) {
        (s_key_len_val = sage_len(sage_str(s_payload)));
    }
    ({ SageValue _args[2]; _args[0] = s_mb; _args[1] = sage_dict(6, "from", s_src_id, "to", s_dst_id, "payload", s_payload, "sig", s_sig_val, "key_len", s_key_len_val, "ts", s_rtos_tick); s_mb_send(2, _args); });
    sage_index_set(s_dst, sage_string("msg_count"), sage_add(sage_index(s_dst, sage_string("msg_count")), sage_number(1)));
    (sage_push(sage_index(s_router_state, sage_string("route_log")), sage_dict(4, "from", s_src_id, "to", s_dst_id, "payload_len", sage_len(sage_str(s_payload)), "tick", s_rtos_tick)), sage_nil());
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("[Router] Routed  node-"), sage_str(s_src_id)), sage_string(" -> node-")), sage_str(s_dst_id)), sage_string("  (")), sage_str(sage_len(sage_str(s_payload)))), sage_string(" bytes)"))); printf("\n");
    return sage_bool(1);
    return sage_nil();
}

static SageValue s_task_body_accept(int argc, SageValue* argv) {
    if (sage_truthy(sage_eq(sage_len(s_router_conn_queue), sage_number(0)))) {
        return sage_nil();
    }
    SageValue s_req = sage_index(s_router_conn_queue, sage_number(0));
    SageValue s_new_q = sage_array(0);
    { SageValue _iter_t24 = sage_range((int)sage_sub(sage_len(s_router_conn_queue), sage_number(1)).as.number);
        for (int t24 = 0; t24 < sage_array_len(_iter_t24); t24++) {
            SageValue s_i = sage_array_get(_iter_t24, t24);
            (sage_push(s_new_q, sage_index(s_router_conn_queue, sage_add(s_i, sage_number(1)))), sage_nil());
        }
    }
    (s_router_conn_queue = s_new_q);
    if (sage_truthy(sage_eq(sage_index(s_req, sage_string("op")), s_SMP_OP_JOIN))) {
        SageValue s_assigned_id = ({ SageValue _args[3]; _args[0] = sage_index(s_req, sage_string("host")); _args[1] = sage_index(s_req, sage_string("port")); _args[2] = sage_index(s_req, sage_string("name")); s_router_register(3, _args); });
        sage_print_value(sage_add(sage_add(sage_add(sage_string("[accept_task] JOIN from \""), sage_index(s_req, sage_string("name"))), sage_string("\" -> assigned node-")), sage_str(s_assigned_id))); printf("\n");
    } else {
        if (sage_truthy(sage_eq(sage_index(s_req, sage_string("op")), s_SMP_OP_LEAVE))) {
            ({ SageValue _args[1]; _args[0] = sage_index(s_req, sage_string("node_id")); s_router_unregister(1, _args); });
            sage_print_value(sage_add(sage_string("[accept_task] LEAVE from node-"), sage_str(sage_index(s_req, sage_string("node_id"))))); printf("\n");
        }
    }
    return sage_nil();
}

static SageValue s_task_body_message(int argc, SageValue* argv) {
    SageValue s_ids = sage_dict_keys(s_router_mailboxes);
    SageValue s_total = sage_number(0);
    { SageValue _iter_t25 = sage_range((int)sage_len(s_ids).as.number);
        for (int t25 = 0; t25 < sage_array_len(_iter_t25); t25++) {
            SageValue s_i = sage_array_get(_iter_t25, t25);
            SageValue s_mb = sage_index(s_router_mailboxes, sage_index(s_ids, s_i));
            SageValue s_pending = ({ SageValue _args[1]; _args[0] = s_mb; s_mb_pending(1, _args); });
            if (sage_truthy(sage_gt(s_pending, sage_number(0)))) {
                SageValue s_msg = ({ SageValue _args[1]; _args[0] = s_mb; s_mb_recv(1, _args); });
                while (sage_truthy(sage_neq(s_msg, sage_nil()))) {
                    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("[message_task] Delivering  node-"), sage_str(sage_index(s_msg, sage_string("from")))), sage_string(" -> node-")), sage_str(sage_index(s_msg, sage_string("to")))), sage_string("  payload=")), sage_str(sage_index(s_msg, sage_string("payload"))))); printf("\n");
                    (s_total = sage_add(s_total, sage_number(1)));
                    (s_msg = ({ SageValue _args[1]; _args[0] = s_mb; s_mb_recv(1, _args); }));
                }
            }
        }
    }
    if (sage_truthy(sage_gt(s_total, sage_number(0)))) {
        sage_print_value(sage_add(sage_add(sage_string("[message_task] Delivered "), sage_str(s_total)), sage_string(" message(s) this tick"))); printf("\n");
    }
    return sage_nil();
}

static SageValue s_task_body_heartbeat(int argc, SageValue* argv) {
    sage_index_set(s_router_state, sage_string("heartbeat_ticks"), sage_add(sage_index(s_router_state, sage_string("heartbeat_ticks")), sage_number(1)));
    SageValue s_timeout = sage_index(s_router_state, sage_string("client_timeout"));
    SageValue s_ids = sage_dict_keys(sage_index(s_router_state, sage_string("clients")));
    SageValue s_dropped = sage_number(0);
    { SageValue _iter_t26 = sage_range((int)sage_len(s_ids).as.number);
        for (int t26 = 0; t26 < sage_array_len(_iter_t26); t26++) {
            SageValue s_i = sage_array_get(_iter_t26, t26);
            SageValue s_c = sage_index(sage_index(s_router_state, sage_string("clients")), sage_index(s_ids, s_i));
            if (sage_truthy(sage_index(s_c, sage_string("connected")))) {
                SageValue s_idle = sage_sub(s_rtos_tick, sage_index(s_c, sage_string("last_seen")));
                if (sage_truthy(sage_gt(s_idle, s_timeout))) {
                    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_string("[heartbeat_task] node-"), sage_str(sage_index(s_c, sage_string("id")))), sage_string(" timed out (idle=")), sage_str(s_idle)), sage_string(" ticks) — removing"))); printf("\n");
                    ({ SageValue _args[1]; _args[0] = sage_index(s_c, sage_string("id")); s_router_unregister(1, _args); });
                    (s_dropped = sage_add(s_dropped, sage_number(1)));
                }
            }
        }
    }
    if (sage_truthy(sage_bool(s_rtos_gc_ticks.as.number >= s_RTOS_GC_INTERVAL.as.number))) {
        ({ SageValue _args[1]; s_gc_collect(0, _args); });
        (s_rtos_gc_ticks = sage_number(0));
        sage_print_value(sage_add(sage_string("[heartbeat_task] GC collected at tick "), sage_str(s_rtos_tick))); printf("\n");
    }
    SageValue s_client_count = sage_len(sage_dict_keys(sage_index(s_router_state, sage_string("clients"))));
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("[heartbeat_task] tick="), sage_str(s_rtos_tick)), sage_string("  clients=")), sage_str(s_client_count)), sage_string("  hb#")), sage_str(sage_index(s_router_state, sage_string("heartbeat_ticks"))))); printf("\n");
    return sage_nil();
}

static SageValue s_rtos_dispatch_task(int argc, SageValue* argv) {
    SageValue s_name = (argc > 0) ? argv[0] : sage_nil();
    if (sage_truthy(sage_eq(s_name, s_TASK_ACCEPT))) {
        ({ SageValue _args[1]; s_task_body_accept(0, _args); });
    } else {
        if (sage_truthy(sage_eq(s_name, s_TASK_MESSAGE))) {
            ({ SageValue _args[1]; s_task_body_message(0, _args); });
        } else {
            if (sage_truthy(sage_eq(s_name, s_TASK_HEARTBEAT))) {
                ({ SageValue _args[1]; s_task_body_heartbeat(0, _args); });
            }
        }
    }
    return sage_nil();
}

static SageValue s_rtos_tick_once(int argc, SageValue* argv) {
    (s_rtos_tick = sage_number(s_rtos_tick.as.number + sage_number(1).as.number));
    (s_rtos_gc_ticks = sage_number(s_rtos_gc_ticks.as.number + sage_number(1).as.number));
    { SageValue _iter_t27 = sage_range((int)s_rtos_task_count.as.number);
        for (int t27 = 0; t27 < sage_array_len(_iter_t27); t27++) {
            SageValue s_i = sage_array_get(_iter_t27, t27);
            SageValue s_t = sage_index(s_rtos_tasks, s_i);
            if (sage_truthy((sage_truthy(sage_eq(sage_index(s_t, sage_string("state")), s_TASK_SLEEPING)) ? sage_bool(s_rtos_tick.as.number >= sage_index(s_t, sage_string("sleep_until")).as.number) : sage_eq(sage_index(s_t, sage_string("state")), s_TASK_SLEEPING)))) {
                sage_index_set(s_t, sage_string("state"), s_TASK_READY);
            }
        }
    }
    SageValue s_prio = sage_number(s_RTOS_MAX_PRIORITY.as.number - sage_number(1).as.number);
    while (sage_truthy(sage_bool(s_prio.as.number >= sage_number(0).as.number))) {
        { SageValue _iter_t28 = sage_range((int)s_rtos_task_count.as.number);
            for (int t28 = 0; t28 < sage_array_len(_iter_t28); t28++) {
                SageValue s_i = sage_array_get(_iter_t28, t28);
                SageValue s_t = sage_index(s_rtos_tasks, s_i);
                if (sage_truthy((sage_truthy(sage_eq(sage_index(s_t, sage_string("state")), s_TASK_READY)) ? sage_eq(sage_index(s_t, sage_string("priority")), s_prio) : sage_eq(sage_index(s_t, sage_string("state")), s_TASK_READY)))) {
                    SageValue s_due = sage_bool(0);
                    if (sage_truthy(sage_eq(sage_index(s_t, sage_string("period")), sage_number(0)))) {
                        (s_due = sage_bool(1));
                    } else {
                        if (sage_truthy(sage_bool(sage_sub(s_rtos_tick, sage_index(s_t, sage_string("last_run"))).as.number >= sage_index(s_t, sage_string("period")).as.number))) {
                            (s_due = sage_bool(1));
                        }
                    }
                    if (sage_truthy(s_due)) {
                        sage_index_set(s_t, sage_string("state"), s_TASK_RUNNING);
                        sage_index_set(s_t, sage_string("last_run"), s_rtos_tick);
                        sage_index_set(s_t, sage_string("run_count"), sage_add(sage_index(s_t, sage_string("run_count")), sage_number(1)));
                        ({ SageValue _args[1]; _args[0] = sage_index(s_t, sage_string("name")); s_rtos_dispatch_task(1, _args); });
                        if (sage_truthy(sage_eq(sage_index(s_t, sage_string("state")), s_TASK_RUNNING))) {
                            sage_index_set(s_t, sage_string("state"), s_TASK_READY);
                        }
                    }
                }
            }
        }
        (s_prio = sage_sub(s_prio, sage_number(1)));
    }
    return sage_nil();
}

static SageValue s_cmd_connect(int argc, SageValue* argv) {
    SageValue s_host = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_port = (argc > 1) ? argv[1] : sage_nil();
    if (sage_truthy(sage_index(s_session, sage_string("connected")))) {
        sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_string("[SMP] Already connected to "), sage_index(s_session, sage_string("router_host"))), sage_string(":")), sage_str(sage_index(s_session, sage_string("router_port")))), sage_string("  (disconnect first)"))); printf("\n");
        return sage_bool(0);
    }
    SageValue s_assigned_id = sage_index(s_router_state, sage_string("next_id"));
    SageValue s_join_req = sage_dict(4, "op", s_SMP_OP_JOIN, "host", s_host, "port", s_port, "name", sage_index(s_session, sage_string("my_name")));
    (sage_push(s_router_conn_queue, s_join_req), sage_nil());
    sage_print_value(sage_add(sage_add(sage_add(sage_string("[SMP] JOIN queued for router at "), s_host), sage_string(":")), sage_str(s_port))); printf("\n");
    sage_print_value(sage_string("[SMP] Awaiting ASSIGN... (accept_task will process on next tick)")); printf("\n");
    sage_index_set(s_session, sage_string("router_host"), s_host);
    sage_index_set(s_session, sage_string("router_port"), s_port);
    sage_index_set(s_session, sage_string("connected"), sage_bool(1));
    sage_index_set(s_session, sage_string("my_id"), s_assigned_id);
    sage_print_value(sage_add(sage_add(sage_string("[SMP] Assigned node ID: "), sage_str(s_assigned_id)), sage_string("  (pending router confirmation)"))); printf("\n");
    return sage_bool(1);
    return sage_nil();
}

static SageValue s_cmd_disconnect(int argc, SageValue* argv) {
    if (sage_truthy(sage_bool(!sage_truthy(sage_index(s_session, sage_string("connected")))))) {
        sage_print_value(sage_string("[SMP] Not connected.")); printf("\n");
        return sage_bool(0);
    }
    SageValue s_old_id = sage_index(s_session, sage_string("my_id"));
    SageValue s_leave_req = sage_dict(2, "op", s_SMP_OP_LEAVE, "node_id", s_old_id);
    (sage_push(s_router_conn_queue, s_leave_req), sage_nil());
    sage_index_set(s_session, sage_string("connected"), sage_bool(0));
    sage_index_set(s_session, sage_string("my_id"), sage_number(0));
    sage_index_set(s_session, sage_string("router_host"), sage_string(""));
    sage_index_set(s_session, sage_string("router_port"), sage_number(0));
    sage_print_value(sage_add(sage_add(sage_string("[SMP] LEAVE queued. Node ID "), sage_str(s_old_id)), sage_string(" released."))); printf("\n");
    return sage_bool(1);
    return sage_nil();
}

static SageValue s_cmd_send(int argc, SageValue* argv) {
    SageValue s_target_id = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_message = (argc > 1) ? argv[1] : sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(sage_index(s_session, sage_string("connected")))))) {
        sage_print_value(sage_string("[SMP] Not connected. Use: connect <router_host> <port>")); printf("\n");
        return sage_bool(0);
    }
    if (sage_truthy(sage_eq(sage_index(s_session, sage_string("my_id")), sage_number(0)))) {
        sage_print_value(sage_string("[SMP] No node ID assigned yet.")); printf("\n");
        return sage_bool(0);
    }
    SageValue s_envelope = ({ SageValue _args[6]; _args[0] = s_message; _args[1] = sage_index(s_session, sage_string("secret_key")); _args[2] = sage_index(s_session, sage_string("otp_pass")); _args[3] = sage_index(s_session, sage_string("otp_seed")); _args[4] = sage_index(s_session, sage_string("my_id")); _args[5] = s_target_id; s_crypto_seal(6, _args); });
    sage_index_set(s_session, sage_string("seq"), sage_add(sage_index(s_session, sage_string("seq")), sage_number(1)));
    (sage_push(sage_index(s_session, sage_string("outbox")), sage_dict(5, "seq", sage_index(s_session, sage_string("seq")), "to", s_target_id, "text", s_message, "payload", sage_index(s_envelope, sage_string("payload")), "ts", sage_number(0))), sage_nil());
    (sage_push(sage_index(s_session, sage_string("msg_log")), sage_dict(4, "dir", sage_string("OUT"), "to", s_target_id, "text", s_message, "ts", sage_number(0))), sage_nil());
    ({ SageValue _args[5]; _args[0] = sage_index(s_session, sage_string("my_id")); _args[1] = s_target_id; _args[2] = sage_index(s_envelope, sage_string("payload")); _args[3] = sage_index(s_envelope, sage_string("sig")); _args[4] = sage_index(s_envelope, sage_string("key_len")); s_router_route(5, _args); });
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("[OUT -> node-"), sage_str(s_target_id)), sage_string("] ")), s_message), sage_string("  (seq=")), sage_str(sage_index(s_session, sage_string("seq")))), sage_string(")"))); printf("\n");
    return sage_bool(1);
    return sage_nil();
}

static SageValue s_cmd_broadcast(int argc, SageValue* argv) {
    SageValue s_message = (argc > 0) ? argv[0] : sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(sage_index(s_session, sage_string("connected")))))) {
        sage_print_value(sage_string("[SMP] Not connected.")); printf("\n");
        return sage_bool(0);
    }
    (sage_push(sage_index(s_session, sage_string("msg_log")), sage_dict(4, "dir", sage_string("BCAST"), "to", sage_number(0), "text", s_message, "ts", sage_number(0))), sage_nil());
    SageValue s_ids = sage_dict_keys(sage_index(s_router_state, sage_string("clients")));
    SageValue s_sent = sage_number(0);
    { SageValue _iter_t29 = sage_range((int)sage_len(s_ids).as.number);
        for (int t29 = 0; t29 < sage_array_len(_iter_t29); t29++) {
            SageValue s_i = sage_array_get(_iter_t29, t29);
            SageValue s_c = sage_index(sage_index(s_router_state, sage_string("clients")), sage_index(s_ids, s_i));
            if (sage_truthy((sage_truthy(sage_index(s_c, sage_string("connected"))) ? sage_neq(sage_index(s_c, sage_string("id")), sage_index(s_session, sage_string("my_id"))) : sage_index(s_c, sage_string("connected"))))) {
                SageValue s_envelope = ({ SageValue _args[6]; _args[0] = s_message; _args[1] = sage_index(s_session, sage_string("secret_key")); _args[2] = sage_index(s_session, sage_string("otp_pass")); _args[3] = sage_index(s_session, sage_string("otp_seed")); _args[4] = sage_index(s_session, sage_string("my_id")); _args[5] = sage_index(s_c, sage_string("id")); s_crypto_seal(6, _args); });
                ({ SageValue _args[5]; _args[0] = sage_index(s_session, sage_string("my_id")); _args[1] = sage_index(s_c, sage_string("id")); _args[2] = sage_index(s_envelope, sage_string("payload")); _args[3] = sage_index(s_envelope, sage_string("sig")); _args[4] = sage_index(s_envelope, sage_string("key_len")); s_router_route(5, _args); });
                (s_sent = sage_add(s_sent, sage_number(1)));
            }
        }
    }
    sage_print_value(sage_add(sage_add(sage_string("[BCAST] Routed to "), sage_str(s_sent)), sage_string(" peer(s)"))); printf("\n");
    return sage_bool(1);
    return sage_nil();
}

static SageValue s_cmd_recv_simulate(int argc, SageValue* argv) {
    SageValue s_sender_id = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_encrypted_payload = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_envelope = sage_dict(4, "payload", s_encrypted_payload, "sig", ({ SageValue _args[3]; _args[0] = s_encrypted_payload; _args[1] = sage_index(s_session, sage_string("secret_key")); _args[2] = s_sender_id; s__sign(3, _args); }), "from", s_sender_id, "to", sage_index(s_session, sage_string("my_id")));
    SageValue s_plaintext = ({ SageValue _args[5]; _args[0] = s_envelope; _args[1] = sage_index(s_session, sage_string("secret_key")); _args[2] = sage_index(s_session, sage_string("otp_pass")); _args[3] = sage_index(s_session, sage_string("otp_seed")); _args[4] = s_sender_id; s_crypto_open(5, _args); });
    if (sage_truthy(sage_eq(s_plaintext, sage_nil()))) {
        sage_print_value(sage_add(sage_string("[SMP] Bad signature from node-"), sage_str(s_sender_id))); printf("\n");
        return sage_nil();
    }
    SageValue s_entry = sage_dict(4, "dir", sage_string("IN"), "from", s_sender_id, "text", s_plaintext, "ts", sage_number(0));
    (sage_push(sage_index(s_session, sage_string("inbox")), s_entry), sage_nil());
    (sage_push(sage_index(s_session, sage_string("msg_log")), s_entry), sage_nil());
    sage_print_value(sage_add(sage_add(sage_add(sage_string("[IN  <- node-"), sage_str(s_sender_id)), sage_string("] ")), s_plaintext)); printf("\n");
    ({ SageValue _args[2]; _args[0] = s_sender_id; _args[1] = s_plaintext; s__auto_relay_check(2, _args); });
    return s_plaintext;
    return sage_nil();
}

static SageValue s__poll_router_mailbox(int argc, SageValue* argv) {
    if (sage_truthy(sage_eq(sage_index(s_session, sage_string("my_id")), sage_number(0)))) {
        return sage_nil();
    }
    SageValue s_key = sage_str(sage_index(s_session, sage_string("my_id")));
    if (sage_truthy(sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_router_mailboxes; _args[1] = s_key; s_dict_has(2, _args); }))))) {
        return sage_nil();
    }
    SageValue s_mb = sage_index(s_router_mailboxes, s_key);
    SageValue s_msg = ({ SageValue _args[1]; _args[0] = s_mb; s_mb_recv(1, _args); });
    while (sage_truthy(sage_neq(s_msg, sage_nil()))) {
        SageValue s_payload = sage_index(s_msg, sage_string("payload"));
        SageValue s_key_len_val = sage_index(s_msg, sage_string("key_len"));
        if (sage_truthy(sage_eq(s_key_len_val, sage_nil()))) {
            (s_key_len_val = sage_len(sage_str(s_payload)));
        }
        if (sage_truthy((sage_truthy(({ SageValue _args[2]; _args[0] = s_msg; _args[1] = sage_string("sig"); s_dict_has(2, _args); })) ? sage_bool(sage_len(sage_index(s_msg, sage_string("sig"))).as.number >= sage_number(2).as.number) : ({ SageValue _args[2]; _args[0] = s_msg; _args[1] = sage_string("sig"); s_dict_has(2, _args); })))) {
            SageValue s_envelope = sage_dict(5, "payload", s_payload, "sig", sage_index(s_msg, sage_string("sig")), "key_len", s_key_len_val, "from", sage_index(s_msg, sage_string("from")), "to", sage_index(s_session, sage_string("my_id")));
            SageValue s_plaintext = ({ SageValue _args[5]; _args[0] = s_envelope; _args[1] = sage_index(s_session, sage_string("secret_key")); _args[2] = sage_index(s_session, sage_string("otp_pass")); _args[3] = sage_index(s_session, sage_string("otp_seed")); _args[4] = sage_index(s_msg, sage_string("from")); s_crypto_open(5, _args); });
            if (sage_truthy(sage_neq(s_plaintext, sage_nil()))) {
                (sage_push(sage_index(s_session, sage_string("inbox")), sage_dict(4, "dir", sage_string("IN"), "from", sage_index(s_msg, sage_string("from")), "text", s_plaintext, "ts", sage_index(s_msg, sage_string("ts")))), sage_nil());
                (sage_push(sage_index(s_session, sage_string("msg_log")), sage_dict(4, "dir", sage_string("IN"), "from", sage_index(s_msg, sage_string("from")), "text", s_plaintext, "ts", sage_index(s_msg, sage_string("ts")))), sage_nil());
                sage_print_value(sage_add(sage_add(sage_add(sage_string("[IN  <- node-"), sage_str(sage_index(s_msg, sage_string("from")))), sage_string("] ")), s_plaintext)); printf("\n");
                ({ SageValue _args[2]; _args[0] = sage_index(s_msg, sage_string("from")); _args[1] = s_plaintext; s__auto_relay_check(2, _args); });
            }
        } else {
            SageValue s_key_gen = ({ SageValue _args[3]; _args[0] = sage_index(s_session, sage_string("otp_pass")); _args[1] = s_key_len_val; _args[2] = sage_index(s_session, sage_string("otp_seed")); s__generate_otp_key(3, _args); });
            SageValue s_plaintext = ({ SageValue _args[2]; _args[0] = s_payload; _args[1] = s_key_gen; s__otp_decrypt(2, _args); });
            (sage_push(sage_index(s_session, sage_string("inbox")), sage_dict(4, "dir", sage_string("IN"), "from", sage_index(s_msg, sage_string("from")), "text", s_plaintext, "ts", sage_index(s_msg, sage_string("ts")))), sage_nil());
            (sage_push(sage_index(s_session, sage_string("msg_log")), sage_dict(4, "dir", sage_string("IN"), "from", sage_index(s_msg, sage_string("from")), "text", s_plaintext, "ts", sage_index(s_msg, sage_string("ts")))), sage_nil());
            sage_print_value(sage_add(sage_add(sage_add(sage_string("[IN  <- node-"), sage_str(sage_index(s_msg, sage_string("from")))), sage_string("] ")), s_plaintext)); printf("\n");
            ({ SageValue _args[2]; _args[0] = sage_index(s_msg, sage_string("from")); _args[1] = s_plaintext; s__auto_relay_check(2, _args); });
        }
        (s_msg = ({ SageValue _args[1]; _args[0] = s_mb; s_mb_recv(1, _args); }));
    }
    return sage_nil();
}

static SageValue s_cmd_inbox(int argc, SageValue* argv) {
    if (sage_truthy(sage_eq(sage_len(sage_index(s_session, sage_string("inbox"))), sage_number(0)))) {
        sage_print_value(sage_string("  (inbox empty)")); printf("\n");
        return sage_nil();
    }
    { SageValue _iter_t30 = sage_range((int)sage_len(sage_index(s_session, sage_string("inbox"))).as.number);
        for (int t30 = 0; t30 < sage_array_len(_iter_t30); t30++) {
            SageValue s_i = sage_array_get(_iter_t30, t30);
            SageValue s_m = sage_index(sage_index(s_session, sage_string("inbox")), s_i);
            sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  ["), sage_str(s_i)), sage_string("] FROM node-")), sage_str(sage_index(s_m, sage_string("from")))), sage_string(": ")), sage_index(s_m, sage_string("text")))); printf("\n");
        }
    }
    return sage_nil();
}

static SageValue s_cmd_outbox(int argc, SageValue* argv) {
    if (sage_truthy(sage_eq(sage_len(sage_index(s_session, sage_string("outbox"))), sage_number(0)))) {
        sage_print_value(sage_string("  (outbox empty)")); printf("\n");
        return sage_nil();
    }
    { SageValue _iter_t31 = sage_range((int)sage_len(sage_index(s_session, sage_string("outbox"))).as.number);
        for (int t31 = 0; t31 < sage_array_len(_iter_t31); t31++) {
            SageValue s_i = sage_array_get(_iter_t31, t31);
            SageValue s_m = sage_index(sage_index(s_session, sage_string("outbox")), s_i);
            sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  ["), sage_str(s_i)), sage_string("] TO node-")), sage_str(sage_index(s_m, sage_string("to")))), sage_string("  seq=")), sage_str(sage_index(s_m, sage_string("seq")))), sage_string("  \"")), sage_index(s_m, sage_string("text"))), sage_string("\""))); printf("\n");
        }
    }
    return sage_nil();
}

static SageValue s_cmd_log(int argc, SageValue* argv) {
    if (sage_truthy(sage_eq(sage_len(sage_index(s_session, sage_string("msg_log"))), sage_number(0)))) {
        sage_print_value(sage_string("  (no messages)")); printf("\n");
        return sage_nil();
    }
    { SageValue _iter_t32 = sage_range((int)sage_len(sage_index(s_session, sage_string("msg_log"))).as.number);
        for (int t32 = 0; t32 < sage_array_len(_iter_t32); t32++) {
            SageValue s_i = sage_array_get(_iter_t32, t32);
            SageValue s_m = sage_index(sage_index(s_session, sage_string("msg_log")), s_i);
            if (sage_truthy(sage_eq(sage_index(s_m, sage_string("dir")), sage_string("IN")))) {
                sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  ["), sage_str(s_i)), sage_string("] <- node-")), sage_str(sage_index(s_m, sage_string("from")))), sage_string(" | ")), sage_index(s_m, sage_string("text")))); printf("\n");
            } else {
                if (sage_truthy(sage_eq(sage_index(s_m, sage_string("dir")), sage_string("BCAST")))) {
                    sage_print_value(sage_add(sage_add(sage_add(sage_string("  ["), sage_str(s_i)), sage_string("] >> BCAST | ")), sage_index(s_m, sage_string("text")))); printf("\n");
                } else {
                    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  ["), sage_str(s_i)), sage_string("] -> node-")), sage_str(sage_index(s_m, sage_string("to")))), sage_string(" | ")), sage_index(s_m, sage_string("text")))); printf("\n");
                }
            }
        }
    }
    return sage_nil();
}

static SageValue s_cmd_set_secret(int argc, SageValue* argv) {
    SageValue s_key = (argc > 0) ? argv[0] : sage_nil();
    sage_index_set(s_session, sage_string("secret_key"), s_key);
    sage_print_value(sage_string("[SMP] Secret key updated.")); printf("\n");
    return sage_nil();
}

static SageValue s_cmd_set_otp_pass(int argc, SageValue* argv) {
    SageValue s_pass = (argc > 0) ? argv[0] : sage_nil();
    sage_index_set(s_session, sage_string("otp_pass"), s_pass);
    sage_print_value(sage_string("[SMP] OTP passphrase updated.")); printf("\n");
    return sage_nil();
}

static SageValue s_cmd_set_otp_seed(int argc, SageValue* argv) {
    SageValue s_seed = (argc > 0) ? argv[0] : sage_nil();
    sage_index_set(s_session, sage_string("otp_seed"), sage_tonumber(s_seed));
    sage_print_value(sage_add(sage_string("[SMP] OTP seed set to "), sage_str(sage_index(s_session, sage_string("otp_seed"))))); printf("\n");
    return sage_nil();
}

static SageValue s_cmd_show_crypto(int argc, SageValue* argv) {
    sage_print_value(sage_add(sage_string("  secret_key : "), sage_index(s_session, sage_string("secret_key")))); printf("\n");
    sage_print_value(sage_add(sage_string("  otp_pass   : "), sage_index(s_session, sage_string("otp_pass")))); printf("\n");
    sage_print_value(sage_add(sage_string("  otp_seed   : "), sage_str(sage_index(s_session, sage_string("otp_seed"))))); printf("\n");
    sage_print_value(sage_add(sage_add(sage_string("  my_id      : "), sage_str(sage_index(s_session, sage_string("my_id")))), sage_string("  (assigned by router)"))); printf("\n");
    return sage_nil();
}

static SageValue s_cmd_relay_on(int argc, SageValue* argv) {
    (s_relay_enabled = sage_bool(1));
    sage_print_value(sage_string("[Relay] Auto-relay ENABLED.")); printf("\n");
    return sage_nil();
}

static SageValue s_cmd_relay_off(int argc, SageValue* argv) {
    (s_relay_enabled = sage_bool(0));
    sage_print_value(sage_string("[Relay] Auto-relay DISABLED.")); printf("\n");
    return sage_nil();
}

static SageValue s_cmd_add_sender_rule(int argc, SageValue* argv) {
    SageValue s_sender_id = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_reply_msg = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_rule = sage_dict(4, "type", sage_string("sender"), "trigger", sage_tonumber(s_sender_id), "reply_msg", s_reply_msg, "target_id", sage_tonumber(s_sender_id));
    (sage_push(s_relay_rules, s_rule), sage_nil());
    SageValue s_idx = sage_sub(sage_len(s_relay_rules), sage_number(1));
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("[Relay] Rule ["), sage_str(s_idx)), sage_string("] SENDER  from=node-")), sage_str(s_sender_id)), sage_string(" -> reply=\"")), s_reply_msg), sage_string("\""))); printf("\n");
    return s_idx;
    return sage_nil();
}

static SageValue s_cmd_add_content_rule(int argc, SageValue* argv) {
    SageValue s_trigger_text = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_reply_msg = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_rule = sage_dict(4, "type", sage_string("content"), "trigger", s_trigger_text, "reply_msg", s_reply_msg, "target_id", sage_number(sage_number(0).as.number - sage_number(1).as.number));
    (sage_push(s_relay_rules, s_rule), sage_nil());
    SageValue s_idx = sage_sub(sage_len(s_relay_rules), sage_number(1));
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("[Relay] Rule ["), sage_str(s_idx)), sage_string("] CONTENT msg=\"")), s_trigger_text), sage_string("\" -> reply=\"")), s_reply_msg), sage_string("\""))); printf("\n");
    return s_idx;
    return sage_nil();
}

static SageValue s_cmd_remove_rule(int argc, SageValue* argv) {
    SageValue s_idx = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_i = sage_tonumber(s_idx);
    if (sage_truthy((sage_truthy(sage_lt(s_i, sage_number(0))) ? sage_lt(s_i, sage_number(0)) : sage_bool(s_i.as.number >= sage_len(s_relay_rules).as.number)))) {
        sage_print_value(sage_add(sage_string("[Relay] No rule at index "), sage_str(s_i))); printf("\n");
        return sage_bool(0);
    }
    sage_index_set(sage_index(s_relay_rules, s_i), sage_string("type"), sage_string("deleted"));
    sage_print_value(sage_add(sage_add(sage_string("[Relay] Rule ["), sage_str(s_i)), sage_string("] removed."))); printf("\n");
    return sage_bool(1);
    return sage_nil();
}

static SageValue s_cmd_list_rules(int argc, SageValue* argv) {
    if (sage_truthy(sage_eq(sage_len(s_relay_rules), sage_number(0)))) {
        sage_print_value(sage_string("  (no relay rules)")); printf("\n");
        return sage_nil();
    }
    { SageValue _iter_t33 = sage_range((int)sage_len(s_relay_rules).as.number);
        for (int t33 = 0; t33 < sage_array_len(_iter_t33); t33++) {
            SageValue s_i = sage_array_get(_iter_t33, t33);
            SageValue s_r = sage_index(s_relay_rules, s_i);
            if (sage_truthy(sage_eq(sage_index(s_r, sage_string("type")), sage_string("deleted")))) {
                sage_print_value(sage_add(sage_add(sage_string("  ["), sage_str(s_i)), sage_string("] <deleted>"))); printf("\n");
            } else {
                if (sage_truthy(sage_eq(sage_index(s_r, sage_string("type")), sage_string("sender")))) {
                    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  ["), sage_str(s_i)), sage_string("] SENDER   trigger=node-")), sage_str(sage_index(s_r, sage_string("trigger")))), sage_string("  reply=\"")), sage_index(s_r, sage_string("reply_msg"))), sage_string("\""))); printf("\n");
                } else {
                    if (sage_truthy(sage_eq(sage_index(s_r, sage_string("type")), sage_string("content")))) {
                        sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  ["), sage_str(s_i)), sage_string("] CONTENT  trigger=\"")), sage_index(s_r, sage_string("trigger"))), sage_string("\"  reply=\"")), sage_index(s_r, sage_string("reply_msg"))), sage_string("\""))); printf("\n");
                    }
                }
            }
        }
    }
    return sage_nil();
}

static SageValue s__auto_relay_check(int argc, SageValue* argv) {
    SageValue s_sender_id = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_plaintext = (argc > 1) ? argv[1] : sage_nil();
    if (sage_truthy(sage_bool(!sage_truthy(s_relay_enabled)))) {
        return sage_nil();
    }
    { SageValue _iter_t34 = sage_range((int)sage_len(s_relay_rules).as.number);
        for (int t34 = 0; t34 < sage_array_len(_iter_t34); t34++) {
            SageValue s_i = sage_array_get(_iter_t34, t34);
            SageValue s_r = sage_index(s_relay_rules, s_i);
            if (sage_truthy(sage_eq(sage_index(s_r, sage_string("type")), sage_string("deleted")))) {
                SageValue s_skip = sage_bool(1);
            } else {
                if (sage_truthy(sage_eq(sage_index(s_r, sage_string("type")), sage_string("sender")))) {
                    if (sage_truthy(sage_eq(sage_index(s_r, sage_string("trigger")), s_sender_id))) {
                        sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("[Relay] Rule ["), sage_str(s_i)), sage_string("] matched sender node-")), sage_str(s_sender_id)), sage_string(" -> auto-reply: \"")), sage_index(s_r, sage_string("reply_msg"))), sage_string("\""))); printf("\n");
                        ({ SageValue _args[2]; _args[0] = sage_index(s_r, sage_string("target_id")); _args[1] = sage_index(s_r, sage_string("reply_msg")); s_cmd_send(2, _args); });
                    }
                } else {
                    if (sage_truthy(sage_eq(sage_index(s_r, sage_string("type")), sage_string("content")))) {
                        if (sage_truthy(sage_eq(s_plaintext, sage_index(s_r, sage_string("trigger"))))) {
                            SageValue s_reply_to = s_sender_id;
                            if (sage_truthy(sage_neq(sage_index(s_r, sage_string("target_id")), sage_number(sage_number(0).as.number - sage_number(1).as.number)))) {
                                (s_reply_to = sage_index(s_r, sage_string("target_id")));
                            }
                            sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("[Relay] Rule ["), sage_str(s_i)), sage_string("] matched content \"")), sage_index(s_r, sage_string("trigger"))), sage_string("\" -> auto-reply: \"")), sage_index(s_r, sage_string("reply_msg"))), sage_string("\""))); printf("\n");
                            ({ SageValue _args[2]; _args[0] = s_reply_to; _args[1] = sage_index(s_r, sage_string("reply_msg")); s_cmd_send(2, _args); });
                        }
                    }
                }
            }
        }
    }
    return sage_nil();
}

static SageValue s_cmd_status(int argc, SageValue* argv) {
    SageValue s_id_str = sage_str(sage_index(s_session, sage_string("my_id")));
    if (sage_truthy(sage_eq(sage_index(s_session, sage_string("my_id")), sage_number(0)))) {
        (s_id_str = sage_string("(not assigned)"));
    }
    SageValue s_state = sage_string("disconnected");
    if (sage_truthy(sage_index(s_session, sage_string("connected")))) {
        (s_state = sage_add(sage_add(sage_add(sage_string("connected to router @ "), sage_index(s_session, sage_string("router_host"))), sage_string(":")), sage_str(sage_index(s_session, sage_string("router_port")))));
    }
    sage_print_value(sage_add(sage_string("  state      : "), s_state)); printf("\n");
    sage_print_value(sage_add(sage_string("  my node ID : "), s_id_str)); printf("\n");
    sage_print_value(sage_add(sage_string("  my_name    : "), sage_index(s_session, sage_string("my_name")))); printf("\n");
    sage_print_value(sage_add(sage_add(sage_string("  inbox      : "), sage_str(sage_len(sage_index(s_session, sage_string("inbox"))))), sage_string(" message(s)"))); printf("\n");
    sage_print_value(sage_add(sage_add(sage_string("  outbox     : "), sage_str(sage_len(sage_index(s_session, sage_string("outbox"))))), sage_string(" message(s)"))); printf("\n");
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_string("  relay      : "), sage_str(s_relay_enabled)), sage_string("  (")), sage_str(sage_len(s_relay_rules))), sage_string(" rules)"))); printf("\n");
    return sage_nil();
}

static SageValue s_cmd_help(int argc, SageValue* argv) {
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_strcat(sage_string("  SMP Client  v"), s_SMP_VERSION)); printf("\n");
    sage_print_value(sage_string("  ─────────────────────────────────────────────────────────────────")); printf("\n");
    sage_print_value(sage_string("  CONNECTION  (node IDs assigned by router on connect)")); printf("\n");
    sage_print_value(sage_string("    connect <host> <port>          Connect to an SMP router")); printf("\n");
    sage_print_value(sage_string("    disconnect                     Disconnect and release node ID")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_string("  MESSAGING  (crypto applied automatically, routed via router)")); printf("\n");
    sage_print_value(sage_string("    send <node_id> <message>       Send encrypted message to a node")); printf("\n");
    sage_print_value(sage_string("    broadcast <message>            Send to all connected peers")); printf("\n");
    sage_print_value(sage_string("    recv <sender_id> <payload>     Simulate router delivering a message")); printf("\n");
    sage_print_value(sage_string("    inbox                          Show received messages")); printf("\n");
    sage_print_value(sage_string("    outbox                         Show queued outgoing messages")); printf("\n");
    sage_print_value(sage_string("    log                            Show full message history")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_string("  CRYPTO CONFIG")); printf("\n");
    sage_print_value(sage_string("    set secret <key>               Set shared secret key")); printf("\n");
    sage_print_value(sage_string("    set otp_pass <passphrase>      Set OTP passphrase")); printf("\n");
    sage_print_value(sage_string("    set otp_seed <number>          Set OTP seed")); printf("\n");
    sage_print_value(sage_string("    crypto                         Show current crypto settings")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_string("  AUTO-RELAY  (automatic responses to incoming messages)")); printf("\n");
    sage_print_value(sage_string("    relay on / off                 Enable / disable auto-relay")); printf("\n");
    sage_print_value(sage_string("    relay rules                    List configured relay rules")); printf("\n");
    sage_print_value(sage_string("    relay add sender <id> <reply>  Auto-reply to a specific sender")); printf("\n");
    sage_print_value(sage_string("    relay add content <msg> <reply>Auto-reply when message matches text")); printf("\n");
    sage_print_value(sage_string("    relay remove <index>           Delete a relay rule by index")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_string("  GENERAL")); printf("\n");
    sage_print_value(sage_string("    status                         Show session state")); printf("\n");
    sage_print_value(sage_string("    help                           Show this help")); printf("\n");
    sage_print_value(sage_string("    quit  / exit                   Exit")); printf("\n");
    sage_print_value(sage_string("  ─────────────────────────────────────────────────────────────────")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    return sage_nil();
}

static SageValue s__join_parts(int argc, SageValue* argv) {
    SageValue s_parts = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_start = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_msg = sage_string("");
    { SageValue _iter_t35 = ({ SageValue _args[2]; _args[0] = s_start; _args[1] = sage_len(s_parts); s_range(2, _args); });
        for (int t35 = 0; t35 < sage_array_len(_iter_t35); t35++) {
            SageValue s_i = sage_array_get(_iter_t35, t35);
            if (sage_truthy(sage_gt(s_i, s_start))) {
                (s_msg = sage_add(s_msg, sage_string(" ")));
            }
            (s_msg = sage_add(s_msg, sage_index(s_parts, s_i)));
        }
    }
    return s_msg;
    return sage_nil();
}

static SageValue s_dispatch(int argc, SageValue* argv) {
    SageValue s_parts = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_cmd = sage_index(s_parts, sage_number(0));
    if (sage_truthy(sage_eq(s_cmd, sage_string("connect")))) {
        if (sage_truthy(sage_lt(sage_len(s_parts), sage_number(3)))) {
            sage_print_value(sage_string("Usage: connect <host> <port>")); printf("\n");
            return sage_nil();
        }
        ({ SageValue _args[2]; _args[0] = sage_index(s_parts, sage_number(1)); _args[1] = sage_tonumber(sage_index(s_parts, sage_number(2))); s_cmd_connect(2, _args); });
    } else {
        if (sage_truthy(sage_eq(s_cmd, sage_string("disconnect")))) {
            ({ SageValue _args[1]; s_cmd_disconnect(0, _args); });
        } else {
            if (sage_truthy(sage_eq(s_cmd, sage_string("send")))) {
                if (sage_truthy(sage_lt(sage_len(s_parts), sage_number(3)))) {
                    sage_print_value(sage_string("Usage: send <node_id> <message ...>")); printf("\n");
                    return sage_nil();
                }
                ({ SageValue _args[2]; _args[0] = sage_tonumber(sage_index(s_parts, sage_number(1))); _args[1] = ({ SageValue _args[2]; _args[0] = s_parts; _args[1] = sage_number(2); s__join_parts(2, _args); }); s_cmd_send(2, _args); });
            } else {
                if (sage_truthy(sage_eq(s_cmd, sage_string("broadcast")))) {
                    if (sage_truthy(sage_lt(sage_len(s_parts), sage_number(2)))) {
                        sage_print_value(sage_string("Usage: broadcast <message ...>")); printf("\n");
                        return sage_nil();
                    }
                    ({ SageValue _args[1]; _args[0] = ({ SageValue _args[2]; _args[0] = s_parts; _args[1] = sage_number(1); s__join_parts(2, _args); }); s_cmd_broadcast(1, _args); });
                } else {
                    if (sage_truthy(sage_eq(s_cmd, sage_string("recv")))) {
                        if (sage_truthy(sage_lt(sage_len(s_parts), sage_number(3)))) {
                            sage_print_value(sage_string("Usage: recv <sender_id> <encrypted_payload>")); printf("\n");
                            return sage_nil();
                        }
                        ({ SageValue _args[2]; _args[0] = sage_tonumber(sage_index(s_parts, sage_number(1))); _args[1] = sage_index(s_parts, sage_number(2)); s_cmd_recv_simulate(2, _args); });
                    } else {
                        if (sage_truthy(sage_eq(s_cmd, sage_string("inbox")))) {
                            ({ SageValue _args[1]; s_cmd_inbox(0, _args); });
                        } else {
                            if (sage_truthy(sage_eq(s_cmd, sage_string("outbox")))) {
                                ({ SageValue _args[1]; s_cmd_outbox(0, _args); });
                            } else {
                                if (sage_truthy(sage_eq(s_cmd, sage_string("log")))) {
                                    ({ SageValue _args[1]; s_cmd_log(0, _args); });
                                } else {
                                    if (sage_truthy(sage_eq(s_cmd, sage_string("set")))) {
                                        if (sage_truthy(sage_lt(sage_len(s_parts), sage_number(3)))) {
                                            sage_print_value(sage_string("Usage: set <secret|otp_pass|otp_seed> <value>")); printf("\n");
                                            return sage_nil();
                                        }
                                        SageValue s_field = sage_index(s_parts, sage_number(1));
                                        if (sage_truthy(sage_eq(s_field, sage_string("secret")))) {
                                            ({ SageValue _args[1]; _args[0] = sage_index(s_parts, sage_number(2)); s_cmd_set_secret(1, _args); });
                                        } else {
                                            if (sage_truthy(sage_eq(s_field, sage_string("otp_pass")))) {
                                                ({ SageValue _args[1]; _args[0] = sage_index(s_parts, sage_number(2)); s_cmd_set_otp_pass(1, _args); });
                                            } else {
                                                if (sage_truthy(sage_eq(s_field, sage_string("otp_seed")))) {
                                                    ({ SageValue _args[1]; _args[0] = sage_index(s_parts, sage_number(2)); s_cmd_set_otp_seed(1, _args); });
                                                } else {
                                                    sage_print_value(sage_add(sage_add(sage_string("Unknown field: "), s_field), sage_string("  (secret | otp_pass | otp_seed)"))); printf("\n");
                                                }
                                            }
                                        }
                                    } else {
                                        if (sage_truthy(sage_eq(s_cmd, sage_string("crypto")))) {
                                            ({ SageValue _args[1]; s_cmd_show_crypto(0, _args); });
                                        } else {
                                            if (sage_truthy(sage_eq(s_cmd, sage_string("relay")))) {
                                                if (sage_truthy(sage_lt(sage_len(s_parts), sage_number(2)))) {
                                                    sage_print_value(sage_string("Usage: relay <on|off|rules|add|remove>")); printf("\n");
                                                    return sage_nil();
                                                }
                                                SageValue s_sub = sage_index(s_parts, sage_number(1));
                                                if (sage_truthy(sage_eq(s_sub, sage_string("on")))) {
                                                    ({ SageValue _args[1]; s_cmd_relay_on(0, _args); });
                                                } else {
                                                    if (sage_truthy(sage_eq(s_sub, sage_string("off")))) {
                                                        ({ SageValue _args[1]; s_cmd_relay_off(0, _args); });
                                                    } else {
                                                        if (sage_truthy(sage_eq(s_sub, sage_string("rules")))) {
                                                            ({ SageValue _args[1]; s_cmd_list_rules(0, _args); });
                                                        } else {
                                                            if (sage_truthy(sage_eq(s_sub, sage_string("add")))) {
                                                                if (sage_truthy(sage_lt(sage_len(s_parts), sage_number(5)))) {
                                                                    sage_print_value(sage_string("Usage: relay add <sender|content> <trigger> <reply ...>")); printf("\n");
                                                                    return sage_nil();
                                                                }
                                                                SageValue s_kind = sage_index(s_parts, sage_number(2));
                                                                SageValue s_reply = ({ SageValue _args[2]; _args[0] = s_parts; _args[1] = sage_number(4); s__join_parts(2, _args); });
                                                                if (sage_truthy(sage_eq(s_kind, sage_string("sender")))) {
                                                                    ({ SageValue _args[2]; _args[0] = sage_index(s_parts, sage_number(3)); _args[1] = s_reply; s_cmd_add_sender_rule(2, _args); });
                                                                } else {
                                                                    if (sage_truthy(sage_eq(s_kind, sage_string("content")))) {
                                                                        ({ SageValue _args[2]; _args[0] = sage_index(s_parts, sage_number(3)); _args[1] = s_reply; s_cmd_add_content_rule(2, _args); });
                                                                    } else {
                                                                        sage_print_value(sage_add(sage_add(sage_string("Unknown rule type: "), s_kind), sage_string("  (sender | content)"))); printf("\n");
                                                                    }
                                                                }
                                                            } else {
                                                                if (sage_truthy(sage_eq(s_sub, sage_string("remove")))) {
                                                                    if (sage_truthy(sage_lt(sage_len(s_parts), sage_number(3)))) {
                                                                        sage_print_value(sage_string("Usage: relay remove <index>")); printf("\n");
                                                                        return sage_nil();
                                                                    }
                                                                    ({ SageValue _args[1]; _args[0] = sage_index(s_parts, sage_number(2)); s_cmd_remove_rule(1, _args); });
                                                                } else {
                                                                    sage_print_value(sage_add(sage_string("Unknown relay sub-command: "), s_sub)); printf("\n");
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            } else {
                                                if (sage_truthy(sage_eq(s_cmd, sage_string("status")))) {
                                                    ({ SageValue _args[1]; s_cmd_status(0, _args); });
                                                } else {
                                                    if (sage_truthy((sage_truthy(sage_eq(s_cmd, sage_string("help"))) ? sage_eq(s_cmd, sage_string("help")) : sage_eq(s_cmd, sage_string("?"))))) {
                                                        ({ SageValue _args[1]; s_cmd_help(0, _args); });
                                                    } else {
                                                        if (sage_truthy((sage_truthy(sage_eq(s_cmd, sage_string("quit"))) ? sage_eq(s_cmd, sage_string("quit")) : sage_eq(s_cmd, sage_string("exit"))))) {
                                                            sage_print_value(sage_string("Goodbye.")); printf("\n");
                                                            return sage_string("QUIT");
                                                        } else {
                                                            sage_print_value(sage_add(sage_add(sage_string("Unknown command: "), s_cmd), sage_string("  (type 'help')"))); printf("\n");
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return sage_nil();
}

static SageValue s_router_cmd_clients(int argc, SageValue* argv) {
    SageValue s_ids = sage_dict_keys(sage_index(s_router_state, sage_string("clients")));
    if (sage_truthy(sage_eq(sage_len(s_ids), sage_number(0)))) {
        sage_print_value(sage_string("  (no clients registered)")); printf("\n");
        return sage_nil();
    }
    sage_print_value(sage_string("  node-ID  name                  address               msgs   last_seen")); printf("\n");
    sage_print_value(sage_string("  ───────  ────────────────────  ────────────────────  ─────  ─────────")); printf("\n");
    { SageValue _iter_t36 = sage_range((int)sage_len(s_ids).as.number);
        for (int t36 = 0; t36 < sage_array_len(_iter_t36); t36++) {
            SageValue s_i = sage_array_get(_iter_t36, t36);
            SageValue s_c = sage_index(sage_index(s_router_state, sage_string("clients")), sage_index(s_ids, s_i));
            SageValue s_status = sage_string("online");
            if (sage_truthy(sage_bool(!sage_truthy(sage_index(s_c, sage_string("connected")))))) {
                (s_status = sage_string("offline"));
            }
            sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  "), sage_str(sage_index(s_c, sage_string("id")))), sage_string("        ")), sage_index(s_c, sage_string("name"))), sage_string("  ")), sage_index(s_c, sage_string("host"))), sage_string(":")), sage_str(sage_index(s_c, sage_string("port")))), sage_string("  ")), sage_str(sage_index(s_c, sage_string("msg_count")))), sage_string("  tick=")), sage_str(sage_index(s_c, sage_string("last_seen")))), sage_string(" (")), s_status), sage_string(")"))); printf("\n");
        }
    }
    return sage_nil();
}

static SageValue s_router_cmd_queue(int argc, SageValue* argv) {
    if (sage_truthy(sage_eq(sage_len(s_router_conn_queue), sage_number(0)))) {
        sage_print_value(sage_string("  (connection queue empty)")); printf("\n");
        return sage_nil();
    }
    { SageValue _iter_t37 = sage_range((int)sage_len(s_router_conn_queue).as.number);
        for (int t37 = 0; t37 < sage_array_len(_iter_t37); t37++) {
            SageValue s_i = sage_array_get(_iter_t37, t37);
            SageValue s_r = sage_index(s_router_conn_queue, s_i);
            sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  ["), sage_str(s_i)), sage_string("] op=")), sage_str(sage_index(s_r, sage_string("op")))), sage_string(" name=")), sage_index(s_r, sage_string("name"))), sage_string(" @ ")), sage_index(s_r, sage_string("host"))), sage_string(":")), sage_str(sage_index(s_r, sage_string("port"))))); printf("\n");
        }
    }
    return sage_nil();
}

static SageValue s_router_cmd_mailboxes(int argc, SageValue* argv) {
    SageValue s_ids = sage_dict_keys(s_router_mailboxes);
    if (sage_truthy(sage_eq(sage_len(s_ids), sage_number(0)))) {
        sage_print_value(sage_string("  (no mailboxes)")); printf("\n");
        return sage_nil();
    }
    { SageValue _iter_t38 = sage_range((int)sage_len(s_ids).as.number);
        for (int t38 = 0; t38 < sage_array_len(_iter_t38); t38++) {
            SageValue s_i = sage_array_get(_iter_t38, t38);
            SageValue s_mb = sage_index(s_router_mailboxes, sage_index(s_ids, s_i));
            sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  node-"), sage_str(sage_index(s_mb, sage_string("id")))), sage_string("  pending=")), sage_str(({ SageValue _args[1]; _args[0] = s_mb; s_mb_pending(1, _args); }))), sage_string("  sent=")), sage_str(sage_index(sage_index(s_mb, sage_string("stats")), sage_string("sent")))), sage_string("  received=")), sage_str(sage_index(sage_index(s_mb, sage_string("stats")), sage_string("received"))))); printf("\n");
        }
    }
    return sage_nil();
}

static SageValue s_router_cmd_route(int argc, SageValue* argv) {
    SageValue s_src_id = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_dst_id = (argc > 1) ? argv[1] : sage_nil();
    SageValue s_payload = (argc > 2) ? argv[2] : sage_nil();
    ({ SageValue _args[3]; _args[0] = sage_tonumber(s_src_id); _args[1] = sage_tonumber(s_dst_id); _args[2] = s_payload; s_router_route(3, _args); });
    return sage_nil();
}

static SageValue s_router_cmd_log(int argc, SageValue* argv) {
    if (sage_truthy(sage_eq(sage_len(sage_index(s_router_state, sage_string("route_log"))), sage_number(0)))) {
        sage_print_value(sage_string("  (no routed messages)")); printf("\n");
        return sage_nil();
    }
    { SageValue _iter_t39 = sage_range((int)sage_len(sage_index(s_router_state, sage_string("route_log"))).as.number);
        for (int t39 = 0; t39 < sage_array_len(_iter_t39); t39++) {
            SageValue s_i = sage_array_get(_iter_t39, t39);
            SageValue s_e = sage_index(sage_index(s_router_state, sage_string("route_log")), s_i);
            sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_add(sage_string("  ["), sage_str(s_i)), sage_string("] tick=")), sage_str(sage_index(s_e, sage_string("tick")))), sage_string("  node-")), sage_str(sage_index(s_e, sage_string("from")))), sage_string(" -> node-")), sage_str(sage_index(s_e, sage_string("to")))), sage_string("  ")), sage_str(sage_index(s_e, sage_string("payload_len")))), sage_string(" bytes"))); printf("\n");
        }
    }
    return sage_nil();
}

static SageValue s_router_cmd_tasks(int argc, SageValue* argv) {
    ({ SageValue _args[1]; s_rtos_print_tasks(0, _args); });
    return sage_nil();
}

static SageValue s_router_cmd_tick(int argc, SageValue* argv) {
    ({ SageValue _args[1]; s_rtos_tick_once(0, _args); });
    sage_print_value(sage_add(sage_add(sage_string("[RTOS] Manual tick "), sage_str(s_rtos_tick)), sage_string(" done."))); printf("\n");
    return sage_nil();
}

static SageValue s_router_cmd_status(int argc, SageValue* argv) {
    sage_print_value(sage_string("  mode        : ROUTER")); printf("\n");
    sage_print_value(sage_add(sage_string("  host        : "), sage_index(s_router_state, sage_string("host")))); printf("\n");
    sage_print_value(sage_add(sage_string("  port        : "), sage_str(sage_index(s_router_state, sage_string("port"))))); printf("\n");
    sage_print_value(sage_add(sage_string("  clients     : "), sage_str(sage_len(sage_dict_keys(sage_index(s_router_state, sage_string("clients"))))))); printf("\n");
    sage_print_value(sage_add(sage_add(sage_string("  conn queue  : "), sage_str(sage_len(s_router_conn_queue))), sage_string(" pending"))); printf("\n");
    sage_print_value(sage_add(sage_string("  next_id     : "), sage_str(sage_index(s_router_state, sage_string("next_id"))))); printf("\n");
    sage_print_value(sage_add(sage_string("  rtos tick   : "), sage_str(s_rtos_tick))); printf("\n");
    sage_print_value(sage_add(sage_string("  routed msgs : "), sage_str(sage_len(sage_index(s_router_state, sage_string("route_log")))))); printf("\n");
    sage_print_value(sage_add(sage_string("  hb count    : "), sage_str(sage_index(s_router_state, sage_string("heartbeat_ticks"))))); printf("\n");
    return sage_nil();
}

static SageValue s_router_cmd_help(int argc, SageValue* argv) {
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_strcat(sage_string("  SMP Router  v"), s_SMP_VERSION)); printf("\n");
    sage_print_value(sage_string("  ─────────────────────────────────────────────────────────────────")); printf("\n");
    sage_print_value(sage_string("  RTOS SCHEDULER  (runs automatically each prompt cycle)")); printf("\n");
    sage_print_value(sage_string("    tick                           Run one scheduler tick manually")); printf("\n");
    sage_print_value(sage_string("    tasks                          Show RTOS task list & states")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_string("  CLIENT MANAGEMENT  (auto-handled by accept_task)")); printf("\n");
    sage_print_value(sage_string("    clients                        List registered clients")); printf("\n");
    sage_print_value(sage_string("    queue                          Show pending connection queue")); printf("\n");
    sage_print_value(sage_string("    mailboxes                      Show per-client mailbox stats")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_string("  ROUTING")); printf("\n");
    sage_print_value(sage_string("    route <src> <dst> <payload>    Manually route a message")); printf("\n");
    sage_print_value(sage_string("    log                            Show routing history")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_string("  GENERAL")); printf("\n");
    sage_print_value(sage_string("    status                         Show router & RTOS status")); printf("\n");
    sage_print_value(sage_string("    help                           Show this help")); printf("\n");
    sage_print_value(sage_string("    quit  / exit                   Stop the router")); printf("\n");
    sage_print_value(sage_string("  ─────────────────────────────────────────────────────────────────")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    return sage_nil();
}

static SageValue s_router_dispatch(int argc, SageValue* argv) {
    SageValue s_parts = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_cmd = sage_index(s_parts, sage_number(0));
    if (sage_truthy(sage_eq(s_cmd, sage_string("clients")))) {
        ({ SageValue _args[1]; s_router_cmd_clients(0, _args); });
    } else {
        if (sage_truthy(sage_eq(s_cmd, sage_string("queue")))) {
            ({ SageValue _args[1]; s_router_cmd_queue(0, _args); });
        } else {
            if (sage_truthy(sage_eq(s_cmd, sage_string("mailboxes")))) {
                ({ SageValue _args[1]; s_router_cmd_mailboxes(0, _args); });
            } else {
                if (sage_truthy(sage_eq(s_cmd, sage_string("route")))) {
                    if (sage_truthy(sage_lt(sage_len(s_parts), sage_number(4)))) {
                        sage_print_value(sage_string("Usage: route <src_id> <dst_id> <payload ...>")); printf("\n");
                        return sage_nil();
                    }
                    ({ SageValue _args[3]; _args[0] = sage_index(s_parts, sage_number(1)); _args[1] = sage_index(s_parts, sage_number(2)); _args[2] = ({ SageValue _args[2]; _args[0] = s_parts; _args[1] = sage_number(3); s__join_parts(2, _args); }); s_router_cmd_route(3, _args); });
                } else {
                    if (sage_truthy(sage_eq(s_cmd, sage_string("log")))) {
                        ({ SageValue _args[1]; s_router_cmd_log(0, _args); });
                    } else {
                        if (sage_truthy(sage_eq(s_cmd, sage_string("tasks")))) {
                            ({ SageValue _args[1]; s_router_cmd_tasks(0, _args); });
                        } else {
                            if (sage_truthy(sage_eq(s_cmd, sage_string("tick")))) {
                                ({ SageValue _args[1]; s_router_cmd_tick(0, _args); });
                            } else {
                                if (sage_truthy(sage_eq(s_cmd, sage_string("status")))) {
                                    ({ SageValue _args[1]; s_router_cmd_status(0, _args); });
                                } else {
                                    if (sage_truthy((sage_truthy(sage_eq(s_cmd, sage_string("help"))) ? sage_eq(s_cmd, sage_string("help")) : sage_eq(s_cmd, sage_string("?"))))) {
                                        ({ SageValue _args[1]; s_router_cmd_help(0, _args); });
                                    } else {
                                        if (sage_truthy((sage_truthy(sage_eq(s_cmd, sage_string("quit"))) ? sage_eq(s_cmd, sage_string("quit")) : sage_eq(s_cmd, sage_string("exit"))))) {
                                            ({ SageValue _args[1]; s_rtos_halt(0, _args); });
                                            sage_print_value(sage_string("[Router] Shutting down.")); printf("\n");
                                            return sage_string("QUIT");
                                        } else {
                                            sage_print_value(sage_add(sage_add(sage_string("Unknown router command: "), s_cmd), sage_string("  (type 'help')"))); printf("\n");
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return sage_nil();
}

static SageValue s_parse_args(int argc, SageValue* argv) {
    SageValue s_mode_idx = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_argv = sage_nil() /* unsupported call: sage_get_property(s_sys, "args") */;
    SageValue s_i = sage_add(s_mode_idx, sage_number(1));
    while (sage_truthy(sage_lt(s_i, sage_len(s_argv)))) {
        SageValue s_arg = sage_index(s_argv, s_i);
        if (sage_truthy((sage_truthy(sage_eq(s_arg, sage_string("--help"))) ? sage_eq(s_arg, sage_string("--help")) : sage_eq(s_arg, sage_string("-h"))))) {
            sage_print_value(sage_string("Usage: smp_client [--router] [--port <port>] [--host <host>]")); printf("\n");
            sage_print_value(sage_string("")); printf("\n");
            sage_print_value(sage_string("  --router           Start in router mode")); printf("\n");
            sage_print_value(sage_add(sage_add(sage_string("  --port <port>      Port  (default: "), sage_str(s_DEFAULT_PORT)), sage_string(")"))); printf("\n");
            sage_print_value(sage_strcat(sage_strcat(sage_string("  --host <host>      Host  (default: "), s_DEFAULT_HOST), sage_string(")"))); printf("\n");
            sage_print_value(sage_string("  --help             Show this message")); printf("\n");
            sage_nil() /* unsupported call: sage_get_property(s_sys, "exit") */;
        } else {
            if (sage_truthy((sage_truthy(sage_eq(s_arg, sage_string("--router"))) ? sage_eq(s_arg, sage_string("--router")) : sage_eq(s_arg, sage_string("-r"))))) {
                (s__start_as_router = sage_bool(1));
            } else {
                if (sage_truthy((sage_truthy(sage_eq(s_arg, sage_string("--port"))) ? sage_eq(s_arg, sage_string("--port")) : sage_eq(s_arg, sage_string("-p"))))) {
                    (s_i = sage_add(s_i, sage_number(1)));
                    if (sage_truthy(sage_bool(s_i.as.number >= sage_len(s_argv).as.number))) {
                        sage_print_value(sage_string("Error: --port requires a value")); printf("\n");
                        sage_nil() /* unsupported call: sage_get_property(s_sys, "exit") */;
                    }
                    sage_nil();
                    SageValue s_p = sage_tonumber(sage_index(s_argv, s_i));
                    if (sage_truthy((sage_truthy((sage_truthy(sage_eq(s_p, sage_nil())) ? sage_eq(s_p, sage_nil()) : sage_lt(s_p, sage_number(1)))) ? (sage_truthy(sage_eq(s_p, sage_nil())) ? sage_eq(s_p, sage_nil()) : sage_lt(s_p, sage_number(1))) : sage_gt(s_p, sage_number(65535))))) {
                        sage_print_value(sage_string("Error: --port must be 1-65535")); printf("\n");
                        sage_nil() /* unsupported call: sage_get_property(s_sys, "exit") */;
                    }
                    sage_nil();
                    sage_index_set(s_session, sage_string("router_port"), s_p);
                    sage_index_set(s_router_state, sage_string("port"), s_p);
                } else {
                    if (sage_truthy((sage_truthy(sage_eq(s_arg, sage_string("--host"))) ? sage_eq(s_arg, sage_string("--host")) : sage_eq(s_arg, sage_string("-H"))))) {
                        (s_i = sage_add(s_i, sage_number(1)));
                        if (sage_truthy(sage_bool(s_i.as.number >= sage_len(s_argv).as.number))) {
                            sage_print_value(sage_string("Error: --host requires a value")); printf("\n");
                            sage_nil() /* unsupported call: sage_get_property(s_sys, "exit") */;
                        }
                        sage_nil();
                        sage_index_set(s_session, sage_string("router_host"), sage_index(s_argv, s_i));
                        sage_index_set(s_router_state, sage_string("host"), sage_index(s_argv, s_i));
                    } else {
                        sage_print_value(sage_add(sage_add(sage_string("Warning: unknown argument '"), s_arg), sage_string("'  (try --help)"))); printf("\n");
                    }
                }
            }
        }
        sage_nil();
        (s_i = sage_add(s_i, sage_number(1)));
    }
    sage_nil();
    return sage_nil();
}

static SageValue s_run_router_shell(int argc, SageValue* argv) {
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_string("  ╔══════════════════════════════════════════════╗")); printf("\n");
    sage_print_value(sage_strcat(sage_strcat(sage_string("  ║       SMP Router  v"), s_SMP_VERSION), sage_string("                  ║"))); printf("\n");
    sage_print_value(sage_string("  ║  RTOS-scheduled routing + auto registration  ║")); printf("\n");
    sage_print_value(sage_string("  ╚══════════════════════════════════════════════╝")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_add(sage_add(sage_add(sage_string("  Listening on "), sage_index(s_router_state, sage_string("host"))), sage_string(":")), sage_str(sage_index(s_router_state, sage_string("port"))))); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    sage_index_set(s_router_state, sage_string("enabled"), sage_bool(1));
    ({ SageValue _args[1]; s_rtos_init(0, _args); });
    ({ SageValue _args[3]; _args[0] = s_TASK_ACCEPT; _args[1] = sage_number(7); _args[2] = sage_number(1); s_rtos_task_create(3, _args); });
    ({ SageValue _args[3]; _args[0] = s_TASK_MESSAGE; _args[1] = sage_number(5); _args[2] = sage_number(2); s_rtos_task_create(3, _args); });
    ({ SageValue _args[3]; _args[0] = s_TASK_HEARTBEAT; _args[1] = sage_number(2); _args[2] = sage_number(10); s_rtos_task_create(3, _args); });
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_string("  RTOS tasks registered. The scheduler runs one tick before each")); printf("\n");
    sage_print_value(sage_string("  prompt, automatically accepting clients and routing messages.")); printf("\n");
    sage_print_value(sage_string("  Type 'help' for available commands.")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    SageValue s_running = sage_bool(1);
    while (sage_truthy(s_running)) {
        ({ SageValue _args[1]; s_rtos_tick_once(0, _args); });
        SageValue s_line = ({ SageValue _args[1]; _args[0] = sage_add(sage_add(sage_string("router[tick="), sage_str(s_rtos_tick)), sage_string("]> ")); s_input(1, _args); });
        if (sage_truthy((sage_truthy(sage_eq(s_line, sage_nil())) ? sage_eq(s_line, sage_nil()) : sage_eq(sage_len(sage_str(s_line)), sage_number(0))))) {
            SageValue s_skip = sage_bool(1);
        } else {
            SageValue s_parts = ({ SageValue _args[2]; _args[0] = sage_str(s_line); _args[1] = sage_string(" "); s_split(2, _args); });
            SageValue s_clean = sage_array(0);
            { SageValue _iter_t40 = sage_range((int)sage_len(s_parts).as.number);
                for (int t40 = 0; t40 < sage_array_len(_iter_t40); t40++) {
                    SageValue s_i = sage_array_get(_iter_t40, t40);
                    if (sage_truthy(sage_gt(sage_len(sage_index(s_parts, s_i)), sage_number(0)))) {
                        (sage_push(s_clean, sage_index(s_parts, s_i)), sage_nil());
                    }
                }
            }
            if (sage_truthy(sage_gt(sage_len(s_clean), sage_number(0)))) {
                SageValue s_result = ({ SageValue _args[1]; _args[0] = s_clean; s_router_dispatch(1, _args); });
                if (sage_truthy(sage_eq(s_result, sage_string("QUIT")))) {
                    (s_running = sage_bool(0));
                }
            }
        }
    }
    return sage_nil();
}

static SageValue s_run_client_shell(int argc, SageValue* argv) {
    sage_print_value(sage_string("")); printf("\n");
    sage_print_value(sage_string("  ╔══════════════════════════════════════════════╗")); printf("\n");
    sage_print_value(sage_strcat(sage_strcat(sage_string("  ║       SMP Client  v"), s_SMP_VERSION), sage_string("                  ║"))); printf("\n");
    sage_print_value(sage_string("  ║   OTP-encrypted messaging + auto-relay       ║")); printf("\n");
    sage_print_value(sage_string("  ╚══════════════════════════════════════════════╝")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    if (sage_truthy(sage_neq(sage_index(s_router_state, sage_string("port")), sage_number(0)))) {
        sage_print_value(sage_add(sage_string("  Default router port : "), sage_str(sage_index(s_router_state, sage_string("port"))))); printf("\n");
    }
    sage_nil();
    sage_print_value(sage_string("  Type 'help' for available commands.")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    ({ SageValue _args[1]; s_rtos_init(0, _args); });
    ({ SageValue _args[3]; _args[0] = s_TASK_ACCEPT; _args[1] = sage_number(7); _args[2] = sage_number(1); s_rtos_task_create(3, _args); });
    ({ SageValue _args[3]; _args[0] = s_TASK_MESSAGE; _args[1] = sage_number(5); _args[2] = sage_number(2); s_rtos_task_create(3, _args); });
    ({ SageValue _args[3]; _args[0] = s_TASK_HEARTBEAT; _args[1] = sage_number(2); _args[2] = sage_number(10); s_rtos_task_create(3, _args); });
    sage_print_value(sage_string("  [RTOS] Local router tasks initialized for simulation.")); printf("\n");
    sage_print_value(sage_string("")); printf("\n");
    SageValue s_running = sage_bool(1);
    while (sage_truthy(s_running)) {
        ({ SageValue _args[1]; s_rtos_tick_once(0, _args); });
        ({ SageValue _args[1]; s__poll_router_mailbox(0, _args); });
        SageValue s_id_label = sage_string("");
        if (sage_truthy(sage_neq(sage_index(s_session, sage_string("my_id")), sage_number(0)))) {
            (s_id_label = sage_add(sage_add(sage_string("[node-"), sage_str(sage_index(s_session, sage_string("my_id")))), sage_string("] ")));
        }
        SageValue s_line = ({ SageValue _args[1]; _args[0] = sage_add(sage_add(sage_add(sage_add(sage_string("smp-tick="), sage_str(sage_number(s_rtos_tick.as.number - sage_number(1).as.number))), sage_string(" ")), s_id_label), sage_string("> ")); s_input(1, _args); });
        if (sage_truthy((sage_truthy(sage_eq(s_line, sage_nil())) ? sage_eq(s_line, sage_nil()) : sage_eq(sage_len(sage_str(s_line)), sage_number(0))))) {
            SageValue s_skip = sage_bool(1);
        } else {
            SageValue s_parts = ({ SageValue _args[2]; _args[0] = sage_str(s_line); _args[1] = sage_string(" "); s_split(2, _args); });
            SageValue s_clean = sage_array(0);
            { SageValue _iter_t41 = sage_range((int)sage_len(s_parts).as.number);
                for (int t41 = 0; t41 < sage_array_len(_iter_t41); t41++) {
                    SageValue s_i = sage_array_get(_iter_t41, t41);
                    if (sage_truthy(sage_gt(sage_len(sage_index(s_parts, s_i)), sage_number(0)))) {
                        (sage_push(s_clean, sage_index(s_parts, s_i)), sage_nil());
                    }
                }
            }
            if (sage_truthy(sage_gt(sage_len(s_clean), sage_number(0)))) {
                SageValue s_result = ({ SageValue _args[1]; _args[0] = s_clean; s_dispatch(1, _args); });
                if (sage_truthy(sage_eq(s_result, sage_string("QUIT")))) {
                    (s_running = sage_bool(0));
                }
            }
        }
    }
    return sage_nil();
}

static SageValue s_main(int argc, SageValue* argv) {
    SageValue s_argv = sage_nil() /* unsupported call: sage_get_property(s_sys, "args") */;
    SageValue s_mode_idx = sage_number(sage_number(0).as.number - sage_number(1).as.number);
    { SageValue _iter_t42 = sage_range((int)sage_len(s_argv).as.number);
        for (int t42 = 0; t42 < sage_array_len(_iter_t42); t42++) {
            SageValue s_i = sage_array_get(_iter_t42, t42);
            SageValue s_arg = sage_index(s_argv, s_i);
            if (sage_truthy((sage_truthy((sage_truthy((sage_truthy((sage_truthy(sage_neq(s_arg, sage_string("sage"))) ? sage_neq(s_arg, sage_string("--jit")) : sage_neq(s_arg, sage_string("sage")))) ? sage_neq(s_arg, sage_string("--compile")) : (sage_truthy(sage_neq(s_arg, sage_string("sage"))) ? sage_neq(s_arg, sage_string("--jit")) : sage_neq(s_arg, sage_string("sage"))))) ? sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_arg; _args[1] = sage_string(".sage"); s_ends_with(2, _args); }))) : (sage_truthy((sage_truthy(sage_neq(s_arg, sage_string("sage"))) ? sage_neq(s_arg, sage_string("--jit")) : sage_neq(s_arg, sage_string("sage")))) ? sage_neq(s_arg, sage_string("--compile")) : (sage_truthy(sage_neq(s_arg, sage_string("sage"))) ? sage_neq(s_arg, sage_string("--jit")) : sage_neq(s_arg, sage_string("sage")))))) ? sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_arg; _args[1] = sage_string("sagesmp"); s_ends_with(2, _args); }))) : (sage_truthy((sage_truthy((sage_truthy(sage_neq(s_arg, sage_string("sage"))) ? sage_neq(s_arg, sage_string("--jit")) : sage_neq(s_arg, sage_string("sage")))) ? sage_neq(s_arg, sage_string("--compile")) : (sage_truthy(sage_neq(s_arg, sage_string("sage"))) ? sage_neq(s_arg, sage_string("--jit")) : sage_neq(s_arg, sage_string("sage"))))) ? sage_bool(!sage_truthy(({ SageValue _args[2]; _args[0] = s_arg; _args[1] = sage_string(".sage"); s_ends_with(2, _args); }))) : (sage_truthy((sage_truthy(sage_neq(s_arg, sage_string("sage"))) ? sage_neq(s_arg, sage_string("--jit")) : sage_neq(s_arg, sage_string("sage")))) ? sage_neq(s_arg, sage_string("--compile")) : (sage_truthy(sage_neq(s_arg, sage_string("sage"))) ? sage_neq(s_arg, sage_string("--jit")) : sage_neq(s_arg, sage_string("sage")))))))) {
                (s_mode_idx = s_i);
                break;
            }
            sage_nil();
        }
    }
    sage_nil();
    if (sage_truthy(sage_eq(s_mode_idx, sage_number(sage_number(0).as.number - sage_number(1).as.number)))) {
        sage_print_value(sage_string("Usage: sagesmp <relay|pi2|pi4|shell> [args...]")); printf("\n");
        return sage_nil();
    }
    sage_nil();
    SageValue s_mode = sage_index(s_argv, s_mode_idx);
    if (sage_truthy(sage_eq(s_mode, sage_string("relay")))) {
        ({ SageValue _args[1]; _args[0] = s_mode_idx; s_run_orangepi(1, _args); });
    } else {
        if (sage_truthy(sage_eq(s_mode, sage_string("pi2")))) {
            ({ SageValue _args[1]; _args[0] = s_mode_idx; s_run_rpi2(1, _args); });
        } else {
            if (sage_truthy(sage_eq(s_mode, sage_string("pi4")))) {
                ({ SageValue _args[1]; _args[0] = s_mode_idx; s_run_rpi4(1, _args); });
            } else {
                if (sage_truthy(sage_eq(s_mode, sage_string("shell")))) {
                    ({ SageValue _args[1]; _args[0] = s_mode_idx; s_parse_args(1, _args); });
                    if (sage_truthy(s__start_as_router)) {
                        ({ SageValue _args[1]; s_run_router_shell(0, _args); });
                    } else {
                        ({ SageValue _args[1]; s_run_client_shell(0, _args); });
                    }
                } else {
                    sage_print_value(sage_add(sage_string("Unknown mode: "), s_mode)); printf("\n");
                }
            }
        }
    }
    sage_nil();
    return sage_nil();
}

static SageValue s_ends_with(int argc, SageValue* argv) {
    SageValue s_s = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_suffix = (argc > 1) ? argv[1] : sage_nil();
    if (sage_truthy(sage_lt(sage_len(s_s), sage_len(s_suffix)))) {
        return sage_bool(0);
    }
    sage_nil();
    return sage_eq(({ SageValue _args[3]; _args[0] = s_s; _args[1] = sage_sub(sage_len(s_s), sage_len(s_suffix)); _args[2] = sage_len(s_suffix); s_substring(3, _args); }), s_suffix);
    return sage_nil();
}

int main(void) {
    /* import sys */
    /* import tcp */
    /* import thread */
    /* import io */
    s_DQ = ({ SageValue _args[1]; _args[0] = sage_number(34); s_chr(1, _args); });
    s_SMP_SECRET = sage_string("orangepi_cluster_secret_2026");
    s_RELAY_PORT = sage_number(42000);
    s_clients = sage_dict(0);
    s_clients_mutex = sage_nil() /* unsupported call: sage_get_property(s_thread, "mutex") */;
    sage_nil();
    sage_nil();
    sage_nil();
    s_ORANGEPI_HOST = sage_string("192.168.254.44");
    s_ORANGEPI_PORT = sage_number(42000);
    s_CLIENT_ID = sage_number(1);
    s_HEARTBEAT_INTERVAL = sage_number(60);
    sage_nil();
    sage_nil();
    sage_nil();
    sage_nil();
    s_ORANGEPI_HOST = sage_string("192.168.254.44");
    s_ORANGEPI_PORT = sage_number(42000);
    s_CLIENT_ID = sage_number(2);
    s_HEARTBEAT_INTERVAL = sage_number(60);
    sage_nil();
    sage_nil();
    sage_nil();
    sage_nil();
    s_SMP_VERSION = sage_string("1.0.0");
    s_SMP_OP_HEARTBEAT = sage_number(0);
    s_SMP_OP_MESSAGE = sage_number(1);
    s_SMP_OP_JOIN = sage_number(2);
    s_SMP_OP_LEAVE = sage_number(3);
    s_SMP_OP_ASSIGN = sage_number(10);
    s_SMP_OP_FORWARD = sage_number(11);
    s_NODE_STATE_DISCONNECTED = sage_number(0);
    s_NODE_STATE_CONNECTED = sage_number(2);
    s_NODE_STATE_READY = sage_number(3);
    s_DEFAULT_HOST = sage_string("127.0.0.1");
    s_DEFAULT_PORT = sage_number(42000);
    s_DEFAULT_MAX_NODES = sage_number(64);
    s_RTOS_MAX_TASKS = sage_number(16);
    s_RTOS_MAX_PRIORITY = sage_number(8);
    s_RTOS_GC_INTERVAL = sage_number(100);
    s_TASK_READY = sage_number(0);
    s_TASK_RUNNING = sage_number(1);
    s_TASK_SLEEPING = sage_number(2);
    s_TASK_BLOCKED = sage_number(3);
    s_TASK_SUSPENDED = sage_number(4);
    s_TASK_ACCEPT = sage_string("accept_task");
    s_TASK_MESSAGE = sage_string("message_task");
    s_TASK_HEARTBEAT = sage_string("heartbeat_task");
    s_rtos_tasks = sage_array(0);
    s_rtos_task_count = sage_number(0);
    s_rtos_current = sage_number(0);
    s_rtos_tick = sage_number(0);
    s_rtos_gc_ticks = sage_number(0);
    s_rtos_running = sage_bool(0);
    s_router_state = sage_dict(8, "enabled", sage_bool(0), "host", sage_string("0.0.0.0"), "port", s_DEFAULT_PORT, "clients", sage_dict(0), "next_id", sage_number(1), "route_log", sage_array(0), "heartbeat_ticks", sage_number(0), "client_timeout", sage_number(30));
    s_router_mailboxes = sage_dict(0);
    s_router_conn_queue = sage_array(0);
    s_session = sage_dict(12, "connected", sage_bool(0), "router_host", sage_string(""), "router_port", sage_number(0), "my_id", sage_number(0), "my_name", sage_string("smp-client"), "secret_key", sage_string("change_this_key"), "otp_pass", sage_string("change_this_passphrase"), "otp_seed", sage_number(12345), "inbox", sage_array(0), "outbox", sage_array(0), "msg_log", sage_array(0), "seq", sage_number(0));
    s_relay_rules = sage_array(0);
    s_relay_enabled = sage_bool(1);
    s__start_as_router = sage_bool(0);
    sage_nil();
    sage_nil();
    ({ SageValue _args[1]; s_main(0, _args); });
    return 0;
}
