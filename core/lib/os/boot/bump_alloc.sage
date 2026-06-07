## os.boot.bump_alloc — Tiny Early Allocator (No GC)
## Simple bump allocator for the pre-kernel bootstrap phase.

## Initialize a bump allocator within a memory range
proc init(base, limit):
    return {
        "base": base,
        "limit": limit,
        "cursor": base
    }
end

## Allocate memory from the bump heap
proc alloc(heap, size, align):
    let current = heap["cursor"]
    # Align the cursor
    if align > 1:
        let rem = current % align
        if rem != 0:
            current = current + (align - rem)
        end
    end
    
    if current + size > heap["limit"]:
        return nil # Out of memory
    end
    
    heap["cursor"] = current + size
    return current
end

## Reset the allocator (free all)
proc free_all(heap):
    heap["cursor"] = heap["base"]
    return nil
end

## Get current heap usage
proc used(heap):
    return heap["cursor"] - heap["base"]
end
