algorithm fpu(
    input   uint1   start,
    output  uint1   busy,

    input   uint7   opCode,
    input   uint3   function3,
    input   uint7   function7,
    input   uint5   rs1,
    input   uint5   rs2,
    input   uint32  sourceReg1,
    input   uint32  sourceReg1F,
    input   uint32  sourceReg2F,
    input   uint32  sourceReg3F,

    output uint32  result,
    output uint1   frd
) <autorun> {
    uint2   FSM = uninitialised;

    inttofloat FPUfloat( a <: sourceReg1, rs2 <: rs2 );
    floattoint FPUint( sourceReg1F <: sourceReg1F );
    floattouint FPUuint( sourceReg1F <: sourceReg1F );
    floataddsub FPUaddsub();
    floatmultiply FPUmultiply( b <: sourceReg2F );
    floatdivide FPUdivide();
    floatsqrt FPUsqrt( sourceReg1F <: sourceReg1F );
    floatclassify FPUclass( sourceReg1F <: sourceReg1F );
    floatcomparison FPUcomparison( function3 <: function3, sourceReg1F <: sourceReg1F, sourceReg2F <: sourceReg2F );
    floatsign FPUsign( function3 <: function3, sourceReg1F <: sourceReg1F, sourceReg2F <: sourceReg2F );

    FPUfloat.start := 0;
    FPUint.start := 0;
    FPUuint.start := 0;
    FPUaddsub.start := 0;
    FPUmultiply.start := 0;
    FPUdivide.start := 0;
    FPUsqrt.start := 0;

    busy = 0;

    while(1) {
        if( start ) {
            busy = 1;
            frd = 1;

            switch( opCode[2,5] ) {
                default: {
                    // FMADD.S FMSUB.S FNMSUB.S FNMADD.S
                    FSM = 1;
                    while( FSM != 0 ) {
                        onehot( FSM ) {
                            case 0: {
                                FPUmultiply.a = opCode[3,1] ? { ~sourceReg1F[31,1], sourceReg1F[0,31] } : sourceReg1F;
                                FPUmultiply.start = 1; while( FPUmultiply.busy ) {}
                            }
                            case 1: {
                                FPUaddsub.a = FPUmultiply.result; FPUaddsub.b = sourceReg3F;
                                FPUaddsub.addsub = ( opCode[2,1] != opCode[3,1] );
                                FPUaddsub.start = 1; while( FPUaddsub.busy ) {}
                            }
                        }
                        FSM = { FSM[0,1], 1b0 };
                    }
                    result = FPUaddsub.result;
                }
                case 5b10100: {
                    // NON 3 REGISTER FPU OPERATIONS
                    switch( function7[2,5] ) {
                        default: {
                            // FADD.S FSUB.S
                            FPUaddsub.a = sourceReg1F; FPUaddsub.b = sourceReg2F; FPUaddsub.addsub = function7[2,1];
                            FPUaddsub.start = 1; while( FPUaddsub.busy ) {}
                            result = FPUaddsub.result;
                        }
                        case 5b00010: {
                            // FMUL.S
                            FPUmultiply.a = sourceReg1F;
                            FPUmultiply.start = 1; while( FPUmultiply.busy ) {}
                            result = FPUmultiply.result;
                        }
                        case 5b00011: {
                            // FDIV.S
                            FPUdivide.a = sourceReg1F; FPUdivide.b = sourceReg2F;
                            FPUdivide.start = 1; while( FPUdivide.busy ) {}
                            result = FPUdivide.result;
                        }
                        case 5b01011: {
                            // FSQRT.S
                            FPUsqrt.start = 1; while( FPUsqrt.busy ) {}
                            result = FPUsqrt.result;
                        }
                        case 5b00100: {
                            // FSGNJ.S FNGNJN.S FSGNJX.S
                            result = FPUsign.result;
                        }
                        case 5b00101: {
                            // FMIN.S FMAX.S
                            switch( function3[0,1] ) {
                                case 0: { result = FPUcomparison.comparison ? sourceReg1F : sourceReg2F; }
                                case 1: { result = FPUcomparison.comparison ? sourceReg2F : sourceReg1F; }
                            }
                        }
                        case 5b11000: {
                            // FCVT.W.S FCVT.WU.S
                            frd = 0;
                            FPUint.start = ~rs2[0,1]; FPUuint.start = rs2[0,1]; while( FPUint.busy || FPUuint.busy ) {}
                            result = rs2[0,1] ? FPUuint.result : FPUint.result;
                        }
                        case 5b10100: {
                            // FEQ.S FLT.S FLE.S
                            frd = 0;
                            result = { 31b0, FPUcomparison.comparison };
                        }
                        case 5b11100: {
                            // FCLASS.S  FMV.X.W
                            frd = 0;
                            result = function3[0,1] ? FPUclass.classification : sourceReg1F;
                        }
                        case 5b11010: {
                            // FCVT.S.W FCVT.S.WU
                            FPUfloat.start = 1; while( FPUfloat.busy ) {}
                            result = FPUfloat.result;
                        }
                        case 5b11110: {
                            // FMV.W.X
                            result = sourceReg1;
                        }
                    }
                }
            }

            busy = 0;
        }
    }
}

// COUNT LEADING 0s
circuitry countleadingzeros( input a, output count ) {
    uint2   CYCLE = uninitialised;

    CYCLE = 1;
    while( CYCLE != 0 ) {
        onehot( CYCLE ) {
            case 0: {
                count = 0;
            }
            case 1: {
                switch( a ) {
                    case 0: { count = 32; }
                    default: {
                        while( ~a[31-count,1] ) {
                            count = count + 1;
                        }
                    }
                }
            }
        }
        CYCLE = { CYCLE[0,1], 1b0 };
    }
}

// CLASSIFY EXPONENT AND FRACTION
circuitry class( output E, output F, input N ) {
    E = { ( floatingpointnumber(N).exponent ) == 8hff, ( floatingpointnumber(N).exponent ) == 8h00 };
    F = ( floatingpointnumber(N).fraction ) == 23h0000;
}

// CONVERT SIGNED/UNSIGNED INTEGERS TO FLOAT
algorithm inttofloat(
    input   uint1   start,
    output  uint1   busy,

    input   uint32  a,
    input   uint5   rs2,

    output  uint32  result
) <autorun> {
    uint2   FSM = uninitialised;
    uint1   sign = uninitialised;
    uint8   exp = uninitialised;
    uint8   zeros = uninitialised;
    uint32  number = uninitialised;

    busy = 0;

    while(1) {
        if( start ) {
            busy = 1;
            FSM = 1;
            while( FSM != 0 ) {
                onehot( FSM ) {
                    case 0: {
                        // SIGNED / UNSIGNED
                        sign = rs2[0,1] ? 0 : a[31,1];
                        number = rs2[0,1] ? a : ( a[31,1] ? -a : a );
                    }
                    case 1: {
                        switch( number ) {
                            case 0: { result = { sign, 31b0 }; }
                            default: {
                                ( zeros ) = countleadingzeros( number );
                                number = ( zeros < 8 ) ? number >> ( 8 - zeros ) : ( zeros > 8 ) ? number << ( zeros - 8 ) : number;
                                exp = 158 - zeros;
                                result = { sign, exp[0,8], number[0,23] };
                            }
                        }
                    }
                }
                FSM = { FSM[0,1], 1b0 };
            }
            busy = 0;
        }
    }
}

algorithm floataddsub(
    input   uint1   start,
    output  uint1   busy,

    input   uint32  a,
    input   uint32  b,
    input   uint1   addsub,

    output  uint32  result
) <autorun> {
    uint4   FSM = uninitialised;
    uint2   classEa = uninitialised;
    uint1   classFa = uninitialised;
    uint2   classEb = uninitialised;
    uint1   classFb = uninitialised;
    uint1   sign = uninitialised;
    uint8   expA = uninitialised;
    uint8   expB = uninitialised;
    uint32  sigA = uninitialised;
    uint32  sigB = uninitialised;
    uint32  totaldifference = uninitialised;

    uint32  A = uninitialised;
    uint32  B = uninitialised;

    busy = 0;

    while(1) {
        if( start ) {
            busy = 1;
            FSM = 1;
            while( FSM != 0 ) {
                onehot( FSM ) {
                    case 0: {
                        switch( addsub ) {
                            case 0: { A = a; B = b; }
                            case 1: { A = a; B = { ~b[31,1], b[0,31] }; }
                        }
                    }
                    case 1: {
                        expA = floatingpointnumber( A ).exponent;
                        expB = floatingpointnumber( B ).exponent;
                        sigA = { 2b01, floatingpointnumber(A).fraction, 7b0 };
                        sigB = { 2b01, floatingpointnumber(B).fraction, 7b0 };
                        sign = floatingpointnumber(A).sign;
                        ( classEa, classFa ) = class( A );
                        ( classEb, classFb ) = class( B );
                    }
                    case 2: {
                        // ADJUST TO EQUAL EXPONENTS
                        if( ( classEa == 2b00 ) && ( classEb == 2b00 ) ) {
                            if( expA < expB ) {
                                sigA = sigA >> ( expB - expA );
                                expA = expB;
                            } else {
                                if( expB < expA ) {
                                    sigB = sigB >> ( expA - expB );
                                    expB = expA;
                                }
                            }
                        }
                    }
                    case 3: {
                        switch( classEa ) {
                            case 2b00: {
                                switch( classEb ) {
                                    case 2b00: {
                                        switch( { A[31,1], B[31,1] } ) {
                                            case 2b00: { totaldifference = sigA + sigB; }
                                            case 2b01: {
                                                if( sigB > sigA ) {
                                                    sign = ~sign;
                                                    totaldifference = sigB - sigA;
                                                } else {
                                                    totaldifference = sigA - sigB;
                                                }
                                            }
                                            case 2b10: {
                                                if(  sigA > sigB ) {
                                                    totaldifference = sigA - sigB;
                                                } else {
                                                    sign = ~sign;
                                                    totaldifference = sigB - sigA;
                                                }
                                            }
                                            case 2b11: { totaldifference = sigA + sigB; }
                                        }
                                        if( totaldifference == 0 ) {
                                            result = { sign, 31b0 };
                                        } else {
                                            if( totaldifference[31,1] ) {
                                                expA = expA + 1;
                                                result = { sign, expA, totaldifference[8,23] };
                                            } else {
                                                while( ~totaldifference[30,1] ) {
                                                    totaldifference = { totaldifference[0,31], 1b0 };
                                                    expA = expA - 1;
                                                }
                                                result = { sign, expA, totaldifference[7,23] };
                                            }
                                        }
                                    }
                                    case 2b01: { result = A; }
                                    default: {  result = { 1b0, 8b11111111, 23b0 }; }
                                }
                            }
                            case 2b01: {
                                switch( classEb ) {
                                    case 2b00: { result = B; }
                                    case 2b01: { result = 0; }
                                    default: {  result = { 1b0, 8b11111111, 23b0 }; }
                                }
                            }
                            default: {  result = { 1b0, 8b11111111, 23b0 }; }
                        }
                    }
                }
                FSM = { FSM[0,3], 1b0 };
            }
            busy = 0;
        }
    }
}

algorithm floatmultiply(
    input   uint1   start,
    output  uint1   busy,

    input   uint32  a,
    input   uint32  b,

    output  uint32  result
) <autorun> {
    uint2   FSM = uninitialised;

    uint2   classEa = uninitialised;
    uint1   classFa = uninitialised;
    uint2   classEb = uninitialised;
    uint1   classFb = uninitialised;
    uint1   productsign = uninitialised;
    uint48  product = uninitialised;
    int8    productexp  = uninitialised;
    int8    expA = uninitialised;
    int8    expB = uninitialised;

    // Calculation is split into 4 18 x 18 multiplications for DSP
    uint18  A = uninitialised;
    uint18  B = uninitialised;
    uint18  C = uninitialised;
    uint18  D = uninitialised;
    busy = 0;

    while(1) {
        if( start ) {
            busy = 1;
            FSM = 1;
            while( FSM != 0 ) {
                onehot( FSM ) {
                    case 0: {
                        ( classEa, classFa ) = class( a );
                        ( classEb, classFb ) = class( b );
                        expA = floatingpointnumber( a ).exponent - 127;
                        expB = floatingpointnumber( b ).exponent - 127;
                        A = { 10b0, 1b1, a[16,7] };
                        B = { 2b0, a[0,16] };
                        C = { 10b0, 1b1, b[16,7] };
                        D = { 2b0, b[0,16] };
                        product = ( D*B + { D*A, 16b0 } + { C*B, 16b0 } + { C*A, 32b0 } );
                        productexp = expA + expB;
                        productsign = a[31,1] ^ b[31,1];
                    }
                    case 1: {
                        switch( classEa ) {
                            case 2b00: {
                                switch( classEb ) {
                                    case 2b00: {
                                        if( product == 0 ) {
                                            result = { productsign, 31b0 };
                                        } else {
                                            productexp = productexp + 127 + product[47,1];
                                            while( ~product[47,1] ) {
                                                product = { product[0,47], 1b0 };
                                            }
                                            result = { productsign, productexp[0,8], product[24,23] };
                                        }
                                    }
                                    case 2b01: { result = { productsign, 31b0 }; }
                                    default: { result = { productsign, 8b11111111, 23b0 }; }
                                }
                            }
                            case 2b01: {
                                switch( classEb ) {
                                    case 2b00: { result = { productsign, 31b0 }; }
                                    case 2b01: { result = { productsign, 31b0 }; }
                                    default: { result = { productsign, 8b11111111, 23b0 }; }
                                }
                            }
                            default: { result = { productsign, 8b11111111, 23b0 }; }
                        }
                    }
                }
                FSM = { FSM[0,1], 1b0 };
            }
            busy = 0;
        }
    }
}

algorithm floatdivide(
    input   uint1   start,
    output  uint1   busy,

    input   uint32  a,
    input   uint32  b,

    output  uint32  result
) <autorun> {
    uint3   FSM = uninitialised;
    uint1   FSM2 = uninitialised;
    uint2   classEa = uninitialised;
    uint1   classFa = uninitialised;
    uint2   classEb = uninitialised;
    uint1   classFb = uninitialised;
    uint32  temporary = uninitialised;
    uint1   quotientsign = uninitialised;
    int16   quotientexp = uninitialised;
    uint32  quotient = uninitialised;
    uint32  remainder = uninitialised;
    uint6   bit = uninitialised;
    int8    expA = uninitialised;
    int8    expB  = uninitialised;
    uint32  sigA = uninitialised;
    uint32  sigB = uninitialised;

    busy = 0;

    while(1) {
        if( start ) {
            busy = 1;
            FSM = 1;
            while( FSM != 0 ) {
                onehot( FSM ) {
                    case 0: {
                        ( classEa, classFa ) = class( a );
                        ( classEb, classFb ) = class( b );
                        sigA = { 1b1, floatingpointnumber(a).fraction, 8b0 };
                        sigB = { 9b1, floatingpointnumber(b).fraction };
                        expA = floatingpointnumber( a ).exponent - 127;
                        expB = floatingpointnumber( b ).exponent - 127;
                        quotientsign = a[31,1] ^ b[31,1];
                        quotientexp = expA - expB;
                        quotient = 0;
                        remainder = 0;
                        bit = 31;
                    }
                    case 1: { while( ~sigB[0,1] ) { sigB = { 1b0, sigB[1,31] }; } }
                    case 2: {
                        switch( classEa ) {
                            case 2b00: {
                                switch( classEb ) {
                                    case 2b00: {
                                        while( bit != 63 ) {
                                            temporary = { remainder[0,31], sigA[bit,1] };
                                            FSM2 = __unsigned(temporary) >= __unsigned(sigB);
                                            switch( FSM2 ) {
                                                case 1: { remainder = __unsigned(temporary) - __unsigned(sigB); quotient[bit,1] = 1; }
                                                case 0: { remainder = temporary; }
                                            }
                                            bit = bit - 1;
                                        }
                                        switch( quotient ) {
                                            case 0: { result = { quotientsign, 31b0 }; }
                                            default: {
                                                while( ~quotient[31,1] ) {
                                                    quotient = { quotient[0,31], 1b0 };
                                                }
                                                quotientexp = quotientexp + 127 - ( floatingpointnumber(b).fraction > floatingpointnumber(a).fraction );
                                                result = { quotientsign, quotientexp[0,8], quotient[8,23] };
                                            }
                                        }
                                    }
                                    default: { result = { quotientsign, 8b11111111, 23b0 }; }
                                }
                            }
                            case 2b01: {
                                switch( classEb ) {
                                    case 2b00: { result = { quotientsign, 31b0 }; }
                                    default: { result = { quotientsign, 8b11111111, 23b0 }; }
                                }
                            }
                            case 2b10: { result = { quotientsign, 8b11111111, 23b0 }; }
                            case 2b11: { result = { quotientsign, 8b11111111, 23b0 }; }
                        }
                    }
                }
                FSM = { FSM[0,2], 1b0 };
            }
            busy = 0;
        }
    }
}

algorithm floatsqrt(
    input   uint1   start,
    output  uint1   busy,

    input   uint32  sourceReg1F,
    output  uint32  result,
) <autorun> {
    uint2   FSM = uninitialised;
    uint3   FSM2 = uninitialised;
    uint3   count = uninitialised;
    uint8   exp = uninitialised;

    floatdivide FPUdivide( );
    floataddsub FPUaddsub( );
    FPUdivide.start := 0;
    FPUaddsub.start := 0;

    FPUaddsub.addsub = 0;
    busy = 0;

    while(1) {
        if( start ) {
            busy = 1;
            switch( { floatingpointnumber( sourceReg1F ).exponent == 0, sourceReg1F[31,1] } ) {
                case 2b00: {
                    FSM = 1;
                    while( FSM != 0 ) {
                        onehot( FSM ) {
                            case 0: {
                                // FIRST APPROXIMATIONS IS 1
                                result = 32h3f800000;
                            }
                            case 1: {
                                // LOOP UNTIL MANTISSAS ACROSS ITERATIONS ARE APPROXIMATELY EQUAL
                                count = 7;
                                while( count != 0 ) {
                                    FSM2 = 1;
                                    while( FSM2 != 0 ) {
                                        // x(i+1 ) = ( x(i) + n / x(i) ) / 2;
                                        onehot( FSM2 ) {
                                            case 0: {
                                                // DO n/x(i)
                                                FPUdivide.a = sourceReg1F; FPUdivide.b = result;
                                                FPUdivide.start = 1;while( FPUdivide.busy ) {}
                                            }
                                            case 1: {
                                                // DO x(i) + n/x(i)
                                                FPUaddsub.a = result; FPUaddsub.b = FPUdivide.result;
                                                FPUaddsub.start = 1; while( FPUaddsub.busy ) {}
                                            }
                                            case 2: {
                                                // DO (x(i) + n/x(i))/2
                                                exp = floatingpointnumber( FPUaddsub.result ).exponent - 1;
                                                result = { floatingpointnumber( FPUaddsub.result ).sign, exp, floatingpointnumber( FPUaddsub.result ).fraction };
                                            }
                                        }
                                        FSM2 = { FSM[0,2], 1b0 };
                                    }
                                    count = count - 1;
                                }
                            }
                        }
                        FSM = { FSM[0,1], 1b0 };
                    }
                }
                case 2b10: { result = 0; }
                default: { result = { sourceReg1F[31,1], 8b11111111, 23b0 }; }
            }
            busy = 0;
        }
    }
}

algorithm floatclassify(
    input   uint32  sourceReg1F,
    output  uint32  classification
) <autorun> {
    uint2   classE = uninitialised;
    uint1   classF = uninitialised;

    while(1) {
        ( classE, classF ) = class( sourceReg1F );
        switch( classE ) {
            case 2b00: { classification = floatingpointnumber(sourceReg1F).sign ? { 23b0, 9b000000010 } : { 23b0, 9b000100000 }; }
            case 2b01: { classification = floatingpointnumber(sourceReg1F).sign ? { 23b0, 9b000001000 } : { 23b0, 9b000010000 }; }
            case 2b10: { classification = classF ? ( floatingpointnumber(sourceReg1F).sign ? { 23b0, 9b000000001 } : { 23b0, 9b001000000 } ) :
                                            ( floatingpointnumber(sourceReg1F).sign ? { 23b0, 9b100000000 } : { 23b0, 9b010000000 } ); }
        }
    }
}

algorithm floatcomparison(
    input   uint3   function3,
    input   uint32  sourceReg1F,
    input   uint32  sourceReg2F,
    output  uint1   comparison,
) <autorun> {
    while(1) {
        switch( function3 ) {
            case 3b000: {
                // LESS THAN EQUAL OMPARISON OF 2 FLOATING POINT NUMBERS
                comparison = ( sourceReg1F[31,1] != sourceReg2F[31,1] ) ? sourceReg1F[31,1] | ((( sourceReg1F | sourceReg2F ) << 1) == 0 ) : ( sourceReg1F == sourceReg2F ) | ( sourceReg1F[31,1] ^ ( sourceReg1F < sourceReg2F ));
            }
            case 3b001: {
                // LESS THAN COMPARISON OF 2 FLOATING POINT NUMBERS
                comparison = ( sourceReg1F[31,1] != sourceReg2F[31,1] ) ? sourceReg1F[31,1] & ((( sourceReg1F | sourceReg2F ) << 1) != 0 ) : ( sourceReg1F != sourceReg2F ) & ( sourceReg1F[31,1] ^ ( sourceReg1F < sourceReg2F));
            }
            case 3b010: {
                // EQUAL COMPARISON OF 2 FLOATING POINT NUMBERS
                comparison = ( sourceReg1F == sourceReg2F ) | ((( sourceReg1F | sourceReg2F ) << 1) == 0 );
            }
        }
    }
}

algorithm floatsign(
    input   uint3   function3,
    input   uint32  sourceReg1F,
    input   uint32  sourceReg2F,
    output  uint32  result,
) <autorun> {
    while(1) {
        switch( function3 ) {
            default: { result = { sourceReg2F[31,1], sourceReg1F[0,31] }; }                         // FSGNJ.S
            case 3b001: { result = { sourceReg2F[31,1], sourceReg1F[0,31] }; }                      // FSGNJN.S
            case 3b010: { result = { sourceReg1F[31,1] ^ sourceReg2F[31,1], sourceReg1F[0,31] }; }  // FSGNJX.S
        }
    }
}

algorithm floattouint(
    input   uint32  sourceReg1F,
    output  uint32  result,
    output  uint1   busy,
    input   uint1   start
) <autorun> {
    uint2   classE = uninitialised;
    uint1   classF = uninitialised;
    int8    exp = uninitialised;
    uint33  sig = uninitialised;

    busy = 0;

    while(1) {
        if( start ) {
            busy = 1;
            ( classE, classF ) = class( sourceReg1F );
            switch( classE ) {
                case 2b00: {
                    switch( sourceReg1F[31,1] ) {
                        case 1: { result = 0; }
                        default: {
                            exp = floatingpointnumber( sourceReg1F ).exponent - 127;
                            if( exp < 24 ) {
                                sig = { 9b1, sourceReg1F[0,23], 1b0 } >> ( 23 - exp );
                            } else {
                                sig = { 9b1, sourceReg1F[0,23], 1b0 } << ( exp - 24);
                            }
                            result = ( exp > 31 ) ? 32hffffffff : ( sig[1,32] + sig[0,1] );
                        }
                    }
                }
                case 2b01: { result = 0; }
                case 2b10: { result = sourceReg1F[31,1] ? 0 : 32hffffffff;  }
            }
            busy = 0;
        }
    }
}

algorithm floattoint(
    input   uint32  sourceReg1F,
    output  uint32  result,
    output  uint1   busy,
    input   uint1   start
) <autorun> {
    uint2   classE = uninitialised;
    uint1   classF = uninitialised;
    int8    exp = uninitialised;
    uint33  sig = uninitialised;

    busy = 0;

    while(1) {
        if( start ) {
            busy = 1;
            ( classE, classF ) = class( sourceReg1F );
            switch( classE ) {
                case 2b00: {
                    exp = floatingpointnumber( sourceReg1F ).exponent - 127;
                    if( exp < 24 ) {
                        sig = { 9b1, sourceReg1F[0,23], 1b0 } >> ( 23 - exp );
                    } else {
                        sig = { 9b1, sourceReg1F[0,23], 1b0 } << ( exp - 24);
                    }
                    result = ( exp > 30 ) ? ( sourceReg1F[31,1] ? 32hffffffff : 32h7fffffff ) : sourceReg1F[31,1] ? -( sig[1,32] + sig[0,1] ) : ( sig[1,32] + sig[0,1] );
                 }
                case 2b01: { result = 0; }
                case 2b10: { result = sourceReg1F[31,1] ? 32hffffffff : 32h7fffffff; }
            }
            busy = 0;
        }
    }
}
