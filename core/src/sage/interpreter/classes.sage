// ============================================================================
# Interpreter Classes - Class and instance handling
# ============================================================================
// Part of the Reference VM tier
// ============================================================================

import ast
import runtime.values as values
import runtime.objects as objects
import runtime.errors as errors

// Evaluate class definition (called from eval_stmt)
proc eval_class(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    // Create class object
    let class_obj = objects.Class(
        class_id: make_class_id(stmt.name),
        name: stmt.name,
        super_class: stmt.super_class,
        methods: {} as Dict<String, Value>,
        fields: [],
        field_slots: {} as Dict<String, Int>
    )
    
    // Evaluate class body - collect methods and fields
    let prev_env = ctx.current_env
    ctx.current_env = env.env_create(prev_env)
    
    // Process class members
    let i = 0
    while i < len(stmt.members):
        let member = stmt.members[i]
        match member.kind:
            STMT_PROC:
                // Method definition
                let method = eval_proc(ctx, member)
                class_obj.methods[member.name] = method
            STMT_LET:
                // Field definition
                let field_name = member.name
                class_obj.fields = class_obj.fields.push(field_name)
                class_obj.field_slots[field_name] = class_obj.fields.len - 1
            _:
                // Other members (static fields, etc.)
                pass
        i = i + 1
    
    // Assign field slots
    objects.assign_field_slots(class_obj)
    
    ctx.current_env = prev_env
    
    // Define class in current scope
    env_define(ctx.current_env, stmt.name, class_obj)
    return control.result_normal(values.nil)

// Class creation
proc make_class_id(name: String): ClassId =
    ClassId(hash: name.hash(), name: name)

// Create an instance
proc create_instance(ctx: InterpreterContext, class_val: Value, args: Array<Value>): Value =
    let class_obj = class_val.data.fn_val  // Actually a Class
    
    // Call constructor if present
    if dict_has(class_obj.methods, "__init__"):
        let init_method = class_obj.methods["__init__"]
        let instance = objects.new_instance(class_obj, {} as Dict<String, Value>)
        // Call __init__ with instance as self
        runtime_call(ctx, init_method, args.prepend(instance), None)
        return values.value_instance(instance)
    
    // Default: create instance with no initialization
    let instance = objects.new_instance(class_obj, {} as Dict<String, Value>)
    return values.value_instance(instance)

// Instance property access
proc instance_get_property(ctx: InterpreterContext, instance: Value, name: String): Value =
    let inst = instance.data.fn_val  // Actually an Instance
    return objects.instance_get_field(inst, name)

// Instance property set
proc instance_set_property(ctx: InterpreterContext, instance: Value, name: String, value: Value): Unit =
    let inst = instance.data.fn_val
    objects.instance_set_field(inst, name, value)

// Method call on instance
proc instance_call_method(ctx: InterpreterContext, instance: Value, method_name: String, args: Array<Value>): Value =
    let inst = instance.data.fn_val
    return objects.instance_call_method(inst, method_name, args)

// Super call
proc call_super(ctx: InterpreterContext, instance: Value, method_name: String, args: Array<Value>): Value =
    let inst = instance.data.fn_val
    if inst.class_obj.super_class != None:
        let super_class = inst.class_obj.super_class
        if dict_has(super_class.methods, method_name):
            let method = super_class.methods[method_name]
            return runtime_call(ctx, method, args.prepend(instance))
    raise errors.error_property_not_found(inst.class_obj.name, "super." + method_name)

// Static method call
proc class_call_static(ctx: InterpreterContext, class_val: Value, method_name: String, args: Array<Value>): Value =
    let class_obj = class_val.data.fn_val
    if dict_has(class_obj.methods, method_name):
        let method = class_obj.methods[method_name]
        return runtime_call(ctx, method, args, None)
    raise errors.error_property_not_found(class_obj.name, method_name)
