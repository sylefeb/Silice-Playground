algorithm terminal(
    input   uint10  pix_x,
    input   uint10  pix_y,
    input   uint1   pix_active,
    input   uint1   pix_vblank,
    output! uint2   pix_red,
    output! uint2   pix_green,
    output! uint2   pix_blue,
    output! uint1   terminal_display,
    
    input   uint8   terminal_character,
    input   uint1   terminal_write,
    input   uint1   showterminal,
    input   uint1   showcursor,
    input   uint1   timer1hz,
    output  uint3    terminal_active
) <autorun> {
    // Character ROM 8x8 x 256
    brom uint8 characterGenerator8x8[] = {
        $include('ROM/characterROM8x8.inc')
    };
    
    // 80 x 4 character buffer for the input/output terminal
    dualport_bram uint8 terminal[640] = uninitialized;

    // Initial cursor position in the terminal, bottom left
    uint7 terminal_x = 0;
    uint3 terminal_y = 7;
    
    // Character position on the terminal x 0-79, y 0-7 * 80 ( fetch it one pixel ahead of the actual x pixel, so it is always ready )
    uint7 xterminalpos := ( pix_active ? (pix_x < 640 ) ? pix_x + 2 : 0 : 0 ) >> 3;
    uint10 yterminalpos := (( pix_vblank ? 0 : pix_y - 416 ) >> 3) * 80;

    // Determine if cursor, and if cursor is flashing
    uint1 is_cursor := ( xterminalpos == terminal_x ) && ( ( ( pix_y - 416) >> 3 ) == terminal_y );
    
    // Derive the x and y coordinate within the current 8x8 terminal character block x 0-7, y 0-7
    uint3 xinterminal := (pix_x) & 7;
    uint3 yinterminal := (pix_y) & 7;

    // Derive the actual pixel in the current terminal
    uint1 terminalpixel := characterGenerator8x8.rdata[7 - xinterminal,1];
    
    // Terminal active (scroll) flag and temporary storage for scrolling
    uint10 terminal_scroll = 0;
    uint10 terminal_scroll_next = 0;

    // Setup the reading of the terminal memory
    terminal.addr0 := xterminalpos + yterminalpos;
    terminal.wenable0 := 0;

    // Setup the writing to the terminal memory
    terminal.wenable1 := 0;

    // Setup the reading of the characterGenerator8x8 ROM
    characterGenerator8x8.addr :=  terminal.rdata0 * 8 + yinterminal;
    
    // Default to transparent and active pixels always blue
    terminal_display := pix_active && showterminal && (pix_y > 415);
    pix_blue := 3;

    always {
        // TERMINAL Actions
        // Write to terminal, move to next character and scroll
         switch( terminal_active ) {
             case 0: {
                switch( terminal_write ) {
                    case 1: {
                        // Display character
                        switch( terminal_character ) {
                            case 8: {
                                // BACKSPACE, move back one character
                                if( terminal_x != 0 ) {
                                    terminal_x = terminal_x - 1;
                                    terminal.addr1 = terminal_x + terminal_y * 80;
                                    terminal.wdata1 = 0;
                                    terminal.wenable1 = 1;
                                }
                            }
                            case 10: {
                                // LINE FEED, scroll
                                terminal_scroll = 0;
                                terminal_active = 1;
                            }
                            case 13: {
                                // CARRIAGE RETURN
                                terminal_x = 0;
                            }
                            default: {
                                // Display character
                                terminal.addr1 = terminal_x + terminal_y * 80;
                                terminal.wdata1 = terminal_character;
                                terminal.wenable1 = 1;
                                terminal_active = ( terminal_x == 79 ) ? 1 : 0;
                                terminal_x = ( terminal_x == 79 ) ? 0 : terminal_x + 1;
                            }
                        }
                    }
                    default: {}
                }
            }
            // Start of TERMINAL SCROLL
            case 1: {
                // SCROLL
                terminal_active = ( terminal_scroll == 560 ) ? 4 : 2;
                terminal.addr1 = terminal_scroll + 80;
            }
            case 2: {
                // Retrieve the character to move up
                terminal_scroll_next = terminal.rdata1;
                terminal_active = 3;
            }
            case 3: {
                // Write the character one line up and move onto the next character
                terminal.addr1 = terminal_scroll;
                terminal.wdata1 = terminal_scroll_next;
                terminal.wenable1 = 1;
                terminal_scroll = terminal_scroll + 1;
                terminal_active = 1;
            }
            case 4: {
                // Blank out the last line
                terminal.addr1 = terminal_scroll;
                terminal.wdata1 = 0;
                terminal.wenable1 = 1;
                terminal_active = ( terminal_scroll == 640 ) ? 0 : 4;
                terminal_scroll = terminal_scroll + 1;
            }
            default: {
                terminal_scroll = 0;
                terminal_active = 0;
            }
        } // TERMINAL        
    }
    
    // Render the terminal
    while(1) {
        if( terminal_display ) {
            // TERMINAL is in range and showterminal flag
            // Invert colours for cursor if flashing
            switch( terminalpixel ) {
                case 0: {
                    pix_red = ( is_cursor && timer1hz ) ? 3 : 0;
                    pix_green = ( is_cursor && timer1hz ) ? 3: 0;
                }
                case 1: {
                    pix_red = ( is_cursor && timer1hz ) ? 0 : 3;
                    pix_green = ( is_cursor && timer1hz ) ? 0 : 3;
                }
            }
        }
    }
}
