/* Optimized cosf function.
   Copyright (C) 2012 Free Software Foundation, Inc.
   This file is part of the GNU C Library.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with the GNU C Library; if not, see
   <http://www.gnu.org/licenses/>.  */

#include <sysdep.h>
#define __need_Emath
#include <bits/errno.h>

/* Short algorithm description:
 *
 *  1) if |x| == 0: return 1.0-|x|.
 *  2) if |x| <  2^-27: return 1.0-|x|.
 *  3) if |x| <  2^-5 : return 1.0+x^2*DP_COS2_0+x^5*DP_COS2_1.
 *  4) if |x| <   Pi/4: return 1.0+x^2*(C0+x^2*(C1+x^2*(C2+x^2*(C3+x^2*C4)))).
 *  5) if |x| < 9*Pi/4:
 *      5.1) Range reduction: k=trunc(|x|/(Pi/4)), j=(k+1)&0x0e, n=k+3,
 *           t=|x|-j*Pi/4.
 *      5.2) Reconstruction:
 *          s = (-1.0)^((n>>2)&1)
 *          if(n&2 != 0) {
 *              using cos(t) polynomial for |t|<Pi/4, result is
 *              s     * (1.0+t^2*(C0+t^2*(C1+t^2*(C2+t^2*(C3+t^2*C4))))).
 *          } else {
 *              using sin(t) polynomial for |t|<Pi/4, result is
 *              s * t * (1.0+t^2*(S0+t^2*(S1+t^2*(S2+t^2*(S3+t^2*S4))))).
 *          }
 *  6) if |x| < 2^23, large args:
 *      6.1) Range reduction: k=trunc(|x|/(Pi/4)), j=(k+1)&0xfffffffe, n=k+3,
 *           t=|x|-j*Pi/4.
 *      6.2) Reconstruction same as (5.2).
 *  7) if |x| >= 2^23, very large args:
 *      7.1) Range reduction: k=trunc(|x|/(Pi/4)), j=(k+1)&0xfffffffe, n=k+3,
 *           t=|x|-j*Pi/4.
 *      7.2) Reconstruction same as (5.2).
 *  8) if x is Inf, return x-x, and set errno=EDOM.
 *  9) if x is NaN, return x-x.
 *
 * Special cases:
 *  cos(+-0) = 1 not raising inexact,
 *  cos(subnormal) raises inexact,
 *  cos(min_normalized) raises inexact,
 *  cos(normalized) raises inexact,
 *  cos(Inf) = NaN, raises invalid, sets errno to EDOM,
 *  cos(NaN) = NaN.
 */

	.text
ENTRY(__cosf)
	/* Input: single precision x in %xmm0 */

	movd	%xmm0, %eax		/* Bits of x */
	movaps	%xmm0, %xmm7		/* Copy of x */
	cvtss2sd %xmm0, %xmm0		/* DP x */
	movss	L(SP_ABS_MASK)(%rip), %xmm3
	andl	$0x7fffffff, %eax	/* |x| */

	cmpl	$0x3f490fdb, %eax	/* |x|<Pi/4?  */
	jb	L(arg_less_pio4)

	/* Here if |x|>=Pi/4 */
	andps	%xmm7, %xmm3		/* SP |x| */
	andpd	L(DP_ABS_MASK)(%rip), %xmm0	/* DP |x| */
	movss	L(SP_INVPIO4)(%rip), %xmm2	/* SP 1/(Pi/4) */

	cmpl	$0x40e231d6, %eax	/* |x|<9*Pi/4?  */
	jae	L(large_args)

	/* Here if Pi/4<=|x|<9*Pi/4 */
	mulss	%xmm3, %xmm2		/* SP |x|/(Pi/4) */
	cvttss2si %xmm2, %eax		/* k, number of Pi/4 in x */
	lea	L(PIO4J)(%rip), %rsi
	addl	$1, %eax		/* k+1 */
	movl	$0x0e, %edx
	andl	%eax, %edx		/* j = (k+1)&0x0e */
	addl	$2, %eax		/* n */
	subsd	(%rsi,%rdx,8), %xmm0	/* t = |x| - j * Pi/4 */

L(reconstruction):
	/* Input: %eax=n, %xmm0=t */
	testl	$2, %eax		/* n&2 != 0?  */
	jz	L(sin_poly)

/*L(cos_poly):*/
	/* Here if cos(x) calculated using cos(t) polynomial for |t|<Pi/4:
	 * y = t*t; z = y*y;
	 * s = sign(x) * (-1.0)^((n>>2)&1)
	 * result = s     * (1.0+t^2*(C0+t^2*(C1+t^2*(C2+t^2*(C3+t^2*C4)))))
	 */
	shrl	$2, %eax		/* n>>2 */
	mulsd	%xmm0, %xmm0		/* y=t^2 */
	andl	$1, %eax		/* (n>>2)&1 */
	movaps	%xmm0, %xmm1		/* y */
	mulsd	%xmm0, %xmm0		/* z=t^4 */

	movsd	L(DP_C4)(%rip), %xmm4	/* C4 */
	mulsd	%xmm0, %xmm4		/* z*C4 */
	movsd	L(DP_C3)(%rip), %xmm3	/* C3 */
	mulsd	%xmm0, %xmm3		/* z*C3 */
	lea	L(DP_ONES)(%rip), %rsi
	addsd	L(DP_C2)(%rip), %xmm4	/* C2+z*C4 */
	mulsd	%xmm0, %xmm4		/* z*(C2+z*C4) */
	addsd	L(DP_C1)(%rip), %xmm3	/* C1+z*C3 */
	mulsd	%xmm0, %xmm3		/* z*(C1+z*C3) */
	addsd	L(DP_C0)(%rip), %xmm4	/* C0+z*(C2+z*C4) */
	mulsd	%xmm1, %xmm4		/* y*(C0+z*(C2+z*C4)) */

	addsd	%xmm4, %xmm3		/* y*(C0+y*(C1+y*(C2+y*(C3+y*C4)))) */
	/* 1.0+y*(C0+y*(C1+y*(C2+y*(C3+y*C4)))) */
	addsd	L(DP_ONES)(%rip), %xmm3

	mulsd	(%rsi,%rax,8), %xmm3	/* DP result */
	cvtsd2ss %xmm3, %xmm0		/* SP result */
	ret

	.p2align	4
L(sin_poly):
	/* Here if cos(x) calculated using sin(t) polynomial for |t|<Pi/4:
	 * y = t*t; z = y*y;
	 * s = sign(x) * (-1.0)^((n>>2)&1)
	 * result = s * t * (1.0+t^2*(S0+t^2*(S1+t^2*(S2+t^2*(S3+t^2*S4)))))
	 */

	movaps	%xmm0, %xmm4		/* t */
	shrl	$2, %eax		/* n>>2 */
	mulsd	%xmm0, %xmm0		/* y=t^2 */
	andl	$1, %eax		/* (n>>2)&1 */
	movaps	%xmm0, %xmm1		/* y */
	mulsd	%xmm0, %xmm0		/* z=t^4 */

	movsd	L(DP_S4)(%rip), %xmm2	/* S4 */
	mulsd	%xmm0, %xmm2		/* z*S4 */
	movsd	L(DP_S3)(%rip), %xmm3	/* S3 */
	mulsd	%xmm0, %xmm3		/* z*S3 */
	lea	L(DP_ONES)(%rip), %rsi
	addsd	L(DP_S2)(%rip), %xmm2	/* S2+z*S4 */
	mulsd	%xmm0, %xmm2		/* z*(S2+z*S4) */
	addsd	L(DP_S1)(%rip), %xmm3	/* S1+z*S3 */
	mulsd	%xmm0, %xmm3		/* z*(S1+z*S3) */
	addsd	L(DP_S0)(%rip), %xmm2	/* S0+z*(S2+z*S4) */
	mulsd	%xmm1, %xmm2		/* y*(S0+z*(S2+z*S4)) */
	/* t*s, where s = sign(x) * (-1.0)^((n>>2)&1) */
	mulsd	(%rsi,%rax,8), %xmm4
	/* y*(S0+y*(S1+y*(S2+y*(S3+y*S4)))) */
	addsd	%xmm2, %xmm3
	/* t*s*y*(S0+y*(S1+y*(S2+y*(S3+y*S4)))) */
	mulsd	%xmm4, %xmm3
	/* t*s*(1.0+y*(S0+y*(S1+y*(S2+y*(S3+y*S4)))) */
	addsd	%xmm4, %xmm3
	cvtsd2ss %xmm3, %xmm0		/* SP result */
	ret

	.p2align	4
L(large_args):
	/* Here if |x|>=9*Pi/4 */
	cmpl	$0x7f800000, %eax	/* x is Inf or NaN?  */
	jae	L(arg_inf_or_nan)

	/* Here if finite |x|>=9*Pi/4 */
	cmpl	$0x4b000000, %eax	/* |x|<2^23?  */
	jae	L(very_large_args)

	/* Here if 9*Pi/4<=|x|<2^23 */
	movsd	L(DP_INVPIO4)(%rip), %xmm1 /* 1/(Pi/4) */
	mulsd	%xmm0, %xmm1		/* |x|/(Pi/4) */
	cvttsd2si %xmm1, %eax		/* k=trunc(|x|/(Pi/4)) */
	addl	$1, %eax		/* k+1 */
	movl	%eax, %edx
	andl	$0xfffffffe, %edx	/* j=(k+1)&0xfffffffe */
	cvtsi2sdl %edx, %xmm4		/* DP j */
	movsd	L(DP_PIO4HI)(%rip), %xmm2 /* -PIO4HI = high part of -Pi/4 */
	mulsd	%xmm4, %xmm2		/* -j*PIO4HI */
	movsd	L(DP_PIO4LO)(%rip), %xmm3 /* -PIO4LO = low part of -Pi/4 */
	addsd	%xmm2, %xmm0		/* |x| - j*PIO4HI */
	addl	$2, %eax		/* n */
	mulsd	%xmm3, %xmm4		/* j*PIO4LO */
	addsd	%xmm4, %xmm0		/* t = |x| - j*PIO4HI - j*PIO4LO */
	jmp	L(reconstruction)

	.p2align	4
L(very_large_args):
	/* Here if finite |x|>=2^23 */

	/* bitpos = (ix>>23) - BIAS_32 + 59; */
	shrl	$23, %eax		/* eb = biased exponent of x */
	/* bitpos = eb - 0x7f + 59, where 0x7f is exponent bias */
	subl	$68, %eax
	movl	$28, %ecx		/* %cl=28 */
	movl	%eax, %edx		/* bitpos copy */

	/* j = bitpos/28; */
	div	%cl			/* j in register %al=%ax/%cl */
	movapd	%xmm0, %xmm3		/* |x| */
	/* clear unneeded remainder from %ah */
	andl	$0xff, %eax

	imull	$28, %eax, %ecx		/* j*28 */
	lea	L(_FPI)(%rip), %rsi
	movsd	L(DP_HI_MASK)(%rip), %xmm4 /* DP_HI_MASK */
	movapd	%xmm0, %xmm5		/* |x| */
	mulsd	-16(%rsi,%rax,8), %xmm3	/* tmp3 = FPI[j-2]*|x| */
	movapd	%xmm0, %xmm1		/* |x| */
	mulsd	-8(%rsi,%rax,8), %xmm5	/* tmp2 = FPI[j-1]*|x| */
	mulsd	(%rsi,%rax,8), %xmm0	/* tmp0 = FPI[j]*|x| */
	addl	$19, %ecx		/* j*28+19 */
	mulsd	8(%rsi,%rax,8), %xmm1	/* tmp1 = FPI[j+1]*|x| */
	cmpl	%ecx, %edx		/* bitpos>=j*28+19?  */
	jl	L(very_large_skip1)

	/* Here if bitpos>=j*28+19 */
	andpd	%xmm3, %xmm4		/* HI(tmp3) */
	subsd	%xmm4, %xmm3		/* tmp3 = tmp3 - HI(tmp3) */
L(very_large_skip1):

	movsd	L(DP_2POW52)(%rip), %xmm6
	movapd	%xmm5, %xmm2		/* tmp2 copy */
	addsd	%xmm3, %xmm5		/* tmp5 = tmp3 + tmp2 */
	movl	$1, %edx
	addsd	%xmm5, %xmm6		/* tmp6 = tmp5 + 2^52 */
	movsd	8+L(DP_2POW52)(%rip), %xmm4
	movd	%xmm6, %eax		/* k = I64_LO(tmp6); */
	addsd	%xmm6, %xmm4		/* tmp4 = tmp6 - 2^52 */
	comisd	%xmm5, %xmm4		/* tmp4 > tmp5?  */
	jbe	L(very_large_skip2)

	/* Here if tmp4 > tmp5 */
	subl	$1, %eax		/* k-- */
	addsd	8+L(DP_ONES)(%rip), %xmm4 /* tmp4 -= 1.0 */
L(very_large_skip2):

	andl	%eax, %edx		/* k&1 */
	lea	L(DP_ZERONE)(%rip), %rsi
	subsd	%xmm4, %xmm3		/* tmp3 -= tmp4 */
	addsd	(%rsi,%rdx,8), %xmm3	/* t  = DP_ZERONE[k&1] + tmp3 */
	addsd	%xmm2, %xmm3		/* t += tmp2 */
	addsd	%xmm3, %xmm0		/* t += tmp0 */
	addl	$3, %eax		/* n=k+3 */
	addsd	%xmm1, %xmm0		/* t += tmp1 */
	mulsd	L(DP_PIO4)(%rip), %xmm0	/* t *= PI04 */

	jmp	L(reconstruction)	/* end of very_large_args peth */

	.p2align	4
L(arg_less_pio4):
	/* Here if |x|<Pi/4 */
	cmpl	$0x3d000000, %eax	/* |x|<2^-5?  */
	jl	L(arg_less_2pn5)

	/* Here if 2^-5<=|x|<Pi/4 */
	mulsd	%xmm0, %xmm0		/* y=x^2 */
	movaps	%xmm0, %xmm1		/* y */
	mulsd	%xmm0, %xmm0		/* z=x^4 */
	movsd	L(DP_C4)(%rip), %xmm3	/* C4 */
	mulsd	%xmm0, %xmm3		/* z*C4 */
	movsd	L(DP_C3)(%rip), %xmm5	/* C3 */
	mulsd	%xmm0, %xmm5		/* z*C3 */
	addsd	L(DP_C2)(%rip), %xmm3	/* C2+z*C4 */
	mulsd	%xmm0, %xmm3		/* z*(C2+z*C4) */
	addsd	L(DP_C1)(%rip), %xmm5	/* C1+z*C3 */
	mulsd	%xmm0, %xmm5		/* z*(C1+z*C3) */
	addsd	L(DP_C0)(%rip), %xmm3	/* C0+z*(C2+z*C4) */
	mulsd	%xmm1, %xmm3		/* y*(C0+z*(C2+z*C4)) */
	/* y*(C0+y*(C1+y*(C2+y*(C3+y*C4)))) */
	addsd	%xmm5, %xmm3
	/* 1.0 + y*(C0+y*(C1+y*(C2+y*(C3+y*C4)))) */
	addsd	L(DP_ONES)(%rip), %xmm3
	cvtsd2ss %xmm3, %xmm0		/* SP result */
	ret

	.p2align	4
L(arg_less_2pn5):
	/* Here if |x|<2^-5 */
	cmpl	$0x32000000, %eax	/* |x|<2^-27?  */
	jl	L(arg_less_2pn27)

	/* Here if 2^-27<=|x|<2^-5 */
	mulsd	%xmm0, %xmm0		/* DP x^2 */
	movsd	L(DP_COS2_1)(%rip), %xmm3 /* DP DP_COS2_1 */
	mulsd	%xmm0, %xmm3		/* DP x^2*DP_COS2_1 */
	addsd	L(DP_COS2_0)(%rip), %xmm3 /* DP DP_COS2_0+x^2*DP_COS2_1 */
	mulsd	%xmm0, %xmm3		/* DP x^2*DP_COS2_0+x^4*DP_COS2_1 */
	/* DP 1.0+x^2*DP_COS2_0+x^4*DP_COS2_1 */
	addsd	L(DP_ONES)(%rip), %xmm3
	cvtsd2ss %xmm3, %xmm0		/* SP result */
	ret

	.p2align	4
L(arg_less_2pn27):
	/* Here if |x|<2^-27 */
	andps	L(SP_ABS_MASK)(%rip),%xmm7 /* |x| */
	movss	L(SP_ONE)(%rip), %xmm0	/* 1.0 */
	subss	%xmm7, %xmm0		/* result is 1.0-|x| */
	ret

	.p2align	4
L(arg_inf_or_nan):
	/* Here if |x| is Inf or NAN */
	jne	L(skip_errno_setting)	/* in case of x is NaN */

	/* Here if x is Inf. Set errno to EDOM.  */
	call	JUMPTARGET(__errno_location)
	movl	$EDOM, (%rax)

	.p2align	4
L(skip_errno_setting):
	/* Here if |x| is Inf or NAN. Continued.  */
	movaps	%xmm7, %xmm0		/* load x */
	subss	%xmm0, %xmm0		/* Result is NaN */
	ret
END(__cosf)

	.section .rodata, "a"
	.p2align 3
L(PIO4J): /* Table of j*Pi/4, for j=0,1,..,10 */
	.long	0x00000000,0x00000000
	.long	0x54442d18,0x3fe921fb
	.long	0x54442d18,0x3ff921fb
	.long	0x7f3321d2,0x4002d97c
	.long	0x54442d18,0x400921fb
	.long	0x2955385e,0x400f6a7a
	.long	0x7f3321d2,0x4012d97c
	.long	0xe9bba775,0x4015fdbb
	.long	0x54442d18,0x401921fb
	.long	0xbeccb2bb,0x401c463a
	.long	0x2955385e,0x401f6a7a
	.type L(PIO4J), @object
	ASM_SIZE_DIRECTIVE(L(PIO4J))

	.p2align 3
L(_FPI): /* 4/Pi broken into sum of positive DP values */
	.long	0x00000000,0x00000000
	.long	0x6c000000,0x3ff45f30
	.long	0x2a000000,0x3e3c9c88
	.long	0xa8000000,0x3c54fe13
	.long	0xd0000000,0x3aaf47d4
	.long	0x6c000000,0x38fbb81b
	.long	0xe0000000,0x3714acc9
	.long	0x7c000000,0x3560e410
	.long	0x56000000,0x33bca2c7
	.long	0xac000000,0x31fbd778
	.long	0xe0000000,0x300b7246
	.long	0xe8000000,0x2e5d2126
	.long	0x48000000,0x2c970032
	.long	0xe8000000,0x2ad77504
	.long	0xe0000000,0x290921cf
	.long	0xb0000000,0x274deb1c
	.long	0xe0000000,0x25829a73
	.long	0xbe000000,0x23fd1046
	.long	0x10000000,0x2224baed
	.long	0x8e000000,0x20709d33
	.long	0x80000000,0x1e535a2f
	.long	0x64000000,0x1cef904e
	.long	0x30000000,0x1b0d6398
	.long	0x24000000,0x1964ce7d
	.long	0x16000000,0x17b908bf
	.type L(_FPI), @object
	ASM_SIZE_DIRECTIVE(L(_FPI))

/* Coefficients of polynomial
   for cos(x)~=1.0+x^2*DP_COS2_0+x^4*DP_COS2_1, |x|<2^-5.  */
	.p2align 3
L(DP_COS2_0):
	.long	0xff5cc6fd,0xbfdfffff
	.type L(DP_COS2_0), @object
	ASM_SIZE_DIRECTIVE(L(DP_COS2_0))

	.p2align 3
L(DP_COS2_1):
	.long	0xb178dac5,0x3fa55514
	.type L(DP_COS2_1), @object
	ASM_SIZE_DIRECTIVE(L(DP_COS2_1))

	.p2align 3
L(DP_ZERONE):
	.long	0x00000000,0x00000000	/* 0.0 */
	.long	0x00000000,0xbff00000	/* 1.0 */
	.type L(DP_ZERONE), @object
	ASM_SIZE_DIRECTIVE(L(DP_ZERONE))

	.p2align 3
L(DP_ONES):
	.long	0x00000000,0x3ff00000	/* +1.0 */
	.long	0x00000000,0xbff00000	/* -1.0 */
	.type L(DP_ONES), @object
	ASM_SIZE_DIRECTIVE(L(DP_ONES))

/* Coefficients of polynomial
   for sin(t)~=t+t^3*(S0+t^2*(S1+t^2*(S2+t^2*(S3+t^2*S4)))), |t|<Pi/4.  */
	.p2align 3
L(DP_S3):
	.long	0x64e6b5b4,0x3ec71d72
	.type L(DP_S3), @object
	ASM_SIZE_DIRECTIVE(L(DP_S3))

	.p2align 3
L(DP_S1):
	.long	0x10c2688b,0x3f811111
	.type L(DP_S1), @object
	ASM_SIZE_DIRECTIVE(L(DP_S1))

	.p2align 3
L(DP_S4):
	.long	0x1674b58a,0xbe5a947e
	.type L(DP_S4), @object
	ASM_SIZE_DIRECTIVE(L(DP_S4))

	.p2align 3
L(DP_S2):
	.long	0x8b4bd1f9,0xbf2a019f
	.type L(DP_S2),@object
	ASM_SIZE_DIRECTIVE(L(DP_S2))

	.p2align 3
L(DP_S0):
	.long	0x55551cd9,0xbfc55555
	.type L(DP_S0), @object
	ASM_SIZE_DIRECTIVE(L(DP_S0))

/* Coefficients of polynomial
   for cos(t)~=1.0+t^2*(C0+t^2*(C1+t^2*(C2+t^2*(C3+t^2*C4)))), |t|<Pi/4.  */
	.p2align 3
L(DP_C3):
	.long	0x9ac43cc0,0x3efa00eb
	.type L(DP_C3), @object
	ASM_SIZE_DIRECTIVE(L(DP_C3))

	.p2align 3
L(DP_C1):
	.long	0x545c50c7,0x3fa55555
	.type L(DP_C1), @object
	ASM_SIZE_DIRECTIVE(L(DP_C1))

	.p2align 3
L(DP_C4):
	.long	0xdd8844d7,0xbe923c97
	.type L(DP_C4), @object
	ASM_SIZE_DIRECTIVE(L(DP_C4))

	.p2align 3
L(DP_C2):
	.long	0x348b6874,0xbf56c16b
	.type L(DP_C2), @object
	ASM_SIZE_DIRECTIVE(L(DP_C2))

	.p2align 3
L(DP_C0):
	.long	0xfffe98ae,0xbfdfffff
	.type L(DP_C0), @object
	ASM_SIZE_DIRECTIVE(L(DP_C0))

	.p2align 3
L(DP_PIO4):
	.long	0x54442d18,0x3fe921fb	/* Pi/4 */
	.type L(DP_PIO4), @object
	ASM_SIZE_DIRECTIVE(L(DP_PIO4))

	.p2align 3
L(DP_2POW52):
	.long	0x00000000,0x43300000	/* +2^52 */
	.long	0x00000000,0xc3300000	/* -2^52 */
	.type L(DP_2POW52), @object
	ASM_SIZE_DIRECTIVE(L(DP_2POW52))

	.p2align 3
L(DP_INVPIO4):
	.long	0x6dc9c883,0x3ff45f30	/* 4/Pi */
	.type L(DP_INVPIO4), @object
	ASM_SIZE_DIRECTIVE(L(DP_INVPIO4))

	.p2align 3
L(DP_PIO4HI):
	.long	0x54000000,0xbfe921fb	/* High part of Pi/4 */
	.type L(DP_PIO4HI), @object
	ASM_SIZE_DIRECTIVE(L(DP_PIO4HI))

	.p2align 3
L(DP_PIO4LO):
	.long	0x11A62633,0xbe010b46	/* Low part of Pi/4 */
	.type L(DP_PIO4LO), @object
	ASM_SIZE_DIRECTIVE(L(DP_PIO4LO))

	.p2align 2
L(SP_INVPIO4):
	.long	0x3fa2f983		/* 4/Pi */
	.type L(SP_INVPIO4), @object
	ASM_SIZE_DIRECTIVE(L(SP_INVPIO4))

	.p2align 4
L(DP_ABS_MASK): /* Mask for getting DP absolute value */
	.long	0xffffffff,0x7fffffff
	.long	0xffffffff,0x7fffffff
	.type L(DP_ABS_MASK), @object
	ASM_SIZE_DIRECTIVE(L(DP_ABS_MASK))

	.p2align 3
L(DP_HI_MASK): /* Mask for getting high 21 bits of DP value */
	.long	0x00000000,0xffffffff
	.type L(DP_HI_MASK), @object
	ASM_SIZE_DIRECTIVE(L(DP_HI_MASK))

	.p2align 4
L(SP_ABS_MASK): /* Mask for getting SP absolute value */
	.long	0x7fffffff,0x7fffffff
	.long	0x7fffffff,0x7fffffff
	.type L(SP_ABS_MASK), @object
	ASM_SIZE_DIRECTIVE(L(SP_ABS_MASK))

	.p2align 2
L(SP_ONE):
	.long	0x3f800000		/* 1.0 */
	.type L(SP_ONE), @object
	ASM_SIZE_DIRECTIVE(L(SP_ONE))

weak_alias(__cosf, cosf)
