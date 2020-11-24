bitfield spriteupdate {
    uint1   colour_act,         // 1 change the colour
    uint6   colour,             // { rrggbb }
    uint1   y_act,              // 1 - kill when off screen, 0 - wrap
    uint1   x_act,              // 1 - kill when off screen, 0 - wrap
    uint1   tile_act,           // 1 - increase the tile number
    uint1   dysign,             // dy - 2's complement update for the y coordinate
    uint2   dy,
    uint1   dxsign,             // dx - 2's complement update for the x coordinate
    uint2   dx
}

algorithm sprite_layer(
    input   uint10  pix_x,
    input   uint10  pix_y,
    input   uint1   pix_active,
    input   uint1   pix_vblank,
    output! uint2   pix_red,
    output! uint2   pix_green,
    output! uint2   pix_blue,
    output! uint1   sprite_layer_display,

    // For setting sprite characteristics
    input   uint4   sprite_set_number,
    input   uint1   sprite_set_active,
    input   uint1   sprite_set_double,
    input   uint6   sprite_set_colour,
    input   int11   sprite_set_x,
    input   int11   sprite_set_y,
    input   uint3   sprite_set_tile,
    // Flag to set the above
    input   uint4   sprite_layer_write,

    // For reading sprite characteristics for sprite_set_number
    output uint1   sprite_read_active,
    output uint1   sprite_read_double,
    output uint6   sprite_read_colour,
    output int11   sprite_read_x,
    output int11   sprite_read_y,
    output uint3   sprite_read_tile,

    input   uint16  sprite_update,

    // FULL collision detection
    // (1) Bitmap, (2) Tile Map, (3) Other Sprite Layer
    input   uint1   collision_layer_1,
    input   uint1   collision_layer_2,
    input   uint1   collision_layer_3,
    $$for i=0,12 do
        output uint16 collision_$i$,
    $$end

    // For setting sprite tile bitmaps
    input   uint4   sprite_writer_sprite,
    input   uint7   sprite_writer_line,
    input   uint16  sprite_writer_bitmap,
    input   uint1   sprite_writer_active

) <autorun> {
    // Storage for the sprites
    // Stored as registers as needed instantly
    uint1 sprite_active[13] = uninitialised;
    uint1 sprite_double[13] = uninitialised;
    int11 sprite_x[13] = uninitialised;
    int11 sprite_y[13] = uninitialised;
    uint6 sprite_colour[13] = uninitialised;
    uint3 sprite_tile_number[13] = uninitialised;

    $$for i=0,12 do
        // Sprite Tiles
        dualport_bram uint16 tiles_$i$[128] = uninitialised;

        // Calculate if sprite is visible
        uint6 spritesize_$i$ := sprite_double[$i$] ? 32 : 16;
        uint4 xinsprite_$i$ := 15  - ( ( pix_x - sprite_x[$i$] ) >> sprite_double[$i$] );
        uint4 yinsprite_$i$ := ( pix_y - sprite_y[$i$] ) >> sprite_double[$i$];
        uint1 xinrange_$i$ := ( pix_x >= sprite_x[$i$] ) && ( pix_x < ( sprite_x[$i$] + spritesize_$i$ ) );
        uint1 yinrange_$i$ := ( pix_y >= sprite_y[$i$] ) && ( pix_y < ( sprite_y[$i$] + spritesize_$i$ ) );
        uint1 pix_visible_$i$ := sprite_active[$i$] && xinrange_$i$ && yinrange_$i$ && ( tiles_$i$.rdata0[ xinsprite_$i$, 1 ] == 1 );

        // Collision detection flag
        uint16      detect_collision_$i$ = uninitialised;
    $$end

    // Expand Sprite Update Deltas
    int11   deltax := { {9{spriteupdate( sprite_update ).dxsign}}, spriteupdate( sprite_update ).dx };
    int11   deltay := { {9{spriteupdate( sprite_update ).dysign}}, spriteupdate( sprite_update ).dy };

    // Set read and write address for the tiles
    $$for i=0,12 do
        tiles_$i$.addr0 := sprite_tile_number[$i$] * 16 + yinsprite_$i$;
        tiles_$i$.wenable0 := 0;
        tiles_$i$.wenable1 := 1;
    $$end

    // Default to transparent
    sprite_layer_display := 0;

    // Sprite details reader
    sprite_read_active := sprite_active[ sprite_set_number ];
    sprite_read_double := sprite_double[ sprite_set_number ];
    sprite_read_colour := sprite_colour[ sprite_set_number ];
    sprite_read_x := sprite_x[ sprite_set_number ];
    sprite_read_y := sprite_y[ sprite_set_number ];
    sprite_read_tile := sprite_tile_number[ sprite_set_number ];

    // Write to the sprite_layer
    // Set tile bitmaps, x coordinate, y coordinate, colour, tile number, visibility, double
    always {
        // WRITE BITMAP TO SPRITE TILE
        if( sprite_writer_active ) {
            switch( sprite_writer_sprite ) {
                $$for i=0,12 do
                    case $i$: {
                        tiles_$i$.addr1 = sprite_writer_line;
                        tiles_$i$.wdata1 = sprite_writer_bitmap;
                    }
                $$end
            }
        }

        switch( sprite_layer_write ) {
            case 1: { sprite_active[ sprite_set_number ] = sprite_set_active; }
            case 2: { sprite_tile_number[ sprite_set_number ] = sprite_set_tile; }
            case 3: { sprite_colour[ sprite_set_number ] = sprite_set_colour; }
            case 4: { sprite_x[ sprite_set_number ] = sprite_set_x; }
            case 5: { sprite_y[ sprite_set_number ] = sprite_set_y; }
            case 6: { sprite_double[ sprite_set_number ] = sprite_set_double; }
            case 10: {
                // Perform sprite update
                sprite_colour[ sprite_set_number ] = ( spriteupdate( sprite_update ).colour_act ) ? spriteupdate( sprite_update ).colour : sprite_colour[ sprite_set_number ];
                sprite_tile_number[ sprite_set_number ] = ( spriteupdate( sprite_update ).tile_act ) ? sprite_tile_number[ sprite_set_number ] + 1 : sprite_tile_number[ sprite_set_number ];

                sprite_x[ sprite_set_number ] = (__signed( sprite_x[ sprite_set_number ] ) < __signed(-16)) ? 640 :
                                                ( (__signed( sprite_x[ sprite_set_number ] ) > __signed(640)) ? -15 : sprite_x[ sprite_set_number ] + deltax );
                sprite_y[ sprite_set_number ] = (__signed( sprite_y[ sprite_set_number ] ) < __signed(-16)) ? 480 :
                                                ( (__signed( sprite_y[ sprite_set_number ] ) > __signed(480)) ? -15 : sprite_y[ sprite_set_number ] + deltay );

                sprite_active[ sprite_set_number ] = ( ( ( (__signed( sprite_x[ sprite_set_number ] ) < __signed(-16)) ||
                                                        (__signed( sprite_x[ sprite_set_number ] ) > __signed(640)) ) && ( spriteupdate( sprite_update ).x_act ) ) ||
                                                        ( ( (__signed( sprite_y[ sprite_set_number ] ) < __signed(-16)) ||
                                                        (__signed( sprite_y[ sprite_set_number ] ) > __signed(480)) ) && spriteupdate( sprite_update ).y_act ) ) ?
                                                        0 : sprite_active[ sprite_set_number ];
            }
        }
    }

    // Render the sprite layer
    while(1) {

        if( pix_vblank ) {
            // RESET collision detection
            $$for i=0,12 do
                detect_collision_$i$ = 0;
            $$end
        } else {
            if( pix_active ) {
                $$for i=0,12 do
                    if(  ( pix_visible_$i$ ) ) {
                        pix_red = sprite_colour[$i$][4,2];
                        pix_green = sprite_colour[$i$][2,2];
                        pix_blue = sprite_colour[$i$][0,2];

                        sprite_layer_display = 1;

                        // Perform collision detection
                        detect_collision_$i$ = detect_collision_$i$ | {
                            collision_layer_1, collision_layer_2, collision_layer_3, pix_visible_12, pix_visible_11,
                            pix_visible_10, pix_visible_9, pix_visible_8, pix_visible_7,
                            pix_visible_6, pix_visible_5, pix_visible_4, pix_visible_3,
                            pix_visible_2, pix_visible_1, pix_visible_0
                        };
                    }
                $$end
            }
        }

        // Output collision detection
        if( ( pix_x == 639 ) && ( pix_y == 479 ) ) {
            $$for i=0,12 do
                collision_$i$ = detect_collision_$i$;
            $$end
        }
    }
}