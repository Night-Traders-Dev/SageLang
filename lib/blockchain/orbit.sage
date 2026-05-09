# lib/blockchain/orbit.sage

import math

# R_base: Initial base mining rate (0.082 ORBIT/sec)
let R_BASE = 0.082
# U_target: Target baseline users (10,000)
let U_TARGET = 10000.0
# S_max: Initial mining allocation (1,000,000,000 ORBIT)
let S_MAX = 1000000000.0
# B_halflife: Blocks per mining halving (100,000)
let B_HALFLIFE = 100000.0

proc calculate_mining_rate(users, current_supply, block_height, node_score):
    # UserFactor = (U_target / max(U, U_target))^0.5
    let u_effective = users
    if u_effective < U_TARGET:
        u_effective = U_TARGET
    
    let user_factor = math.pow(U_TARGET / u_effective, 0.5)
    
    # SupplyFactor = max(0, 1 - (S / S_max))
    # Note: S is the amount already mined
    let supply_factor = 1.0 - (current_supply / S_MAX)
    if supply_factor < 0.0:
        supply_factor = 0.0
        
    # TimeDecay = 0.5 ^ (B / B_halflife)
    let time_decay = math.pow(0.5, block_height / B_HALFLIFE)
    
    # NodeBoost = 1 + min(Score, 0.10)
    let boost = node_score
    if boost > 0.10:
        boost = 0.10
    let node_boost = 1.0 + boost
    
    return R_BASE * user_factor * supply_factor * time_decay * node_boost
