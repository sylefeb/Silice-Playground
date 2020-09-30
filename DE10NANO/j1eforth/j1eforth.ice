// VGA Driver Includes
$include('common/vga.ice')
import('common/de10nano_clk_100_25.v')
import('common/reset_conditioner.v')

algorithm multiplex_display(
  input   uint10 pix_x,
  input   uint10 pix_y,
  input   uint1  pix_active,
  input   uint1  pix_vblank,
  output! uint$color_depth$ pix_red,
  output! uint$color_depth$ pix_green,
  output! uint$color_depth$ pix_blue
) <autorun> {

    // Character ROM 
    //brom uint8 characterGenerator[] = {
    uint8 characterGenerator[] = {
        $include('characterROM8x16.inc')
    };

    // 80 x 30 character buffer and foreground and background colours in { rrrgggbb }
    // Setting character to 0 allows the bitmap to show through
    dualport_bram uint8 character[2400] = uninitialized;
    
    dualport_bram uint8 foreground[2400] = uninitialized;
    
    dualport_bram uint8 background[2400] = uninitialized;
   
    // 640 x 480 { rrrgggbb } colour bitmap
    dualport_bram uint8 bitmap[ 307200 ] = uninitialized;

    // Expansion map for { rrr } to { rrrrrr }, { ggg } to { gggggg }, { bb } to { bbbbbb }
    uint6 colourexpand3to6[8] = {  0, 9, 18, 27, 36, 45, 54, 63 };
    uint6 colourexpand2to6[4] = {  0, 21, 42, 63 };
    
    // Character position on the screen x 0-79, y 0-29 * 80 ( fetch it one pixel ahead of the actual x pixel, so it is always ready )
    uint8 xcharacterpos := (pix_x + 2 ) >> 3;
    uint8 ycharacterpos := ((pix_y + 2)  >> 4) * 80;
    
    // Derive the x and y coordinate within the current 8x16 character block x 0-7, y 0-15
    uint8 xincharacter := pix_x & 7;
    uint8 yincharacter := pix_y & 15;
    // Derive the actual pixel in the current character
    uint1 characterpixel := ((characterGenerator[ character.rdata0 * 16 + yincharacter ] << xincharacter) >> 7) & 1;

    // RGB is { 0,  0, 0 } by default
    pix_red   := 0;
    pix_green := 0;
    pix_blue  := 0;
    
    // Set up reading of character and attribute memory
    // character.rdata0 is the character, foreground.rdata0 and background.rdata0 are the attribute being rendered
    character.addr0 := xcharacterpos + ycharacterpos;
    character.wenable0 := 0;
    foreground.addr0 := xcharacterpos + ycharacterpos;
    foreground.wenable0 := 0;
    background.addr0 := xcharacterpos + ycharacterpos;
    background.wenable0 := 0;
    
    // Setup the address in the bitmap for the pixel being rendered
    bitmap.addr0 := pix_x  + pix_y * 640;
    bitmap.wenable0 := 0;

    while (1) {
        // wait until vblank is over
        while (pix_vblank == 1) {}
        
        while (pix_vblank == 0) {
            if( pix_active ) { //& ((pix_x > 0)&(pix_x<639) & ((pix_y>0)&(pix_y<479))) ) {
                switch( character.rdata0 ) {
                    case 0: {
                        // BITMAP
                        pix_red = colourexpand3to6[ (bitmap.rdata0 & 8he0) >> 5 ];
                        pix_green = colourexpand3to6[ (bitmap.rdata0 & 8h1c) >> 2 ];
                        pix_blue = colourexpand3to6[ (bitmap.rdata0 & 8h3) ];
                    }
                    default: {
                        // CHARACTER from characterGenerator
                        // Determine if background or foreground
                        switch( characterpixel ) {
                        case 0: {
                                // background
                                pix_red = colourexpand3to6[ (background.rdata0 & 8he0) >> 5 ];
                                pix_green = colourexpand3to6[ (background.rdata0 & 8h1c) >> 2 ];
                                pix_blue = colourexpand3to6[ (background.rdata0 & 8h3) ];
                            }
                            case 1: {
                                // foreground
                                pix_red = colourexpand3to6[ (foreground.rdata0 & 8he0) >> 5 ];
                                pix_green = colourexpand3to6[ (foreground.rdata0 & 8h1c) >> 2 ];
                                pix_blue = colourexpand3to6[ (foreground.rdata0 & 8h3) ];
                            }
                        }
                    }
                } // character or bitmap
            } // pix_active
        } // pix_vblank == 0
    }
}

// BITFIELDS to help with bit/field access

// Instruction is 3 bits 1xx = literal value, 000 = branch, 001 = 0branch, 010 = call, 011 = alu, followed by 13 bits of instruction specific data
bitfield instruction {
    uint3 is_litcallbranchalu,
    uint13 pad
}

// A literal instruction is 1 followed by a 15 bit UNSIGNED literal value
bitfield literal {
    uint1  is_literal,
    uint15 literalvalue
}

// A branch, 0branch or call instruction is 0 followed by 00 = branch, 01 = 0branch, 10 = call followed by 13bit target address 
bitfield callbranch {
    uint1  is_literal,
    uint2  is_callbranchalu,
    uint13 address
}
// An alu instruction is 0 (not literal) followed by 11 = alu
bitfield aluop {
    uint1   is_literal,
    uint2   is_callbranchalu,
    uint1   is_r2pc,                // return from subroutine
    uint4   operation,              // arithmetic / memory read/write operation to perform
    uint1   is_t2n,                 // top to next in stack
    uint1   is_t2r,                 // top to return stack
    uint1   is_n2memt,              // write to memory       
    uint1   is_j1j1plus,            // Original J1 or extra J1+ alu operations
    uint1   rdelta1,                // two's complement adjustment for rsp
    uint1   rdelta0,
    uint1   ddelta1,                // two's complement adjustment for dsp
    uint1   ddelta0
}

// Simplify access to high/low byte
bitfield bytes {
    uint8   byte1,
    uint8   byte0
}

// Simplify access to 4bit nibbles (used to extract shift left/right amount)
bitfield nibbles {
    uint4   nibble3,
    uint4   nibble2,
    uint4   nibble1,
    uint4   nibble0
}

algorithm main(
    // LEDS (8 of)
    output  uint8   led,
    
    // USER buttons
    input   uint8    buttons,

    // UART Interface
    output   uint8  uart_tx_data,
    output   uint1  uart_tx_valid,
    input    uint1  uart_tx_busy,
    input   uint1   uart_tx_done,
    input    uint8  uart_rx_data,
    input    uint1  uart_rx_valid,

    // SDRAM
    output! uint1  sdram_cle,
    output! uint1  sdram_dqm,
    output! uint1  sdram_cs,
    output! uint1  sdram_we,
    output! uint1  sdram_cas,
    output! uint1  sdram_ras,
    output! uint2  sdram_ba,
    output! uint13 sdram_a,
    output! uint1  sdram_clk,
    inout   uint8  sdram_dq,

    // VGA
    output! uint$color_depth$ video_r,
    output! uint$color_depth$ video_g,
    output! uint$color_depth$ video_b,
    output! uint1 video_hs,
    output! uint1 video_vs,

    // 1hz timer
    input   uint16 timer1hz
) {
    // VGA Text Display
  uint1 video_reset = 0;
  uint1 video_clock = 0;
  uint1 sdram_clock = 0;
  uint1 pll_lock = 0;
  de10nano_clk_100_25 clk_gen(
    refclk    <: clock,
    outclk_0  :> sdram_clock,
    outclk_1  :> video_clock,
    locked    :> pll_lock,
    rst       <: reset
  ); 

  // --- video reset
  reset_conditioner vga_rstcond (
    rcclk <: video_clock,
    in  <: reset,
    out :> video_reset
  );

  uint1  active = 0;
  uint1  vblank = 0;
  uint10 pix_x  = 0;
  uint10 pix_y  = 0;

  vga vga_driver <@video_clock,!video_reset>
  (
    vga_hs :> video_hs,
	  vga_vs :> video_vs,
	  active :> active,
	  vblank :> vblank,
	  vga_x  :> pix_x,
	  vga_y  :> pix_y
  );

  multiplex_display display <@video_clock,!video_reset>
  (
	  pix_x      <: pix_x,
	  pix_y      <: pix_y,
	  pix_active <: active,
	  pix_vblank <: vblank,
	  pix_red    :> video_r,
	  pix_green  :> video_g,
	  pix_blue   :> video_b
  );

  uint8 frame  = 0;

    // J1+ CPU
    // instruction being executed, plus decoding, including 5bit deltas for dsp and rsp expanded from 2bit encoded in the alu instruction
    uint16  instruction = uninitialized;
    uint16  immediate := ( literal(instruction).literalvalue );
    uint1   is_alu := ( instruction(instruction).is_litcallbranchalu == 3b011 );
    uint1   is_call := ( instruction(instruction).is_litcallbranchalu == 3b010 );
    uint1   is_lit := literal(instruction).is_literal;
    uint1   dstackWrite := ( is_lit | (is_alu & aluop(instruction).is_t2n) );
    uint1   rstackWrite := ( is_call | (is_alu & aluop(instruction).is_t2r) );
    uint8   ddelta := { {7{aluop(instruction).ddelta1}}, aluop(instruction).ddelta0 };
    uint8   rdelta := { {7{aluop(instruction).rdelta1}}, aluop(instruction).rdelta0 };
    
    // program counter
    uint13  pc = 0;
    uint13  pcPlusOne := pc + 1;
    uint13  newPC = uninitialized;

    // dstack 257x16bit (as 3256 array + stackTop) and pointer, next pointer, write line, delta
    bram uint16 dstack[256] = uninitialized; // bram (code from @sylefeb)
    uint16  stackTop = 0;
    uint8   dsp = 0;
    uint8   newDSP = uninitialized;
    uint16  newStackTop = uninitialized;

    // rstack 256x16bit and pointer, next pointer, write line
    bram uint16 rstack[256] = uninitialized; // bram (code from @sylefeb)
    uint8   rsp = 0;
    uint8   newRSP = uninitialized;
    uint16  rstackWData = uninitialized;

    uint16  stackNext = uninitialized;
    uint16  rStackTop = uninitialized;
    uint16  memoryInput = uninitialized;

    // 16bit ROM with included compiled j1eForth from https://github.com/samawati/j1eforth
    brom uint16 rom[] = {
        $include('j1eforthROM.inc')
    };
    
    dualport_bram uint16 ram[32768] = uninitialized;
    
    // CYCLE to control each stage
    // CYCLE allows 1 clock cycle for BRAM access and 3 clock cycles for SPRAM access
    // INIT to determine if copying rom to ram or executing
    // INIT 0 SPRAM, INIT 1 ROM to SPRAM, INIT 2 J1 CPU
    uint3 CYCLE = 0;
    uint2 INIT = 0;
    
    // Address for 0 to SPRAM, copying ROM, plus storage
    uint16 copyaddress = 0;
    uint16 bramREAD = 0;

    // UART input FIFO (512 character) as dualport bram (code from @sylefeb)
    dualport_bram uint8 uartInBuffer[256] = uninitialized;
    uint8 uartInBufferNext = 0;
    uint8 uartInBufferTop = 0;
    uint1 uartInHold = 1;

    // UART output FIFO (512 character) as dualport bram (code from @sylefeb)
    dualport_bram uint8 uartOutBuffer[256] = uninitialized;
    uint8 uartOutBufferNext = 0;
    uint8 uartOutBufferTop = 0;
    uint8 newuartOutBufferTop = 0;
    uint8 uartOutHold = 0;
    
    // bram for dstack and rstack write enable, maintained low, pulsed high (code from @sylefeb)
    dstack.wenable         := 0;  
    rstack.wenable         := 0;

    // dual port bram for dtsack and strack
    uartInBuffer.wenable0  := 0;  // always read  on port 0
    uartInBuffer.wenable1  := 1;  // always write on port 1
    uartInBuffer.addr0     := uartInBufferNext; // FIFO reads on next
    uartInBuffer.addr1     := uartInBufferTop;  // FIFO writes on top
    
    uartOutBuffer.wenable0 := 0; // always read  on port 0
    uartOutBuffer.wenable1 := 1; // always write on port 1    
    uartOutBuffer.addr0    := uartOutBufferNext; // FIFO reads on next
    uartOutBuffer.addr1    := uartOutBufferTop;  // FIFO writes on top

    // Lock out SDRAM for the J1+ CPU
    sdram_cle := 1bz;
    sdram_dqm := 1bz;
    sdram_cs  := 1bz;
    sdram_we  := 1bz;
    sdram_cas := 1bz;
    sdram_ras := 1bz;
    sdram_ba  := 2bz;
    sdram_a   := 13bz;
    sdram_clk := 1bz;
    
    // INIT is 0 ZERO dualport working blockram
    while( INIT == 0 ) {
        switch(CYCLE) {
            case 0: {
                ram.addr0 = copyaddress;
                ram.wdata0 = 0;
                ram.wenable0 = 1;
            }
            case 1: {
                copyaddress = copyaddress + 1;
                ram.wenable0 = 0;
            }
            case 4: {
                if( copyaddress == 32768 ) {
                    INIT = 1;
                    copyaddress = 0;
                }
            }
            default: {}
        }
        CYCLE = ( CYCLE == 4 ) ? 0 : CYCLE + 1;
    }
    
    // INIT is 1 COPY ROM TO RAM
    while( INIT == 1) {
        switch(CYCLE) {
            case 0: {
                // Setup READ from ROM
                rom.addr = copyaddress;
            }
            case 1: {
                bramREAD = rom.rdata;
            }
            case 2: {
                // WRITE to RAM
                ram.addr0 = copyaddress;
                ram.wdata0 = bramREAD;
                ram.wenable0 = 1;
            }
            case 3: {
                copyaddress = copyaddress + 1;
                ram.wenable0 = 0;
            }
            case 4: {
                if( copyaddress == 4096 ) {
                    INIT = 3;
                    copyaddress = 0;
                }
            }
            default: {
            }
        }
        CYCLE = ( CYCLE == 4 ) ? 0 : CYCLE + 1;
    }

    // INIT is 3 EXECUTE J1 CPU
    while( INIT == 3 ) {
        // Deal with VBLANK, VGA and SDRAM

        // READ from UART if character available and store
        switch( uartInHold ) {
            case 0: {
                if( uart_rx_valid ) {
                    // writes at uartInBufferTop (code from @sylefeb)
                    uartInBuffer.wdata1  = uart_rx_data;            
                    uartInBufferTop      = uartInBufferTop + 1;
                    uartInHold = 1;
                }
            }
            case 1: {
                // Wait for UART valid flag to flip before allowing another read
                uartInHold = ( uart_rx_valid == 0 ) ? 0 : 1;
            }
        }

        // WRITE to UART if characters in buffer and UART is ready
        switch( uartOutHold ) {
            case 0: {
                if( ~(uartOutBufferNext == uartOutBufferTop) & ~( uart_tx_busy ) ) {
                    // reads at uartOutBufferNext (code from @sylefeb)
                    uart_tx_data      = uartOutBuffer.rdata0; 
                    uart_tx_valid     = 1;
                    uartOutHold = 1;
                    uartOutBufferNext = uartOutBufferNext + 1;
                }
            }
            case 1: {
                if( ~uart_tx_busy ) {
                    uart_tx_valid = 0;
                    uartOutHold = 0;
                }
            }
        }
        uartOutBufferTop = newuartOutBufferTop;        
        
        switch( CYCLE ) {
            // Read stackNext, rStackTop
            case 0: {
                // read dtsack and rstack brams (code from @sylefeb)
                stackNext = dstack.rdata;
                rStackTop = rstack.rdata;
            
                // start READ memoryInput = [stackTop] and instruction = [pc] result ready in 1 cycles
                ram.addr0 = stackTop >> 1;
                ram.wenable0 = 0;
                ram.addr1 = pc;
                ram.wenable1 = 0;
            }
            case 1: {
                // wait then read the data from RAM
                memoryInput = ram.rdata0;
                instruction = ram.rdata1;
            }
            
            // J1 CPU Instruction Execute
            case 2: {
                // +---------------------------------------------------------------+
                // | F | E | D | C | B | A | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
                // +---------------------------------------------------------------+
                // | 1 |                    LITERAL VALUE                          |
                // +---------------------------------------------------------------+
                // | 0 | 0 | 0 |            BRANCH TARGET ADDRESS                  |
                // +---------------------------------------------------------------+
                // | 0 | 0 | 1 |            CONDITIONAL BRANCH TARGET ADDRESS      |
                // +---------------------------------------------------------------+
                // | 0 | 1 | 0 |            CALL TARGET ADDRESS                    |
                // +---------------------------------------------------------------+
                // | 0 | 1 | 1 |R2P| ALU OPERATION |T2N|T2R|N2A|J1P| RSTACK| DSTACK|
                // +---------------------------------------------------------------+
                // | F | E | D | C | B | A | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
                // +---------------------------------------------------------------+
                // 
                // T   : Top of data stack
                // N   : Next on data stack
                // PC  : Program Counter
                // 
                // LITERAL VALUES : push a value onto the data stack
                // CONDITIONAL    : BRANCHS pop and test the T
                // CALLS          : PC+1 onto the return stack
                // 
                // T2N : Move T to N
                // T2R : Move T to top of return stack
                // N2A : STORE T to memory location addressed by N
                // R2P : Move top of return stack to PC
                // 
                // RSTACK and DSTACK are signed values (twos compliment) that are
                // the stack delta (the amount to increment or decrement the stack
                // by for their respective stacks: return and data)

                if(is_lit) {
                    // LITERAL Push value onto stack
                    newStackTop = immediate;
                    newPC = pcPlusOne;
                    newDSP = dsp + 1;
                    newRSP = rsp;
                } else {
                    switch( callbranch(instruction).is_callbranchalu ) { // BRANCH 0BRANCH CALL ALU
                        case 2b00: {
                            // BRANCH
                            newStackTop = stackTop;
                            newPC = callbranch(instruction).address;
                            newDSP = dsp;
                            newRSP = rsp;
                        }
                        case 2b01: {
                            // 0BRANCH
                            newStackTop = stackNext;
                            newPC = ( stackTop == 0 ) ? callbranch(instruction).address : pcPlusOne;
                            newDSP = dsp - 1;
                            newRSP = rsp;
                        }
                        case 2b10: {
                            // CALL
                            newStackTop = stackTop;
                            newPC = callbranch(instruction).address;
                            newDSP = dsp;
                            newRSP = rsp + 1;
                            rstackWData = pcPlusOne << 1;
                        }
                        case 2b11: {
                            // ALU
                            switch( aluop(instruction).is_j1j1plus ) {
                                case 1b0: {
                                    switch( aluop(instruction).operation ) {
                                        case 4b0000: {newStackTop = stackTop;}
                                        case 4b0001: {newStackTop = stackNext;}
                                        case 4b0010: {newStackTop = stackTop + stackNext;}
                                        case 4b0011: {newStackTop = stackTop & stackNext;}
                                        case 4b0100: {newStackTop = stackTop | stackNext;}
                                        case 4b0101: {newStackTop = stackTop ^ stackNext;}
                                        case 4b0110: {newStackTop = ~stackTop;}
                                        case 4b0111: {newStackTop = {16{(stackNext == stackTop)}};}
                                        case 4b1000: {newStackTop = {16{(__signed(stackNext) < __signed(stackTop))}};}
                                        case 4b1001: {newStackTop = stackNext >> nibbles(stackTop).nibble0;}
                                        case 4b1010: {newStackTop = stackTop - 1;}
                                        case 4b1011: {newStackTop = rStackTop;}
                                        case 4b1100: {
                                        // UART or memoryInput
                                            switch( stackTop ) {
                                                case 16hf000: {
                                                    // INPUT from UART reads at uartInBufferNext (code from @sylefeb)
                                                    newStackTop = { 8b0, uartInBuffer.rdata0 };
                                                    uartInBufferNext = uartInBufferNext + 1;
                                                } 
                                                case 16hf001: {
                                                    // UART status register { 14b0, tx full, rx available }
                                                    newStackTop = {14b0, ( uartOutBufferTop + 1 == uartOutBufferNext ), ~( uartInBufferNext == uartInBufferTop )};
                                                }
                                                case 16hf002: {
                                                    // RGB LED status
                                                    newStackTop = led;
                                                }
                                                case 16hf003: {
                                                    // user buttons
                                                    newStackTop = {12b0, buttons};
                                                }
                                                case 16hf004: {
                                                    // 1hz timer
                                                    newStackTop = timer1hz;
                                                }
                                                default: {newStackTop = memoryInput;}
                                            }
                                        }
                                        case 4b1101: {newStackTop = stackNext << nibbles(stackTop).nibble0;}
                                        case 4b1110: {newStackTop = {rsp, dsp};}
                                        case 4b1111: {newStackTop = {16{(__unsigned(stackNext) < __unsigned(stackTop))}};}
                                    }
                                }
                                
                                case 1b1: {
                                    switch( aluop(instruction).operation ) {
                                        case 4b0000: {newStackTop = {16{(stackTop == 0)}};}
                                        case 4b0001: {newStackTop = ~{16{(stackTop == 0)}};}
                                        case 4b0010: {newStackTop = ~{16{(stackNext == stackTop)}};}
                                        case 4b0011: {newStackTop = stackTop + 1;}
                                        case 4b0100: {newStackTop = stackTop << 1;}
                                        case 4b0101: {newStackTop = stackTop >> 1;}
                                        case 4b0110: {newStackTop = {16{(__signed(stackNext) > __signed(stackTop))}};}
                                        case 4b0111: {newStackTop = {16{(__unsigned(stackNext) > __unsigned(stackTop))}};}
                                        case 4b1000: {newStackTop = {16{(__signed(stackTop) < __signed(0))}};}
                                        case 4b1001: {newStackTop = {16{(__signed(stackTop) > __signed(0))}};}
                                        case 4b1010: {newStackTop = ( __signed(stackTop) < __signed(0) ) ?  - stackTop : stackTop;}
                                        case 4b1011: {newStackTop = ( __signed(stackNext) > __signed(stackTop) ) ? stackNext : stackTop;}
                                        case 4b1100: {newStackTop = ( __signed(stackNext) < __signed(stackTop) ) ? stackNext : stackTop;}
                                        case 4b1101: {newStackTop = -stackTop;}
                                        case 4b1110: {newStackTop = stackNext - stackTop;}
                                        case 4b1111: {newStackTop = {16{(__signed(stackNext) >= __signed(stackTop))}};}
                                    }
                                }
                            } // ALU Operation
                            
                            // UPDATE newDSP newRSP
                            newDSP = dsp + ddelta;
                            newRSP = rsp + rdelta;
                            rstackWData = stackTop;

                            // Update PC for next instruction, return from call or next instruction
                            newPC = ( aluop(instruction).is_r2pc ) ? rStackTop >> 1 : pcPlusOne;

                            // n2memt mem[t] = n        
                            if( aluop(instruction).is_n2memt ) {
                                switch( stackTop ) {
                                    default: {
                                        // WRITE to SPRAM
                                        ram.addr0 = stackTop >> 1;
                                        ram.wdata0 = stackNext;
                                        ram.wenable0 = 1;
                                    }
                                    case 16hf000: {
                                        // OUTPUT to UART (dualport blockram code from @sylefeb)
                                        uartOutBuffer.wdata1 = bytes(stackNext).byte0;
                                        newuartOutBufferTop = uartOutBufferTop + 1;
                                    }
                                    case 16hf002: {
                                        // OUTPUT to led
                                        led = stackNext;
                                    }
                                }
                            }
                        } // ALU
                    }
                }
            } // J1 CPU Instruction Execute

            // update pc and perform mem[t] = n
            case 3: {
                // Write to dstack and rstack
                if( dstackWrite ) {
                    // bram code for dstack (code from @sylefeb)
                    dstack.wenable = 1;
                    dstack.addr    = newDSP;
                    dstack.wdata   = stackTop;
                }
                if( rstackWrite ) {
                    // bram code for rstack (code from @sylefeb)
                    rstack.wenable = 1;
                    rstack.addr    = newRSP;
                    rstack.wdata   = rstackWData;
                }
            }
            
            // Update dsp, rsp, pc, stackTop
            case 4: {
                dsp = newDSP;
                pc = newPC;
                stackTop = newStackTop;
                rsp = newRSP;
                
                // Setup addresses for dstack and rstack brams (code from @sylefeb)
                dstack.addr = newDSP;
                rstack.addr = newRSP;
            
                // reset sram_readwrite
                ram.wenable0 = 0;
            }
            
            default: {}
        } // switch(CYCLE)
        
    
        // Move to next CYCLE ( 0 to 12 , then back to 0 )
        CYCLE = ( CYCLE == 4 ) ? 0 : CYCLE + 1;
    } // (INIT==3 execute J1 CPU)

}
