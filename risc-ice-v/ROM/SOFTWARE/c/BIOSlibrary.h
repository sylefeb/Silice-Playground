// STDDEF.H DEFINITIONS
 #define max(a,b) \
   ({ __typeof__ (a) _a = (a); \
       __typeof__ (b) _b = (b); \
     _a > _b ? _a : _b; })

#define min(a,b) \
   ({ __typeof__ (a) _a = (a); \
       __typeof__ (b) _b = (b); \
     _a < _b ? _a : _b; })

typedef unsigned int size_t;

// STRUCTURE OF THE SPRITE UPDATE FLAG
struct sprite_update_flag {
    unsigned int padding:3;
    unsigned int y_act:1;
    unsigned int x_act:1;
    unsigned int tile_act:1;
    int dy:5;
    int dx:5;
};

// RISC-V CSR FUNCTIONS
extern long CSRcycles( void );
extern long CSRinstructions( void );
extern long CSRtime( void );

// STANDARD FUNCTION DEFINITIONS
extern void* memcpy(void *dest, const void *src, size_t n);
extern int strcmp(const char *p1, const char *p2);
extern int strlen( char *s );

// UART AND TERMINAL INPUT / OUTPUT
extern void outputcharacter(char);
extern void outputstring(char *);
extern void outputstringnonl(char *);
extern void outputnumber_char( unsigned char );
extern void outputnumber_short( unsigned short );
extern void outputnumber_int( unsigned int );
extern char inputcharacter( void );
unsigned char inputcharacter_available( void );

// BASIC I/O
extern void set_leds( unsigned char );

// TIMERS AND PSEUDO RANDOM NUMBER GENERATOR
extern void sleep( unsigned short );

// SDCARD
extern void sdcard_readsector( unsigned int, unsigned char * );

// BACKGROUND GENERATOR
extern void set_background( unsigned char, unsigned char, unsigned char );

// TERMINAL WINDOW
extern void terminal_showhide( unsigned char );

// GPU AND BITMAP
extern void gpu_pixel( unsigned char, short, short );
extern void gpu_rectangle( unsigned char, short, short, short, short );
extern void gpu_cs( void );
extern void gpu_line( unsigned char, short, short, short, short );
extern void gpu_circle( unsigned char, short, short, short, unsigned char );
extern void gpu_blit( unsigned char, short, short, short, unsigned char );
extern void gpu_character_blit( unsigned char, short, short, unsigned char, unsigned char );
extern void gpu_triangle( unsigned char, short, short, short, short, short, short );
extern void bitmap_scrollwrap( unsigned char );
extern void set_blitter_bitmap( unsigned char, unsigned short * );

// CHARACTER MAP
extern void tpu_cs( void );
extern void tpu_clearline( unsigned char );
extern void tpu_set(  unsigned char, unsigned char, unsigned char, unsigned char );
extern void tpu_output_character( char );
extern void tpu_outputstring( char * );
extern void tpu_outputstringcentre( unsigned char, unsigned char, unsigned char, char * );
extern void tpu_outputnumber_char( unsigned char );
extern void tpu_outputnumber_short( unsigned short );
extern void tpu_outputnumber_int( unsigned int );

// BACKGROUND PATTERN GENERATOR
#define BKG_SOLID 0
#define BKG_5050_V 1
#define BKG_5050_H 2
#define BKG_CHKBRD_5 3
#define BKG_RAINBOW 4
#define BKG_SNOW 5
#define BKG_STATIC 6
#define BKG_CHKBRD_1 7
#define BKG_CHKBRD_2 8
#define BKG_CHKBRD_3 9
#define BKG_CHKBRD_4 10

// COLOURS
#define TRANSPARENT 0x40
#define BLACK 0x00
#define BLUE 0x03
#define DKBLUE 0x02
#define GREEN 0x0c
#define DKGREEN 0x08
#define CYAN 0x0f
#define RED 0x30
#define DKRED 0x20
#define MAGENTA 0x33
#define PURPLE 0x13
#define YELLOW 0x3c
#define WHITE 0x3f
#define GREY1 0x15
#define GREY2 0x2a
#define ORANGE 0x38
