// RISC-ICE-V
// inspired by https://github.com/sylefeb/Silice/blob/master/projects/ice-v/ice-v.ice
//
// A simple Risc-V RV32I processor

// RISC-V BASE INSTRUCTION BITFIELDS
bitfield    Btype {
    uint1   immediate_bits_12,
    uint6   immediate_bits_10_5,
    uint5   sourceReg2,
    uint5   sourceReg1,
    uint3   function3,
    uint4   immediate_bits_4_1,
    uint1   immediate_bits_11,
    uint7   opcode
}

bitfield    Itype {
    uint12  immediate,
    uint5   sourceReg1,
    uint3   function3,
    uint5   destReg,
    uint7   opcode
}

bitfield    ItypeSHIFT {
    uint7   function7,
    uint5   shiftCount,
    uint5   sourceReg1,
    uint3   function3,
    uint5   destReg,
    uint7   opcode
}

bitfield    Jtype {
    uint1   immediate_bits_20,
    uint10  immediate_bits_10_1,
    uint1   immediate_bits_11,
    uint8   immediate_bits_19_12,
    uint5   destReg,
    uint7   opcode
}

bitfield    Rtype {
    uint7   function7,
    uint5   sourceReg2,
    uint5   sourceReg1,
    uint3   function3,
    uint5   destReg,
    uint7   opCode
}

bitfield Stype {
    uint7   immediate_bits_11_5,
    uint5   sourceReg2,
    uint5   sourceReg1,
    uint3   function3,
    uint5   immediate_bits_4_0,
    uint7   opcode
}

bitfield Utype {
    uint20  immediate_bits_31_12,
    uint5   destReg,
    uint7   opCode
}

// COMPRESSED Risc-V Instruction Bitfields
bitfield    CI {
    uint3   function3,
    uint1   ib_5,
    uint5   rd,
    uint3   ib_4_2,
    uint2   ib_7_6,
    uint2   opcode
}
bitfield    CI50 {
    uint3   function3,
    uint1   ib_5,
    uint5   rd,
    uint5   ib_4_0,
    uint2   opcode
}
bitfield    CI94 {
    uint3   function3,
    uint1   ib_9,
    uint5   rd,
    uint1   ib_4,
    uint1   ib_6,
    uint2   ib_8_7,
    uint1   ib_5,
    uint2   opcode
}
bitfield    CIu94 {
    uint3   function3,
    uint2   ib_5_4,
    uint4   ib_9_6,
    uint1   ib_2,
    uint1   ib_3,
    uint3   rd_alt,
    uint2   opcode
}
bitfield    CIlui {
    uint3   function3,
    uint1   ib_17,
    uint5   rd,
    uint5   ib_16_12,
    uint2   opcode
}

bitfield    CBalu {
    uint3   function3,
    uint1   ib_5,
    uint2   function2,
    uint3   rd_alt,
    uint2   logical2,
    uint3   rd_alt,
    uint2   opcode
}

bitfield    CBalu50 {
    uint3   function3,
    uint1   ib_5,
    uint2   function2,
    uint3   rd_alt,
    uint5   ib_4_0,
    uint2   opcode
}

bitfield    CB {
    uint3   function3,
    uint1   offset_8,
    uint2   offset_4_3,
    uint3   rs1_alt,
    uint2   offset_7_6,
    uint2   offset_2_1,
    uint1   offset_5,
    uint2   opcode
}

bitfield    CJ {
    uint3   function3,
    uint1   ib_11,
    uint1   ib_4,
    uint2   ib_9_8,
    uint1   ib_10,
    uint1   ib_6,
    uint1   ib_7,
    uint3   ib_3_1,
    uint1   ib_5,
    uint2   opcode
}

bitfield    CR {
    uint4   function4,
    uint5   rs1,
    uint5   rs2,
    uint2   opcode
}

bitfield    CSS {
    uint3   function3,
    uint1   ib_5,
    uint3   ib_4_2,
    uint2   ib_7_6,
    uint5   rs2,
    uint2   opcode
}

bitfield    CL {
    uint3   function3,
    uint3   ib_5_3,
    uint3   rs1_alt,
    uint1   ib_2,
    uint1   ib_6,
    uint3   rd_alt,
    uint2   opcode
}

bitfield    CS {
    uint3   function3,
    uint1   ib_5,
    uint2   ib_4_3,
    uint3   rs1_alt,
    uint1   ib_2,
    uint1   ib_6,
    uint3   rs2_alt,
    uint2   opcode
}

algorithm main(
    // LEDS (8 of)
    output  uint8   leds,
    input   uint$NUM_BTNS$ btns,

    // HDMI OUTPUT
    output  uint4   gpdi_dp,
    output  uint4   gpdi_dn,

    // UART
    output! uint1   uart_tx,
    input   uint1   uart_rx,

    // AUDIO
    output! uint4   audio_l,
    output! uint4   audio_r

) {
    // VGA/HDMI Display
    uint1   video_reset = uninitialized;
    uint1   video_clock = uninitialized;
    uint1   pll_lock = uninitialized;

    // Generate the 100MHz SDRAM and 25MHz VIDEO clocks
    uint1 clock_50mhz = uninitialized;
    ulx3s_clk_50_25 clk_gen (
        clkin    <: clock,
        clkout0  :> clock_50mhz,
        clkout1  :> video_clock,
        locked   :> pll_lock
    );

    // Video Reset
    reset_conditioner vga_rstcond (
        rcclk <: video_clock ,
        in  <: reset,
        out :> video_reset
    );

    // Status of the screen, if in range, if in vblank, actual pixel x and y
    uint1   vblank = uninitialized;
    uint1   pix_active = uninitialized;
    uint10  pix_x  = uninitialized;
    uint10  pix_y  = uninitialized;

    // VGA or HDMI driver
    uint8   video_r = uninitialized;
    uint8   video_g = uninitialized;
    uint8   video_b = uninitialized;

    hdmi video<@clock,!reset> (
        vblank  :> vblank,
        active  :> pix_active,
        x       :> pix_x,
        y       :> pix_y,
        gpdi_dp :> gpdi_dp,
        gpdi_dn :> gpdi_dn,
        red     <: video_r,
        green   <: video_g,
        blue    <: video_b
    );

    // RISC-V RAM and BIOS
    bram uint16 ram[16384] = {
        $include('ROM/BIOS.inc')
        , pad(uninitialized)
    };

    // RISC-V REGISTERS
    dualport_bram int32 registers_1[64] = { 0, pad(0) };
    dualport_bram int32 registers_2[64] = { 0, pad(0) };

    // RISC-V PROGRAM COUNTER
    uint32  pc = 0;
    uint32  newPC = 0;
    uint1   compressed = 0;
    uint1   frs1 = 0;
    uint1   frs2 = 0;
    uint1   frd = 0;
    uint1   takeBranch = 0;

    // RISC-V INSTRUCTION and DECODE
    uint32  instruction = uninitialized;
    uint32  nop := { 12b000000000000, 5b00000, 3b000, 5b00000, 7b0010011 };
    uint7   opCode := Utype(instruction).opCode;
    uint3   function3 := Rtype(instruction).function3;
    uint7   function7 := Rtype(instruction).function7;

    // RISC-V SOURCE REGISTER VALUES and IMMEDIATE VALUE and DESTINATION REGISTER ADDRESS
    int32   sourceReg1 := registers_1.rdata0;
    int32   sourceReg2 := registers_2.rdata0;
    int32   immediateValue := { {20{instruction[31,1]}}, Itype(instruction).immediate };

    // RISC-V ALU RESULTS
    int32   result = uninitialized;
    uint1   writeRegister = uninitialized;

    // RISC-V ADDRESS CALCULATIONS
    uint32  branchOffset := { {20{Btype(instruction).immediate_bits_12}}, Btype(instruction).immediate_bits_11, Btype(instruction).immediate_bits_10_5, Btype(instruction).immediate_bits_4_1, 1b0 };
    uint32  loadAddress := immediateValue + sourceReg1;
    uint32  storeAddress := { {20{instruction[31,1]}}, Stype(instruction).immediate_bits_11_5, Stype(instruction).immediate_bits_4_0 } + sourceReg1;

    // Setup Memory Mapped I/O
    memmap_io IO_Map (
        leds :> leds,
        btns <: btns,

        // UART
        uart_tx :> uart_tx,
        uart_rx <: uart_rx,

        // AUDIO
        audio_l :> audio_l,
        audio_r :> audio_r,

        // VGA/HDMI
        video_r :> video_r,
        video_g :> video_g,
        video_b :> video_b,
        vblank <: vblank,
        pix_active <: pix_active,
        pix_x <: pix_x,
        pix_y <: pix_y,

        // CLOCKS
        clock_50mhz <: clock_50mhz,
        video_clock <:video_clock,
        video_reset <: video_reset
    );

    // MULTIPLICATION and DIVISION units
    divideremainder dividerunit <@clock_50mhz> (
        dividend <: sourceReg1,
        divisor <: sourceReg2
    );
    multiplicationDSP multiplicationuint <@clock_50mhz> (
        factor_1 <: sourceReg1,
        factor_2 <: sourceReg2
    );

    // MULTIPLICATION and DIVISION Start Flags
    dividerunit.start := 0;
    multiplicationuint.start := 0;

    // RAM/IO Read/Write Flags
    ram.wenable := 0;
    IO_Map.memoryWrite := 0;
    IO_Map.memoryRead := 0;

    // REGISTER Read/Write Flags
    registers_1.addr0 := Rtype(instruction).sourceReg1 + ( frs1 ? 32 : 0 );
    registers_1.wenable0 := 0;
    registers_1.wenable1 := 1;
    registers_2.addr0 := Rtype(instruction).sourceReg2 + ( frs2 ? 32 : 0 );
    registers_2.wenable0 := 0;
    registers_2.wenable1 := 1;

    while(1) {
        // RISC-V
        writeRegister = 1;
        takeBranch = 0;
        frs1 = 0; frs2 = 0; frd = 0;
        compressed = 0;

        // FETCH - 32 bit instruction
        ram.addr = pc[1,15];
        ++:
        switch( ram.rdata[0,2] ) {
            case 2b00: {
                compressed = 1;
                newPC = pc + 2;
                switch( ram.rdata[13,3] ) {
                    case 3b000: {
                        // ADDI4SPN -> addi rd', x2, nzuimm[9:2]
                        // { 000, nzuimm[5:4|9:6|2|3] rd' 00 }
                        instruction = { 2b0, CIu94(ram.rdata).ib_9_6, CIu94(ram.rdata).ib_5_4, CIu94(ram.rdata).ib_3, CIu94(ram.rdata).ib_2, 2b00, 5h2, 3b000, {2b01,CIu94(ram.rdata).rd_alt}, 7b0010011 };
                    }
                    case 3b001: {
                        // FLD
                        floatingpoint = 1; instruction = nop;
                    }
                    case 3b010: {
                        // LW -> lw rd', offset[6:2](rs1')
                        // { 010 uimm[5:3] rs1' uimm[2][6] rd' 00 }
                        instruction = { 5b0, CL(ram.rdata).ib_6, CL(ram.rdata).ib_5_3, CL(ram.rdata).ib_2, {2b01,CL(ram.rdata).rs1_alt}, 3b010, {2b01,CL(ram.rdata).rd_alt}, 7b0000011};
                    }
                    case 3b011: {
                        // FLW
                        frs1 = 1; frs2 = 1; frd = 1;
                        instruction = nop;
                    }
                    case 3b100: {
                        // reserved
                        instruction = nop;
                    }
                    case 3b101: {
                        // FSD
                        frs1 = 1; frs2 = 1; frd = 1;
                        instruction = nop;
                    }
                    case 3b110: {
                        // SW -> sw rs2', offset[6:2](rs1')
                        // { 110 uimm[5:3] rs1' uimm[2][6] rs2' 00 }
                        instruction = { 5b0, CS(ram.rdata).ib_6, CS(ram.rdata).ib_5, {2b01,CS(ram.rdata).rs2_alt}, {2b01,CS(ram.rdata).rs1_alt}, 3b010, CS(ram.rdata).ib_4_3, CS(ram.rdata).ib_2, 2b0, 7b0100011 };
                    }
                    case 3b111: {
                        // FSW
                        frs1 = 1; frs2 = 1; frd = 1;
                        instruction = nop;
                    }
                }
            }
            case 2b01: {
                compressed = 1;
                newPC = pc + 2;
                switch( ram.rdata[13,3] ) {
                    case 3b000: {
                        // ADDI -> addi rd, rd, nzimm[5:0]
                        // { 000 nzimm[5] rs1/rd!=0 nzimm[4:0] 01 }
                        instruction = { {7{CI50(ram.rdata).ib_5}}, CI50(ram.rdata).ib_4_0, CI50(ram.rdata).rd, 3b000, CI50(ram.rdata).rd, 7b0010011 };
                    }
                    case 3b001: {
                        // JAL -> jal x1, offset[11:1]
                        // { 001, imm[11|4|9:8|10|6|7|3:1|5] 01 }
                        instruction = { CJ(ram.rdata).ib_11, CJ(ram.rdata).ib_10, CJ(ram.rdata).ib_9_8, CJ(ram.rdata).ib_7, CJ(ram.rdata).ib_6, CJ(ram.rdata).ib_5, CJ(ram.rdata).ib_4, CJ(ram.rdata).ib_3_1, {9{CJ(ram.rdata).ib_11}}, 5h1, 7b1101111 };
                    }
                    case 3b010: {
                        // LI -> addi rd, x0, imm[5:0]
                        // { 010 imm[5] rd!=0 imm[4:0] 01 }
                        instruction = { {7{ CI50(ram.rdata).ib_5}}, CI50(ram.rdata).ib_4_0, 5h0, 3b000, CI(ram.rdata).rd, 7b0010011 };
                    }
                    case 3b011: {
                        // LUI / ADDI16SP
                        if( ( CI(ram.rdata).rd != 0 ) && ( CI(ram.rdata).rd != 2 ) ) {
                            // LUI -> addi rd, x0, imm[5:0]
                            // { 011 nzimm[17] rd!={0,2} nzimm[16:12] 01 }
                            instruction = { {15{CIlui(ram.rdata).ib_17}}, CIlui(ram.rdata).ib_16_12, CIlui(ram.rdata).rd, 7b0110111 };
                        } else {
                            // ADDI16SP -> addi x2, x2, nzimm[9:4]
                            // { 011 nzimm[9] 00010 nzimm[4|6|8:7|5] 01 }
                            instruction = { {3{CI94(ram.rdata).ib_9}}, CI94(ram.rdata).ib_8_7, CI94(ram.rdata).ib_6, CI94(ram.rdata).ib_5, CI94(ram.rdata).ib_4, 4b0000, 5h2, 3b000, 5h2, 7b0010011 };
                        }
                    }
                    case 3b100: {
                        // MISC-ALU
                        switch( CBalu(ram.rdata).function2 ) {
                            case 2b00: {
                                // SRLI
                            }
                            case 2b01: {
                                // SRAI
                            }
                            case 2b10: {
                                // ANDI
                            }
                            case 2b11: {
                                // SUB XOR OR AND
                                switch( CBalu(ram.rdata).logical2 ) {
                                    case 2b00: {
                                        //SUB
                                    }
                                    case 2b01: {
                                        // XOR
                                    }
                                    case 2b10: {
                                        // OR
                                    }
                                    case 2b11: {
                                        // AND
                                    }
                                }
                            }
                        }
                    }
                    case 3b101: {
                        // J -> jal, x0, offset[11:1]
                        // { 101, imm[11|4|9:8|10|6|7|3:1|5] 01 }
                        instruction = { CJ(ram.rdata).ib_11, CJ(ram.rdata).ib_10, CJ(ram.rdata).ib_9_8, CJ(ram.rdata).ib_7, CJ(ram.rdata).ib_6, CJ(ram.rdata).ib_5, CJ(ram.rdata).ib_4, CJ(ram.rdata).ib_3_1, {9{CJ(ram.rdata).ib_11}}, 5h0, 7b1101111 };
                    }
                    case 3b110: {
                        // BEQZ -> beq rs1', x0, offset[8:1]
                        // { 110, imm[8|4:3] rs1' imm[7:6|2:1|5] 01 }
                        instruction = { {4{CB(ram.rdata).offset_8}}, CB(ram.rdata).offset_7_6, CB(ram.rdata).offset_5, 5h0, {2b01,CB(ram.rdata).rs1_alt}, 3b000, CB(ram.rdata).offset_4_3, CB(ram.rdata).offset_2_1, CB(ram.rdata).offset_8, 7b1100011 };
                    }
                    case 3b111: {
                        // BNEZ -> bne rs1', x0, offset[8:1]
                        // { 111, imm[8|4:3] rs1' imm[7:6|2:1|5] 01 }
                        instruction = { {4{CB(ram.rdata).offset_8}}, CB(ram.rdata).offset_7_6, CB(ram.rdata).offset_5, 5h0, {2b01,CB(ram.rdata).rs1_alt}, 3b001, CB(ram.rdata).offset_4_3, CB(ram.rdata).offset_2_1, CB(ram.rdata).offset_8, 7b1100011 };
                    }
                }
            }
            case 2b10: {
                compressed = 1;
                newPC = pc + 2;
                switch( ram.rdata[13,3] ) {
                    case 3b000: {
                        // SLLI -> slli rd, rd, shamt[5:0]
                        // { 000, nzuimm[5], rs1/rd!=0 nzuimm[4:0] 10 }
                        instruction = { 7b0000000, CI50(ram.rdata).ib_4_0, CI50(ram.rdata).rd, 3b001, CI50(ram.rdata).rd, 7b0010011 };
                    }
                    case 3b001: {
                        // FLDSP
                        frs1 = 1; frs2 = 1; frd = 1;
                        instruction = nop;
                    }
                    case 3b010: {
                        // LWSP -> lw rd, offset[7:2](x2)
                        // { 011 uimm[5] rd uimm[4:2|7:6] 10 }
                        instruction = { 4b0, CI(ram.rdata).ib_7_6, CI(ram.rdata).ib_5, CI(ram.rdata).ib_4_2, 2b0, 5h2 ,3b010, CI(ram.rdata).rd, 7b0000011 };
                    }
                    case 3b011: {
                        // FLWSP
                        frs1 = 1; frs2 = 1; frd = 1;
                        instruction = nop;
                    }
                    case 3b100: {
                        // J[AL]R / MV / ADD
                        switch( ram.rdata[12,1] ) {
                            case 1b0: {
                                // JR / MV
                                if( CR(ram.rdata).rs2 == 0 ) {
                                    // JR -> jalr x0, rs1, 0
                                    // { 100 0 rs1 00000 10 }
                                    instruction = { 12b0, CR(ram.rdata).rs1, 3b000, 5h0, 7b1100111 };
                                } else {
                                    // MV
                                }
                            }
                            case 1b1: {
                                // JALR / ADD
                                if( CR(ram.rdata).rs2 == 0 ) {
                                    // JALR -> jalr x1, rs1, 0
                                    // { 100 1 rs1 00000 10 }
                                    instruction = { 12b0, CR(ram.rdata).rs1, 3b000, 5h1, 7b1100111 };
                                } else {
                                    // ADD
                                }
                            }
                        }
                    }
                    case 3b101: {
                        // FSDSP
                        frs1 = 1; frs2 = 1; frd = 1;
                        instruction = nop;
                    }
                    case 3b110: {
                        // SWSP -> sw rs2, offset[7:2](x2)
                        // { 110 uimm[5][4:2][7:6] rs2 10 }
                        instruction = { 4b0, CSS(ram.rdata).ib_7_6, CSS(ram.rdata).ib_5, CSS(ram.rdata).rs2, 5h2, 3b010, CSS(ram.rdata).ib_4_2, 2b0, 7b0100011 };
                    }
                    case 3b111: {
                        // FSWSP
                        frs1 = 1; frs2 = 1; frd = 1;
                        instruction = nop;
                    }
                }
            }
            case 2b11: {
                instruction = { 16b0, ram.rdata };
                ram.addr = pc[1,15] + 1;
                ++:
                instruction = { ram.rdata, instruction[0,16] };
                newPC = pc + 4;
            }
        }
        ++:
        ++:

        // DECODE + EXECUTE
        switch( { opCode[6,1], opCode[4,1] } ) {
            case 2b00: {
                // LOAD STORE
                switch( opCode[5,1] ) {
                    case 1b0: {
                        // LOAD execute even if rd == 0 as may be discarding values in a buffer
                        switch( loadAddress[15,1] ) {
                            case 0: {
                                ram.addr = loadAddress[1,15];
                                ++:
                                switch( function3 & 3 ) {
                                    case 2b00: {
                                        switch( loadAddress[0,1] ) {
                                            case 1b0: { result = { {24{ram.rdata[7,1] & ~function3[2,1]}}, ram.rdata[0,8] }; }
                                            case 1b1: { result = { {24{ram.rdata[15,1] & ~function3[2,1]}}, ram.rdata[8,8] }; }
                                        }
                                    }
                                    case 2b01: {
                                        result =  { {16{ram.rdata[15,1] & ~function3[2,1]}}, ram.rdata[0,16] };
                                    }
                                    case 2b10: {
                                        result = { 16b0, ram.rdata };
                                        ram.addr = loadAddress[1,15] + 1;
                                        ++:
                                        result = { ram.rdata, result[0,16] };
                                    }
                                }
                            }

                            case 1: {
                                IO_Map.memoryAddress = loadAddress[0,16];
                                IO_Map.memoryRead = 1;
                                switch( function3 & 3 ) {
                                    case 2b00: { result = { {24{IO_Map.readData[7,1] & ~function3[2,1]}}, IO_Map.readData[0,8] }; }
                                    case 2b01: { result = { {16{IO_Map.readData[15,1] & ~function3[2,1]}}, IO_Map.readData }; }
                                    case 2b10: { result = IO_Map.readData; }
                                }
                            }
                        }
                    }
                    case 1b1: {
                        // STORE
                        writeRegister = 0;
                        switch( storeAddress[15,1] ) {
                            case 1b0: {
                                ram.addr = storeAddress[1,15];
                                switch( function3 & 3 ) {
                                    case 2b00: {
                                        ++:
                                        switch( storeAddress[0,1] ) {
                                            case 1b0: { ram.wdata = { ram.rdata[8,8], sourceReg2[0,8] }; }
                                            case 1b1: { ram.wdata = { sourceReg2[0,8], ram.rdata[0,8] }; }
                                        }
                                        ram.wenable = 1;
                                    }
                                    case 2b01: {
                                        ram.wdata = sourceReg2[0,16];
                                        ram.wenable = 1;
                                    }
                                    case 2b10: {
                                        ram.wdata = sourceReg2[0,16];
                                        ram.wenable = 1;
                                        ++:
                                        ram.addr = storeAddress[1,15] + 1;
                                        ram.wdata = sourceReg2[16,16];
                                        ram.wenable = 1;
                                    }
                                }
                            }
                            case 1b1: {
                                IO_Map.memoryAddress = storeAddress[0,16];
                                IO_Map.writeData = sourceReg2[0,16];
                                IO_Map.memoryWrite = 1;
                            }
                        }
                    }
                }
            }

            case 2b01: {
                // AUIPC LUI ALUI ALUR
                switch( opCode[2,1] ) {
                    case 1b0: {
                        if( ( opCode[5,1] == 1 ) && ( function7[0,1] == 1 ) ) {
                            // M EXTENSION
                            switch( function3[2,1] ) {
                                case 1b0: {
                                    // MULTIPLICATION
                                    multiplicationuint.dosigned = ( function3[1,1] == 0 ) ? 1 : ( ( function3[0,1] == 0 ) ? 2 : 0 );
                                    multiplicationuint.start = 1;
                                    ++:
                                    while( multiplicationuint.active ) {}
                                    result = ( function3 == 0 ) ? multiplicationuint.product[0,32] : multiplicationuint.product[32,32];
                                }
                                case 1b1: {
                                    // DIVISION / REMAINDER
                                    dividerunit.dosigned = ~function3[0,1];
                                    dividerunit.start = 1;
                                    ++:
                                    while( dividerunit.active ) {}
                                    result = function3[1,1] ? dividerunit.remainder : dividerunit.quotient;
                                }
                            }
                        } else {
                            // I ALU OPERATIONS
                            switch( function3 ) {
                                case 3b000: {
                                    if( ( opCode[5,1] == 1 ) && ( function7[5,1] == 1 ) ) {
                                        result =sourceReg1 - sourceReg2;
                                    } else {
                                        result = sourceReg1 + ( ( opCode[5,1] == 1 ) ? sourceReg2 : immediateValue ); }
                                    }
                                case 3b001: { result = sourceReg1 << ( ( opCode[5,1] == 1 ) ? sourceReg2[0,5] : ItypeSHIFT( instruction ).shiftCount ); }
                                case 3b010: { result = __signed( sourceReg1 ) < ( ( opCode[5,1] == 1 ) ? __signed(sourceReg2) : __signed(immediateValue) ) ? 32b1 : 32b0; }
                                case 3b011: {
                                    switch( opCode[5,1] ) {
                                        case 1b0: {
                                            if( immediateValue == 1 ) {
                                                result = ( sourceReg1 == 0 ) ? 32b1 : 32b0;
                                            } else {
                                                result = ( __unsigned( sourceReg1 ) < __unsigned( immediateValue ) ) ? 32b1 : 32b0;
                                            }
                                        }
                                        case 1b1: {
                                            if( Rtype(instruction).sourceReg1 == 0 ) {
                                                result = ( sourceReg2 != 0 ) ? 32b1 : 32b0;
                                            } else {
                                                result = ( __unsigned( sourceReg1 ) < __unsigned( sourceReg2 ) ) ? 32b1 : 32b0;
                                            }
                                        }
                                    }
                                }
                                case 3b100: { result = sourceReg1 ^ ( ( opCode[5,1] == 1 ) ? sourceReg2 : immediateValue ); }
                                case 3b101: {
                                    switch( function7[5,1] ) {
                                        case 1b0: {
                                            result = __signed(sourceReg1) >>> ( ( opCode[5,1] == 1 ) ? sourceReg2[0,5] : ItypeSHIFT( instruction ).shiftCount );
                                        }
                                        case 1b1: {
                                            result = sourceReg1 >> ( ( opCode[5,1] == 1 ) ? sourceReg2[0,5] : ItypeSHIFT( instruction ).shiftCount );
                                        }
                                    }
                                }
                                case 3b110: { result = sourceReg1 | ( ( opCode[5,1] == 1 ) ? sourceReg2 : immediateValue ); }
                                case 3b111: { result = sourceReg1 & ( ( opCode[5,1] == 1 ) ? sourceReg2 : immediateValue ); }
                            }
                        }
                    }
                    case 1b1: {
                        // AUIPC LUI
                        result = { Utype(instruction).immediate_bits_31_12, 12b0 } + ( ( opCode[5,1] == 0 ) ? pc : 0 );
                    }
                }
            }

            case 2b10: {
                // JUMP BRANCH
                switch( opCode[2,1] ) {
                    case 1b0: {
                        // BRANCH on CONDITION
                        writeRegister = 0;
                        switch( function3 ) {
                            case 3b000: { takeBranch = ( sourceReg1 == sourceReg2 ) ? 1 : 0; }
                            case 3b001: { takeBranch = ( sourceReg1 != sourceReg2 ) ? 1 : 0; }
                            case 3b100: { takeBranch = ( __signed(sourceReg1) < __signed(sourceReg2) ) ? 1 : 0; }
                            case 3b101: { takeBranch = ( __signed(sourceReg1) >= __signed(sourceReg2) )  ? 1 : 0; }
                            case 3b110: { takeBranch = ( __unsigned(sourceReg1) < __unsigned(sourceReg2) ) ? 1 : 0; }
                            case 3b111: { takeBranch = ( __unsigned(sourceReg1) >= __unsigned(sourceReg2) ) ? 1 : 0; }
                        }
                    }
                    case 1b1: {
                        // JUMP AND LINK / JUMP AND LINK REGISTER
                        result = pc + ( compressed ? 2 : 4 );
                        newPC = ( opCode[3,1] == 1 ) ?
                                    { {12{Jtype(instruction).immediate_bits_20}}, Jtype(instruction).immediate_bits_19_12, Jtype(instruction).immediate_bits_11, Jtype(instruction).immediate_bits_10_1, 1b0 } + pc :
                                    loadAddress;
                    }
                }
            }
        }

        ++:

        // NEVER write to registers[0]
        if( writeRegister && ( Rtype(instruction).destReg != 0 ) ) {
            registers_1.addr1 = Rtype(instruction).destReg + ( frd ? 32 : 0 );
            registers_1.wdata1 = result;
            registers_2.addr1 = Rtype(instruction).destReg + ( frd ? 32 : 0 );
            registers_2.wdata1 = result;
        }

        pc = takeBranch ? pc + branchOffset : newPC;
    } // RISC-V
}