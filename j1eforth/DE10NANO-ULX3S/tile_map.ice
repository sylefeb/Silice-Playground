// Entry in the tilemap
bitfield tilemapentry {
    uint1   alpha,
    uint6   background,
    uint6   foreground,
    uint5   tilenumber
}

algorithm tilemap(
    input   uint10  pix_x,
    input   uint10  pix_y,
    input   uint1   pix_active,
    input   uint1   pix_vblank,
    output! uint2   pix_red,
    output! uint2   pix_green,
    output! uint2   pix_blue,
    output! uint1   tilemap_display,

    // Set TM at x, y, character with foreground and background
    input uint6 tm_x,
    input uint6 tm_y,
    input uint5 tm_character,
    input uint6 tm_foreground,
    input uint7 tm_background,
    input uint1 tm_write,

    // For setting tile bitmaps
    input   uint5   tile_writer_tile,
    input   uint4   tile_writer_line,
    input   uint16  tile_writer_bitmap,

    // For scrolling/wrapping
    input   uint4   tm_scrollwrap,
    output  uint4   tm_lastaction,
    output  uint2   tm_active
) <autorun> {
    // Tile Map 32 x 16 x 16
    simple_dualport_bram uint16 tiles16x16 <input!> [ 512 ] = { 0, pad(0) };

    // 42 x 32 tile map, allows for pixel scrolling with border { 7 bits background, 6 bits foreground, 5 bits tile number }
    // Setting background to 40 (ALPHA) allows the bitmap/background to show through
    simple_dualport_bram uint18 tiles[1344] = { 18h20000, pad(18h20000) };

    // Scroll position - -15 to 0 to 15
    // -15 or 15 will trigger appropriate scroll when next moved in that direction
    int5    tm_offset_x = uninitialized;
    int5    tm_offset_y = uninitialized;
    tile_map_writer TMW(
        tiles <:> tiles,
        tm_x <: tm_x,
        tm_y <: tm_y,
        tm_character <: tm_character,
        tm_foreground <: tm_foreground,
        tm_background <: tm_background,
        tm_write <: tm_write,
        tm_offset_x :> tm_offset_x,
        tm_offset_y :> tm_offset_y,
        tm_scrollwrap <: tm_scrollwrap,
        tm_lastaction :> tm_lastaction,
        tm_active :> tm_active
    );

    tilebitmapwriter TBMW(
        tile_writer_tile <: tile_writer_tile,
        tile_writer_line <: tile_writer_line,
        tile_writer_bitmap <: tile_writer_bitmap,
        tiles16x16 <:> tiles16x16
    );

    // Character position on the screen x 0-41, y 0-31 * 42 ( fetch it two pixels ahead of the actual x pixel, so it is always ready )
    // Adjust for the offsets, effective 0 point margin is ( 1,1 ) to ( 40,30 ) with a 1 tile border
    uint11  xtmpos :=  ( pix_active ? pix_x + ( 11d18 + {{6{tm_offset_x[4,1]}}, tm_offset_x} ) : ( 11d16 + {{6{tm_offset_x[4,1]}}, tm_offset_x} ) ) >> 4;
    uint11  ytmpos := (( pix_vblank ? ( 11d16 + {{6{tm_offset_y[4,1]}}, tm_offset_y} ) : pix_y + ( 11d16 + {{6{tm_offset_y[4,1]}}, tm_offset_y} ) ) >> 4) * 42;

    // Derive the x and y coordinate within the current 16x16 tilemap block x 0-7, y 0-15
    // Needs adjusting for the offsets
    uint4   xintm := { 1b0, pix_x[0,4] } + tm_offset_x;
    uint4   yintm := { 1b0, pix_y[0,4] } + tm_offset_y;

    // Derive the actual pixel in the current character
    uint1   tmpixel := tiles16x16.rdata0[15 - xintm,1];

    // Set up reading of the tilemap
    tiles.addr0 := xtmpos + ytmpos;

    // Setup the reading and writing of the tiles16x16
    tiles16x16.addr0 :=  { tilemapentry(tiles.rdata0).tilenumber, yintm };

    // RENDER - Default to transparent
    tilemap_display := pix_active && ( ( tmpixel ) || ( ~tilemapentry(tiles.rdata0).alpha ) );
    pix_red := tmpixel ? tiles.rdata0[9,2] : tiles.rdata0[15,2];
    pix_green := tmpixel ? tiles.rdata0[7,2] : tiles.rdata0[13,2];
    pix_blue := tmpixel ?  tiles.rdata0[5,2] : tiles.rdata0[11,2];

    while(1) {
    }
}

algorithm tile_map_writer(
    simple_dualport_bram_port1 tiles,

    // Set TM at x, y, character with foreground and background
    input uint6 tm_x,
    input uint6 tm_y,
    input uint5 tm_character,
    input uint6 tm_foreground,
    input uint7 tm_background,
    input uint1 tm_write,

    // For scrolling/wrapping
    output  int5    tm_offset_x,
    output  int5    tm_offset_y,

    input   uint4   tm_scrollwrap,
    output  uint4   tm_lastaction,
    output  uint2   tm_active
) <autorun> {
    // COPY OF TILEMAP FOR SCROLLING
    simple_dualport_bram uint18 tiles_copy[1344] = { 18h20000, pad(18h20000) };

    // Scroller/Wrapper storage
    uint1   tm_scroll = uninitialized;
    uint1   tm_goleft = uninitialized;
    uint1   tm_goup = uninitialized;
    uint6   x_cursor = uninitialized;
    uint6   y_cursor = uninitialized;
    uint11  y_cursor_addr = uninitialized;
    uint18  new_tile = uninitialized;

    // CLEARSCROLL address
    uint11  tmcsaddr = uninitialized;

    // TILEMAP WRITE FLAGS
    tiles.wenable1 := 1;
    tiles_copy.wenable1 := 1;

    // Default to 0,0 and transparent
    tiles.addr1 = 0; tiles.wdata1 = 18h20000;
    tiles_copy.addr1 = 0; tiles_copy.wdata1 = 18h20000;

    tm_offset_x = 0;
    tm_offset_y = 0;

    while(1) {
        // Write character to the tilemap
        if( tm_write == 1 ) {
            tiles.addr1 = tm_x + tm_y * 42;
            tiles.wdata1 = { tm_background, tm_foreground, tm_character };
            tiles_copy.addr1 = tm_x + tm_y * 42;
            tiles_copy.wdata1 = { tm_background, tm_foreground, tm_character };
        }

        switch( tm_active ) {
            case 0: {
                // Perform Scrolling/Wrapping
                switch( tm_scrollwrap ) {
                    // NO ACTION
                    case 0: {
                    }
                    // CLEAR
                    case 9: {
                        tm_active = 3;
                        tm_lastaction = 9;
                    }

                    // SCROLL / WRAP
                    default: {
                        switch( ( tm_scrollwrap - 1 ) & 3  ) {
                            case 0: {
                                if( tm_offset_x == 15 ) {
                                    tm_scroll = ( tm_scrollwrap == 1 ) ? 1 : 0;
                                    tm_lastaction = tm_scrollwrap;
                                    tm_goleft = 1;
                                    tm_active = 1;
                                } else {
                                    tm_offset_x = tm_offset_x + 1;
                                    tm_lastaction = 0;
                                }
                            }
                            // UP
                            case 1: {
                                if( tm_offset_y == 15 ) {
                                    tm_scroll = ( tm_scrollwrap == 2 ) ? 1 : 0;
                                    tm_lastaction = tm_scrollwrap;
                                    tm_goup = 1;
                                    tm_active = 2;
                                } else {
                                    tm_offset_y = tm_offset_y + 1;
                                    tm_lastaction = 0;
                                }
                            }
                            // RIGHT
                            case 2: {
                                if( tm_offset_x == -15 ) {
                                    tm_scroll = ( tm_scrollwrap == 3 ) ? 1 : 0;
                                    tm_lastaction = tm_scrollwrap;
                                    tm_goleft = 0;
                                    tm_active = 1;
                                } else {
                                    tm_offset_x = tm_offset_x - 1;
                                    tm_lastaction = 0;
                                }
                            }
                            // DOWN
                            case 3: {
                                if( tm_offset_y == -15 ) {
                                    tm_scroll = ( tm_scrollwrap == 4 ) ? 1 : 0;
                                    tm_lastaction = tm_scrollwrap;
                                    tm_goup = 0;
                                    tm_active = 2;
                                } else {
                                    tm_offset_y = tm_offset_y - 1;
                                    tm_lastaction = 0;
                                }
                            }
                        }
                    }
                }
            }

            // SCROLL/WRAP LEFT/RIGHT
            case 1: {
                y_cursor = 0;
                y_cursor_addr = 0;
                ++:
                while( y_cursor < 32 ) {
                    x_cursor = tm_goleft ? 0 : 41;
                    tiles_copy.addr0 = y_cursor_addr + ( tm_goleft ? 0 : 41 );
                    ++:
                    new_tile = tm_scroll ? 18h20000 : tiles_copy.rdata0;
                    ++:
                    while( tm_goleft ? ( x_cursor < 42 ) : ( x_cursor > 0 ) ) {
                        tiles_copy.addr0 = y_cursor_addr + x_cursor + ( tm_goleft ? 1 : (-1) );
                        ++:
                        tiles.addr1 = x_cursor + y_cursor_addr;
                        tiles.wdata1 = tiles_copy.rdata0;
                        tiles_copy.addr1 = x_cursor + y_cursor_addr;
                        tiles_copy.wdata1 = tiles_copy.rdata0;
                        x_cursor = x_cursor + ( tm_goleft ? 1 : (-1) );
                    }
                    ++:
                    tiles.addr1 = y_cursor_addr + ( tm_goleft ? 41 : 0 );
                    tiles.wdata1 = new_tile;
                    tiles_copy.addr1 = y_cursor_addr + ( tm_goleft ? 41 : 0 );
                    tiles_copy.wdata1 = new_tile;
                    y_cursor = y_cursor + 1;
                    y_cursor_addr = y_cursor_addr + 42;
                }
                tm_offset_x = 0;
                tm_active = 0;
            }

            // SCROLL/WRAP UP/DOWN
            case 2: {
                x_cursor = 0;
                ++:
                while( x_cursor < 42 ) {
                    y_cursor = tm_goup ? 0 : 31;
                    y_cursor_addr = tm_goup ? 0 : 1302;
                    tiles_copy.addr0 = x_cursor;
                    ++:
                    new_tile = tm_scroll ? 18h20000 : tiles_copy.rdata0;
                    ++:
                    while( tm_goup ? ( y_cursor < 31 ) : ( y_cursor > 0 ) ) {
                        tiles_copy.addr0 = x_cursor + y_cursor_addr + ( tm_goup ? 42 : (-42) );
                        ++:
                        tiles.addr1 = x_cursor + y_cursor_addr;
                        tiles.wdata1 = tiles_copy.rdata0;
                        tiles_copy.addr1 = x_cursor + y_cursor_addr;
                        tiles_copy.wdata1 = tiles_copy.rdata0;
                        y_cursor = y_cursor + ( tm_goup ? 1 : (-1) );
                        y_cursor_addr = y_cursor_addr + ( tm_goup ? 42 : (-42) );
                    }
                    tiles.addr1 = x_cursor + ( tm_goup ? 1302 : 0 );
                    tiles.wdata1 = new_tile;
                    tiles_copy.addr1 = x_cursor + ( tm_goup ? 1302 : 0 );
                    tiles_copy.wdata1 = new_tile;
                    x_cursor = x_cursor + 1;
                }
                tm_offset_y = 0;
                tm_active = 0;
            }

            // CLEAR
            case 3: {
                tmcsaddr = 0;
                ++:
                while( tmcsaddr < 1344 ) {
                    tiles.addr1 = tmcsaddr;
                    tiles.wdata1 = 18h20000;
                    tiles_copy.addr1 = tmcsaddr;
                    tiles_copy.wdata1 = 18h20000;
                    tmcsaddr = tmcsaddr + 1;
                }

                tm_offset_x = 0;
                tm_offset_y = 0;
                tm_active = 0;
            }
        }
    }
}

algorithm tilebitmapwriter(
    input   uint5   tile_writer_tile,
    input   uint4   tile_writer_line,
    input   uint16  tile_writer_bitmap,

    simple_dualport_bram_port1 tiles16x16
) <autorun> {
    tiles16x16.wenable1 := 1;

    while(1) {
        tiles16x16.addr1 = { tile_writer_tile, tile_writer_line };
        tiles16x16.wdata1 = tile_writer_bitmap;
    }
}
