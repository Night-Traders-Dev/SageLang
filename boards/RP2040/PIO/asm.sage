## The assembler needs a two-pass architecture. 
## The first pass scans the text to find labels (like .wrap_target:) and records their line numbers so that jmp instructions can branch to them. 
## The second pass parses the mnemonics and bitwise-packs them into the 16-bit opcodes the RP2040 hardware expects.

from strings import endswith

class PIOAssembler:
    proc init(self):
        self.labels = {}
        self.opcodes = []

    proc parse(self, source):
        # Pass 1: Resolve Labels
        let instr_count = 0
        let lines = split(source, "\n")
        
        for line in lines:
            # Strip comments and whitespace
            line = line.split("#")[0].strip()
            if (line == ""):
                continue
            
            # Save label addresses
            if (line.endswith(":")):
                let label_name = replace(line, ":", "")
#                self.labels[label_name] = instr_count
            else:
                instr_count = instr_count + 1

        # Pass 2: Generate Opcodes
        for line in lines:
            line = strip(split(line, "#")[0])
            if (line == "" or line.endswith(":")):
                continue
            
            let opcode = self.encode_instruction(line)
            self.opcodes.append(opcode)
            
        return self.opcodes

    proc encode_instruction(self, line):
        let parts = split(line, " ")
        let instr = parts[0]
        let opcode = 0
        
        # JMP Instruction format: 000 | Delay/Side(5) | Condition(3) | Address(5)
        if (instr == "jmp"):
            let target = parts[1]
            let addr = self.labels[target]
            
            # Shift bits into the correct 16-bit RP2040 opcode positions
            opcode = (0b000 << 13) | addr 
            
        # SET Instruction format: 111 | Delay/Side(5) | Destination(3) | Data(5)
        if (instr == "set"):
            let dest_str = parts[1]
            let dest_val = 0
            if (dest_str == "pins"):
                dest_val = 0b000
                
            let data = parts[2].to_int()
            opcode = (0b111 << 13) | (dest_val << 5) | data
            
        return opcode
