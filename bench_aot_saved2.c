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

static SageValue s_fib(int argc, SageValue* argv);
static SageValue s_sieve(int argc, SageValue* argv);
static SageValue s_start_fib;
static SageValue s_f;
static SageValue s_end_fib;
static SageValue s_start_sieve;
static SageValue s_p;
static SageValue s_end_sieve;

static SageValue s_fib(int argc, SageValue* argv) {
    SageValue s_n = (argc > 0) ? argv[0] : sage_nil();
    if (sage_truthy(sage_bool(s_n.as.number <= sage_number(1).as.number))) {
        return s_n;
    }
    return sage_add(({ SageValue _args[1]; _args[0] = sage_sub(s_n, sage_number(1)); s_fib(1, _args); }), ({ SageValue _args[1]; _args[0] = sage_sub(s_n, sage_number(2)); s_fib(1, _args); }));
    return sage_nil();
}

static SageValue s_sieve(int argc, SageValue* argv) {
    SageValue s_limit = (argc > 0) ? argv[0] : sage_nil();
    SageValue s_is_prime = sage_array(1, sage_bool(1));
    SageValue s_count = sage_number(0);
    SageValue s_i = sage_number(0);
    while (sage_truthy(sage_lt(s_i, sage_number(5000)))) {
        SageValue s_j = sage_number(0);
        while (sage_truthy(sage_lt(s_j, s_limit))) {
            (s_count = sage_add(sage_add(s_count, s_i), s_j));
            (s_j = sage_add(s_j, sage_number(1)));
        }
        (s_i = sage_add(s_i, sage_number(1)));
    }
    return s_count;
    return sage_nil();
}

int main(void) {
    sage_print_value(sage_string("Running SageLang Benchmarks...")); printf("\n");
    s_start_fib = ({ SageValue _args[1]; s_clock(0, _args); });
    s_f = ({ SageValue _args[1]; _args[0] = sage_number(36); s_fib(1, _args); });
    s_end_fib = ({ SageValue _args[1]; s_clock(0, _args); });
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_string("Fibonacci(36): "), sage_str(s_f)), sage_string(" | Time: ")), sage_str(sage_sub(s_end_fib, s_start_fib))), sage_string(" s"))); printf("\n");
    s_start_sieve = ({ SageValue _args[1]; s_clock(0, _args); });
    s_p = ({ SageValue _args[1]; _args[0] = sage_number(5000); s_sieve(1, _args); });
    s_end_sieve = ({ SageValue _args[1]; s_clock(0, _args); });
    sage_print_value(sage_add(sage_add(sage_add(sage_add(sage_string("Nested_loop(5K x 5K): "), sage_str(s_p)), sage_string(" | Time: ")), sage_str(sage_sub(s_end_sieve, s_start_sieve))), sage_string(" s"))); printf("\n");
    return 0;
}
