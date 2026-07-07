package sage.runtime

class SageException(val value: SageRuntime.Value) : Exception(SageRuntime.toKString(value))

open class SageObject(val className: String) {
    open val props = mutableMapOf<String, SageRuntime.Value>()
    open fun sageInit(vararg args: SageRuntime.Value): SageRuntime.Value = SageRuntime.nil
}

class SageAtomic(val atom: java.util.concurrent.atomic.AtomicLong) : SageObject("atomic")
class SageSemaphore(val sem: java.util.concurrent.Semaphore) : SageObject("semaphore")

object SageRuntime {

    sealed class Value {
        data class Num(val v: Double) : Value()
        data class Str(val v: String) : Value()
        data class Bool(val v: Boolean) : Value()
        object Nil : Value()
        data class Arr(val v: MutableList<Value>) : Value()
        data class Dict(val v: MutableMap<String, Value>) : Value()
        data class Tup(val v: List<Value>) : Value()
        data class Obj(val v: SageObject) : Value()
        data class Fn(val name: String, val f: (Array<out Value>) -> Value) : Value()
        data class Gen(val v: Sequence<Value>) : Value()
        data class Ptr(val buf: java.nio.ByteBuffer, val size: Int) : Value()
    }

    val nil: Value = Value.Nil
    fun num(v: Double): Value = Value.Num(v)
    fun num(v: Int): Value = Value.Num(v.toDouble())
    fun str(v: String): Value = Value.Str(v)
    fun bool(v: Boolean): Value = Value.Bool(v)
    fun array(vararg elems: Value): Value = Value.Arr(elems.toMutableList())
    fun dict(vararg pairs: Pair<String, Value>): Value = Value.Dict(mutableMapOf(*pairs))
    fun tuple(vararg elems: Value): Value = Value.Tup(elems.toList())
    fun fn(name: String, f: (Array<out Value>) -> Value): Value = Value.Fn(name, f)
    fun call(v: Value, vararg args: Value): Value = if(v is Value.Fn) v.f(args) else nil

    private val classRegistry = mutableMapOf<String, (Array<out Value>) -> Value>()
    fun init() { }
    fun registerClass(name: String, ctor: (Array<out Value>) -> Value) { classRegistry[name] = ctor }
    fun newInstance(className: String, vararg args: Value): Value {
        val ctor = classRegistry[className] ?: throw RuntimeException("Unknown class: $className")
        return ctor(args)
    }

    fun truthy(v: Value): Boolean = when (v) {
        is Value.Nil -> false; is Value.Bool -> v.v; is Value.Num -> v.v != 0.0
        is Value.Str -> v.v.isNotEmpty(); is Value.Arr -> v.v.isNotEmpty()
        is Value.Dict -> v.v.isNotEmpty(); else -> true
    }

    fun add(a: Value, b: Value): Value = when {
        a is Value.Num && b is Value.Num -> num(a.v + b.v)
        a is Value.Str || b is Value.Str -> str(toKString(a) + toKString(b))
        a is Value.Arr && b is Value.Arr -> Value.Arr((a.v + b.v).toMutableList())
        else -> num(toDouble(a) + toDouble(b))
    }
    fun sub(a: Value, b: Value): Value = num(toDouble(a) - toDouble(b))
    fun mul(a: Value, b: Value): Value = when {
        a is Value.Str && b is Value.Num -> str(a.v.repeat(b.v.toInt().coerceAtLeast(0)))
        a is Value.Num && b is Value.Str -> str(b.v.repeat(a.v.toInt().coerceAtLeast(0)))
        else -> num(toDouble(a) * toDouble(b))
    }
    fun div(a: Value, b: Value): Value = num(toDouble(a) / toDouble(b))
    fun mod(a: Value, b: Value): Value = num(toDouble(a) % toDouble(b))

    fun eq(a: Value, b: Value): Value = bool(equal(a, b))
    fun neq(a: Value, b: Value): Value = bool(!equal(a, b))
    fun gt(a: Value, b: Value): Value = bool(toDouble(a) > toDouble(b))
    fun lt(a: Value, b: Value): Value = bool(toDouble(a) < toDouble(b))
    fun gte(a: Value, b: Value): Value = bool(toDouble(a) >= toDouble(b))
    fun lte(a: Value, b: Value): Value = bool(toDouble(a) <= toDouble(b))
    fun equal(a: Value, b: Value): Boolean = when {
        a is Value.Nil && b is Value.Nil -> true
        a is Value.Num && b is Value.Num -> a.v == b.v
        a is Value.Str && b is Value.Str -> a.v == b.v
        a is Value.Bool && b is Value.Bool -> a.v == b.v
        else -> a == b
    }

    fun not(v: Value): Value = bool(!truthy(v))
    fun and(a: Value, b: Value): Value = if (truthy(a)) b else a
    fun or(a: Value, b: Value): Value = if (truthy(a)) a else b
    fun bitAnd(a: Value, b: Value): Value = num((toDouble(a).toLong() and toDouble(b).toLong()).toDouble())
    fun bitOr(a: Value, b: Value): Value = num((toDouble(a).toLong() or toDouble(b).toLong()).toDouble())
    fun bitXor(a: Value, b: Value): Value = num((toDouble(a).toLong() xor toDouble(b).toLong()).toDouble())
    fun bitNot(v: Value): Value = num(toDouble(v).toLong().inv().toDouble())
    fun shl(a: Value, b: Value): Value = num((toDouble(a).toLong() shl toDouble(b).toInt()).toDouble())
    fun shr(a: Value, b: Value): Value = num((toDouble(a).toLong() shr toDouble(b).toInt()).toDouble())

    fun len(v: Value): Value = num(when (v) {
        is Value.Str -> v.v.length.toDouble(); is Value.Arr -> v.v.size.toDouble()
        is Value.Dict -> v.v.size.toDouble(); is Value.Tup -> v.v.size.toDouble()
        else -> 0.0
    })
    fun index(collection: Value, idx: Value): Value = when (collection) {
        is Value.Arr -> { val i = toDouble(idx).toInt(); val e = if (i<0) collection.v.size+i else i; if (e in collection.v.indices) collection.v[e] else nil }
        is Value.Dict -> collection.v[toKString(idx)] ?: nil
        is Value.Str -> { val i = toDouble(idx).toInt(); val e = if (i<0) collection.v.length+i else i; if (e in collection.v.indices) str(collection.v[e].toString()) else nil }
        is Value.Tup -> { val i = toDouble(idx).toInt(); if (i in collection.v.indices) collection.v[i] else nil }
        else -> nil
    }
    fun indexSet(c: Value, idx: Value, v: Value): Value { when(c) { is Value.Arr -> { val i=toDouble(idx).toInt(); val e=if(i<0)c.v.size+i else i; if(e in c.v.indices) c.v[e]=v }; is Value.Dict -> c.v[toKString(idx)]=v; else -> {} }; return v }
    fun slice(c: Value, s: Value, e: Value): Value {
        if(c is Value.Arr){val a=if(s is Value.Nil)0 else toDouble(s).toInt();val b=if(e is Value.Nil)c.v.size else toDouble(e).toInt();return Value.Arr(c.v.subList(a.coerceAtLeast(0),b.coerceAtMost(c.v.size)).toMutableList())}
        if(c is Value.Str){val a=if(s is Value.Nil)0 else toDouble(s).toInt();val b=if(e is Value.Nil)c.v.length else toDouble(e).toInt();return str(c.v.substring(a.coerceAtLeast(0),b.coerceAtMost(c.v.length)))}
        return nil
    }
    fun push(arr: Value, value: Value): Value { if(arr is Value.Arr) arr.v.add(value); return nil }
    fun pop(arr: Value): Value { if(arr is Value.Arr && arr.v.isNotEmpty()) return arr.v.removeAt(arr.v.size-1); return nil }
    fun range(stop: Value): Value { val n=toDouble(stop).toInt(); return Value.Arr((0 until n).map{num(it.toDouble())}.toMutableList()) }
    fun range(start: Value, stop: Value): Value { val s=toDouble(start).toInt();val e=toDouble(stop).toInt(); return Value.Arr((s until e).map{num(it.toDouble())}.toMutableList()) }

    fun dictKeys(d: Value): Value = if(d is Value.Dict) Value.Arr(d.v.keys.map{str(it)}.toMutableList()) else nil
    fun dictValues(d: Value): Value = if(d is Value.Dict) Value.Arr(d.v.values.toMutableList()) else nil
    fun dictHas(d: Value, key: Value): Value = bool(d is Value.Dict && toKString(key) in d.v)
    fun dictDelete(d: Value, key: Value): Value { if(d is Value.Dict) d.v.remove(toKString(key)); return nil }
    fun dictSet(d: Value, key: Value, value: Value): Value { if(d is Value.Dict) d.v[toKString(key)]=value; return value }
    fun dictGet(d: Value, key: Value): Value = if(d is Value.Dict) d.v[toKString(key)] ?: nil else nil

    fun str(v: Value): Value = Value.Str(toKString(v))
    fun toNumber(v: Value): Value = num(toDouble(v))
    fun typeOf(v: Value): Value = str(when(v) {
        is Value.Num->"number";is Value.Str->"string";is Value.Bool->"bool";is Value.Nil->"nil"
        is Value.Arr->"array";is Value.Dict->"dict";is Value.Tup->"tuple"
        is Value.Obj->v.v.className;is Value.Fn->"function";is Value.Gen->"generator";is Value.Ptr->"pointer"
    })
    fun toKString(v: Value): String = when(v) {
        is Value.Num -> { val d=v.v; if(d==d.toLong().toDouble()) d.toLong().toString() else d.toString() }
        is Value.Str -> v.v; is Value.Bool -> if(v.v) "true" else "false"; is Value.Nil -> "nil"
        is Value.Arr -> "[" + v.v.joinToString(", "){toKString(it)} + "]"
        is Value.Dict -> "{" + v.v.entries.joinToString(", "){"\"${it.key}\": ${toKString(it.value)}"} + "}"
        is Value.Tup -> "(" + v.v.joinToString(", "){toKString(it)} + ")"
        is Value.Obj -> "<${v.v.className} instance>"; is Value.Fn -> "<function ${v.name}>"
        is Value.Gen -> "<generator>"; is Value.Ptr -> "<pointer ${v.size}B>"
    }
    fun toDouble(v: Value): Double = when(v) { is Value.Num->v.v; is Value.Str->v.v.toDoubleOrNull()?:0.0; is Value.Bool->if(v.v)1.0 else 0.0; else->0.0 }

    fun toIterable(v: Value): Iterable<Value> = when(v) { is Value.Arr->v.v; is Value.Str->v.v.map{str(it.toString())}; is Value.Dict->v.v.keys.map{str(it)}; is Value.Tup->v.v; is Value.Gen->v.v.asIterable(); else->emptyList() }

    fun getProperty(obj: Value, name: String): Value = when(obj) {
        is Value.Obj -> obj.v.props[name] ?: nil
        is Value.Dict -> obj.v[name] ?: nil
        is Value.Str -> when(name){"length"->num(obj.v.length.toDouble()); else->nil}
        is Value.Arr -> when(name){"length"->num(obj.v.size.toDouble()); else->nil}
        else -> nil
    }
    fun setProperty(obj: Value, name: String, value: Value): Value { when(obj){is Value.Obj->obj.v.props[name]=value; is Value.Dict->obj.v[name]=value; else->{}}; return value }

    fun callMethod(obj: Value, method: String, vararg args: Value): Value {
        if(obj is Value.Obj) { val m=obj.v::class.java.methods.firstOrNull{it.name==method}; if(m!=null) return try{m.invoke(obj.v,*args) as? Value ?: nil}catch(_:Exception){nil} }
        if(obj is Value.Str) return when(method) {
            "upper"->str(obj.v.uppercase()); "lower"->str(obj.v.lowercase()); "strip","trim"->str(obj.v.trim())
            "split"->if(args.isNotEmpty()) Value.Arr(obj.v.split(toKString(args[0])).map{str(it)}.toMutableList()) else nil
            "replace"->if(args.size>=2) str(obj.v.replace(toKString(args[0]),toKString(args[1]))) else nil
            "starts_with","startsWith"->if(args.isNotEmpty()) bool(obj.v.startsWith(toKString(args[0]))) else nil
            "ends_with","endsWith"->if(args.isNotEmpty()) bool(obj.v.endsWith(toKString(args[0]))) else nil
            "contains"->if(args.isNotEmpty()) bool(obj.v.contains(toKString(args[0]))) else nil
            "find"->if(args.isNotEmpty()) num(obj.v.indexOf(toKString(args[0])).toDouble()) else nil
            "join"->if(args.isNotEmpty()&&args[0] is Value.Arr) str((args[0] as Value.Arr).v.joinToString(obj.v){toKString(it)}) else nil
            else->nil
        }
        if(obj is Value.Arr) return when(method) {
            "push","append"->{ if(args.isNotEmpty()) obj.v.add(args[0]); nil }
            "pop"->if(obj.v.isNotEmpty()) obj.v.removeAt(obj.v.size-1) else nil
            "sort"->{ obj.v.sortWith(compareBy{toDouble(it)}); nil }; "reverse"->{ obj.v.reverse(); nil }
            "map"->if(args.isNotEmpty()&&args[0] is Value.Fn) Value.Arr(obj.v.map{(args[0] as Value.Fn).f(arrayOf(it))}.toMutableList()) else nil
            "filter"->if(args.isNotEmpty()&&args[0] is Value.Fn) Value.Arr(obj.v.filter{truthy((args[0] as Value.Fn).f(arrayOf(it)))}.toMutableList()) else nil
            "join"->if(args.isNotEmpty()) str(obj.v.joinToString(toKString(args[0])){toKString(it)}) else str(obj.v.joinToString(""){toKString(it)})
            else->nil
        }
        return nil
    }
    fun superCall(obj: Value, method: String, vararg args: Value): Value = callMethod(obj, method, *args)

    fun memAlloc(size: Value): Value { val n=toDouble(size).toInt().coerceIn(1,67108864); return Value.Ptr(java.nio.ByteBuffer.allocateDirect(n).order(java.nio.ByteOrder.nativeOrder()), n) }
    fun memFree(ptr: Value): Value { /* DirectByteBuffer is GC-managed on Android/JVM */ return nil }
    fun memRead(ptr: Value, offset: Value, type: Value): Value {
        if(ptr !is Value.Ptr) return nil; val o=toDouble(offset).toInt(); val t=toKString(type); val b=ptr.buf
        return try { when(t) { "byte"->num(b.get(o).toDouble()); "int"->num(b.getInt(o).toDouble()); "double"->num(b.getDouble(o))
            "string"->{ val sb=StringBuilder(); var i=o; while(i<ptr.size&&b.get(i)!=0.toByte()){sb.append(b.get(i).toInt().toChar());i++}; str(sb.toString()) }
            else->nil } } catch(_:Exception) { nil }
    }
    fun memWrite(ptr: Value, offset: Value, type: Value, value: Value): Value {
        if(ptr !is Value.Ptr) return nil; val o=toDouble(offset).toInt(); val t=toKString(type); val b=ptr.buf
        try { when(t) { "byte"->b.put(o, toDouble(value).toInt().toByte()); "int"->b.putInt(o, toDouble(value).toInt()); "double"->b.putDouble(o, toDouble(value))
            "string"->{ val s=toKString(value); for(i in s.indices) b.put(o+i, s[i].code.toByte()); b.put(o+s.length, 0) } } } catch(_:Exception){} ; return nil
    }

    private val ffiLibs = mutableMapOf<String, Any?>()
    fun ffiOpen(name: Value): Value { val n=toKString(name); try { System.loadLibrary(n.removeSuffix(".so").removePrefix("lib")); ffiLibs[n]=true; return str(n) } catch(_:Exception){ return nil } }
    fun ffiCall(lib: Value, func: Value, retType: Value, args: Value = nil): Value {
        // JNI native calls require pre-declared external functions;
        // this stub logs the call for debugging. Real FFI needs JNI bindings.
        val fname = toKString(func); val rt = toKString(retType)
        println("[FFI] call $fname -> $rt"); return nil
    }
    fun ffiClose(lib: Value): Value { if(lib is Value.Str) ffiLibs.remove(lib.v); return nil }

    fun printLn(v: Value) = println(toKString(v))
    fun input(): Value = str(readlnOrNull() ?: "")
    fun input(prompt: Value): Value { print(toKString(prompt)); return input() }
    fun gcCollect(): Value { System.gc(); return nil }
    fun gcStats(): Value = str("GC: JVM managed")

    fun atomicNew(v: Value): Value = Value.Obj(SageAtomic(java.util.concurrent.atomic.AtomicLong(toDouble(v).toLong())))
    fun atomicLoad(a: Value): Value = if(a is Value.Obj && a.v is SageAtomic) num(a.v.atom.get().toDouble()) else nil
    fun atomicStore(a: Value, v: Value): Value { if(a is Value.Obj && a.v is SageAtomic) a.v.atom.set(toDouble(v).toLong()); return nil }
    fun atomicAdd(a: Value, v: Value): Value = if(a is Value.Obj && a.v is SageAtomic) num(a.v.atom.addAndGet(toDouble(v).toLong()).toDouble()) else nil
    fun atomicCas(a: Value, exp: Value, des: Value): Value = if(a is Value.Obj && a.v is SageAtomic) bool(a.v.atom.compareAndSet(toDouble(exp).toLong(), toDouble(des).toLong())) else bool(false)

    fun semNew(v: Value): Value = Value.Obj(SageSemaphore(java.util.concurrent.Semaphore(toDouble(v).toInt())))
    fun semWait(s: Value): Value { if(s is Value.Obj && s.v is SageSemaphore) s.v.sem.acquire(); return nil }
    fun semPost(s: Value): Value { if(s is Value.Obj && s.v is SageSemaphore) s.v.sem.release(); return nil }
    fun semTryWait(s: Value): Value = if(s is Value.Obj && s.v is SageSemaphore) bool(s.v.sem.tryAcquire()) else bool(false)

    fun upper(v: Value): Value = if(v is Value.Str) str(v.v.uppercase()) else nil
    fun lower(v: Value): Value = if(v is Value.Str) str(v.v.lowercase()) else nil
    fun strip(v: Value): Value = if(v is Value.Str) str(v.v.trim()) else nil
    fun split(v: Value, d: Value): Value = if(v is Value.Str) Value.Arr(v.v.split(toKString(d)).map{str(it)}.toMutableList()) else nil
    fun join(items: Value, sep: Value): Value = when(items) { is Value.Arr -> str(items.v.joinToString(toKString(sep)){toKString(it)}); is Value.Tup -> str(items.v.joinToString(toKString(sep)){toKString(it)}); else -> nil }
    fun replace(v: Value, old: Value, new_: Value): Value = if(v is Value.Str) str(v.v.replace(toKString(old), toKString(new_))) else nil
    fun chr(v: Value): Value = str(toDouble(v).toInt().toChar().toString())
    fun ord(v: Value): Value = if(v is Value.Str && v.v.isNotEmpty()) num(v.v[0].code.toDouble()) else num(0.0)
    fun clock(): Value = num(System.nanoTime().toDouble() / 1e9)

    fun pathJoin(a: Value, b: Value): Value = str(toKString(a) + java.io.File.separator + toKString(b))
    fun pathExists(p: Value): Value = bool(java.io.File(toKString(p)).exists())
    fun pathBasename(p: Value): Value = str(java.io.File(toKString(p)).name)
    fun pathDirname(p: Value): Value = str(java.io.File(toKString(p)).parent ?: "")
    fun pathExt(p: Value): Value { val n=toKString(p); val d=n.lastIndexOf('.'); return if(d>=0) str(n.substring(d)) else str("") }

    fun hash(v: Value): Value = num(v.hashCode().toDouble())
    fun sizeOf(v: Value): Value = num(when(v) { is Value.Str->v.v.length.toDouble()*2; is Value.Arr->v.v.size.toDouble()*24; else->8.0 })
}
