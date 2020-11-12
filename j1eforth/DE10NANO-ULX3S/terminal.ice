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
    output  uint1   terminal_active
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
    uint7 xterminalpos := ( pix_active ? pix_x + 2 : 0 ) >> 3;
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
    uint10 terminal_scroll_character = 0;

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

    // Render the terminal
    while(1) {
        if( terminal_write ) {
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
        } else {
            if( terminal_active ) {
                // SCROLL
                terminal_scroll = 0;
                ++:
                while( terminal_scroll < 560 ) {
                    // Retrieve character on the next line
                    terminal.addr1 = terminal_scroll + 80;
                    ++:
                    terminal_scroll_character = terminal.rdata1;
                    ++:
                    // Write retrieved character
                    terminal.addr1 = terminal_scroll;
                    terminal.wdata1 = terminal_scroll_character;
                    terminal.wenable1 = 1;

                    //++:
                    terminal_scroll = terminal_scroll + 1;
                }

                // BLANK LAST LINE
                while( terminal_scroll < 640 ) {
                    terminal.addr1 = terminal_scroll;
                    terminal.wdata1 = 0;
                    terminal.wenable1 = 1;

                    terminal_scroll = terminal_scroll + 1;
                }

                terminal_active = 0;
            }
        }
    }
}
