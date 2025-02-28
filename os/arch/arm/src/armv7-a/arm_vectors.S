/****************************************************************************
 *
 * Copyright 2023 Samsung Electronics All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
 * either express or implied. See the License for the specific
 * language governing permissions and limitations under the License.
 *
 ****************************************************************************/
/****************************************************************************
 * arch/arm/src/armv7-a/arm_vectors.S
 *
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.  The
 * ASF licenses this file to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance with the
 * License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
 * License for the specific language governing permissions and limitations
 * under the License.
 *
 ****************************************************************************/

/****************************************************************************
 * Included Files
 ****************************************************************************/

#include <tinyara/config.h>
#include <tinyara/irq.h>

#include "arm.h"
#include "cp15.h"
#include "chip.h"

	.file	"arm_vectors.S"

/****************************************************************************
 * Pre-processor Definitions
 ****************************************************************************/

/****************************************************************************
 * Private Data
 ****************************************************************************/

/****************************************************************************
 * Assembly Macros
 ****************************************************************************/

/****************************************************************************
 * Name: cpuindex
 *
 * Description:
 *   Return an index idenifying the current CPU.  Single CPU case.  Must be
 *   provided by MCU-specific logic in chip.h for the SMP case.
 *
 ****************************************************************************/

#if !defined(CONFIG_SMP) && CONFIG_ARCH_INTERRUPTSTACK > 7
	.macro	cpuindex, index
	.mov		\index, #0
	.endm
#endif

/****************************************************************************
 * Name: setirqstack
 *
 * Description:
 *   Set the current stack pointer to the "top" of the IRQ interrupt stack.  Single
 *   CPU case.  Must be provided by MCU-specific logic in chip.h for the SMP case.
 *
 ****************************************************************************/

#if !defined(CONFIG_SMP) && CONFIG_ARCH_INTERRUPTSTACK > 7
	.macro	setirqstack, tmp1, tmp2
	ldr		sp, .Lirqstacktop		/* SP = IRQ stack top */
	.endm
#endif

/****************************************************************************
 * Name: setfiqstack
 *
 * Description:
 *   Set the current stack pointer to the "top" of the FIQ interrupt stack.  Single
 *   CPU case.  Must be provided by MCU-specific logic in chip.h for the SMP case.
 *
 ****************************************************************************/

#if !defined(CONFIG_SMP) && CONFIG_ARCH_INTERRUPTSTACK > 7
	.macro	setfiqstack, tmp1, tmp2
	ldr		sp, .Lfiqstacktop		/* SP = FIQ stack top */
	.endm
#endif

/****************************************************************************
 * Name: savefpu
 *
 * Description:
 *   Save the state of the floating point registers.
 *
 ****************************************************************************/

#ifdef CONFIG_ARCH_FPU
	.macro	savefpu, out, tmp
	/* Store all floating point registers.  Registers are stored in numeric order,
	 * s0, s1, ... in increasing address order.
	 */

#ifdef CONFIG_ARM_DPFPU32
	vstmia.64	\out!, {d0-d15}			/* Save the full FP context */
	vstmia.64	\out!, {d16-d31}
#else
	vstmia		\out!, {s0-s31}			/* Save the full FP context */
#endif

	/* Store the floating point control and status register.  At the end of the
	 * vstmia, r1 will point to the FPSCR storage location.
	 */

	vmrs		\tmp, fpscr			/* Fetch the FPSCR */
	str		\tmp, [\out], #4		/* Save the floating point control and status register */
	.endm
#endif

/****************************************************************************
 * Name: restorefpu
 *
 * Description:
 *   Restore the state of the floating point registers.
 *
 ****************************************************************************/

#ifdef CONFIG_ARCH_FPU
	.macro	restorefpu, in, tmp
	/* Load all floating point registers.  Registers are loaded in numeric order,
	 * s0, s1, ... in increasing address order.
	 */

#ifdef CONFIG_ARM_DPFPU32
	vldmia.64	\in!, {d0-d15}			/* Restore the full FP context */
	vldmia.64	\in!, {d16-d31}
#else
	vldmia		\in!, {s0-s31}			/* Restore the full FP context */
#endif

	/* Load the floating point control and status register.   At the end of the
	 * vstmia, \in will point to the FPSCR storage location.
	 */

	ldr		\tmp, [\in], #4			/* Fetch the floating point control and status register */
	vmsr		fpscr, \tmp			/* Restore the FPSCR */
	.endm
#endif

/****************************************************************************
 * Private Functions
 ****************************************************************************/

	.text

/****************************************************************************
 * Public Functions
 ****************************************************************************/

/****************************************************************************
 * Name: arm_vectorirq
 *
 * Description:
 *   Interrupt exception. Entered in IRQ mode with spsr = SVC CPSR, lr = SVC PC
 *
 ****************************************************************************/

	.globl	arm_decodeirq
	.globl	arm_vectorirq
	.type	arm_vectorirq, %function

arm_vectorirq:
	/* Switch to SYS mode */

#ifdef CONFIG_ARMV7A_DECODEFIQ
	cpsid		if, #PSR_MODE_SYS
#else
	cpsid		i, #PSR_MODE_SYS
#endif

	/* Create a context structure.  First set aside a stack frame
	 * and store r0-r12 into the frame.
	 */

	sub		sp, sp, #XCPTCONTEXT_SIZE
	stmia		sp, {r0-r12}			/* Save the SYS mode regs */

	cps		#PSR_MODE_IRQ			/* Switch back IRQ mode */

	/* Get the values for r15(pc) and CPSR in r3 and r4 */

	sub		r3, lr, #4
	mrs		r4, spsr

	cps		#PSR_MODE_SYS			/* Then switch back to SYS mode */

	/* Get the correct values of USR/SYS r13(sp) and r14(lr) in r1 and r2 */

	add		r1, sp, #XCPTCONTEXT_SIZE
	mov		r2, r14

	/* Save r13(sp), r14(lr), r15(pc), and the CPSR */

	add		r0, sp, #(4*REG_SP)		/* Offset to pc, cpsr storage */
	stmia		r0, {r1-r4}

#ifdef CONFIG_ARCH_FPU
	/* Save the state of the floating point registers. */

	add		r0, sp, #(4*REG_S0)		/* R1=Address of FP register storage */
	savefpu		r0, r1
#endif

	/* Then call the IRQ handler with interrupts disabled. */

	mov		fp, #0				/* Init frame pointer */
	mov		r0, sp				/* Get r0=xcp */

#if CONFIG_ARCH_INTERRUPTSTACK > 7
	/* Call arm_decodeirq() on the interrupt stack */

	setirqstack	r1, r3				/* SP = interrupt stack top */
	str		r0, [sp, #-4]!			/* Save the xcp address at SP-4 then update SP */
	mov		r4, sp				/* Save the SP in a preserved register */
	bic		sp, sp, #7			/* Force 8-byte alignment */
	bl		arm_decodeirq			/* Call the handler */
	ldr		sp, [r4]			/* Restore the user stack pointer */
#else
	/* Call arm_decodeirq() on the user stack */

	mov		r4, sp				/* Save the SP in a preserved register */

	/* If the interrupt stack is disabled, reserve xcpcontext to ensure
	 * that signal processing can have a separate xcpcontext to handle
	 * signal context (reference: arm_schedulesigaction.c):
	 *      ----------------------
	 *     |    IRQ XCP context   |
	 *      -------------------
	 *     |  Signal XCP context  |
	 *      ----------------------   <- SP
	 */

	sub		sp, sp, #XCPTCONTEXT_SIZE	/* Reserve signal context */

	bic		sp, sp, #7			/* Force 8-byte alignment */
	bl		arm_decodeirq			/* Call the handler */
	mov		sp, r4				/* Restore the possibly unaligned stack pointer */
#endif

#ifdef CONFIG_ARCH_FPU
	/* Restore the state of the floating point registers. */

	add		r1, r0, #(4*REG_S0)		/* R1=Address of FP register storage */
	restorefpu	r1, r2
#endif

	/* Switch back IRQ mode and return with shadow SPSR */

	cps		#PSR_MODE_IRQ

	/* Upon return from arm_decodeirq, r0 holds the pointer to the register
	 * state save area to use to restore the registers.  This may or may not
	 * be the same value that was passed to arm_decodeirq:  It will differ if a
	 * context switch is required.
	 */

	/* Restore the CPSR, IRQ mode registers and return */

	ldr		r1, [r0, #(4*REG_CPSR)]		/* Fetch the return SPSR */
	msr		spsr_cxsf, r1			/* Set the return mode SPSR */

	/* Life is simple when everything is IRQ mode */

	mov		r14, r0				/* (IRQ) r14=Register storage area */
	ldmia		r14!, {r0-r12}			/* Restore common r0-r12 */
	ldmia		r14, {r13, r14}^		/* Restore user mode r13/r14 */
	add		r14, r14, #(4*2)		/* (IRQ) r14=address of r15 storage */
	ldmia		r14, {r15}^			/* Return */

#if !defined(CONFIG_SMP) && CONFIG_ARCH_INTERRUPTSTACK > 7
.Lirqstacktop:
	.word	g_intstacktop
#endif
	.size	arm_vectorirq, . - arm_vectorirq

	.align	5

/****************************************************************************
 * Function: arm_vectorsvc
 *
 * Description:
 *   SVC interrupt. We enter the SVC in SYS mode.
 *
 ****************************************************************************/

	.globl	arm_syscall
	.globl	arm_vectorsvc
	.type	arm_vectorsvc, %function

arm_vectorsvc:
	/* Switch to SYS mode */

#ifdef CONFIG_ARMV7A_DECODEFIQ
	cpsid		if, #PSR_MODE_SYS
#else
	cpsid		i, #PSR_MODE_SYS
#endif

	/* Create a context structure.  First set aside a stack frame
	 * and store r0-r12 into the frame.
	 */

	sub		sp, sp, #XCPTCONTEXT_SIZE
	stmia		sp, {r0-r12}			/* Save the SYS mode regs */

	cps		#PSR_MODE_SVC			/* Switch back SVC mode */

	/* Get the values for r15(pc) and CPSR in r3 and r4 */

	mov		r3, r14				/* Save r14 as the PC as well */
	mrs		r4, spsr			/* Get the saved CPSR */

	cps		#PSR_MODE_SYS			/* Then switch back to SYS mode */

	/* Get the correct values of USR/SYS r13(sp) and r14(lr) in r1 and r2 */

	add		r1, sp, #XCPTCONTEXT_SIZE
	mov		r2, r14

	/* Save r13(sp), r14(lr), r15(pc), and the CPSR */

	add		r0, sp, #(4*REG_SP)		/* Offset to pc, cpsr storage */
	stmia		r0, {r1-r4}

#ifdef CONFIG_ARCH_FPU
	/* Save the state of the floating point registers. */

	add		r0, sp, #(4*REG_S0)		/* R1=Address of FP register storage */
	savefpu		r0, r1
#endif

	/* Then call the SVC handler with interrupts disabled.
	 * void arm_syscall(struct xcptcontext *xcp)
	 */

	mov		fp, #0				/* Init frame pointer */
	mov		r0, sp				/* Get r0=xcp */

#if CONFIG_ARCH_INTERRUPTSTACK > 7
	/* Call arm_syscall() on the interrupt stack */

	setirqstack	r1, r3				/* SP = interrupt stack top */
	str		r0, [sp, #-4]!			/* Save the xcp address at SP-4 then update SP */
	mov		r4, sp				/* Save the SP in a preserved register */
	bic		sp, sp, #7			/* Force 8-byte alignment */
	bl		arm_syscall			/* Call the handler */
	ldr		sp, [r4]			/* Restore the user stack pointer */
#else
	/* Call arm_syscall() on the user stack */

	mov		r4, sp				/* Save the SP in a preserved register */

	/* If the interrupt stack is disabled, reserve xcpcontext to ensure
	 * that signal processing can have a separate xcpcontext to handle
	 * signal context (reference: arm_schedulesigaction.c):
	 *      ----------------------
	 *     |    IRQ XCP context   |
	 *      -------------------
	 *     |  Signal XCP context  |
	 *      ----------------------   <- SP
	 */

	sub		sp, sp, #XCPTCONTEXT_SIZE	/* Reserve signal context */

	bic		sp, sp, #7			/* Force 8-byte alignment */
	bl		arm_syscall			/* Call the handler */
	mov		sp, r4				/* Restore the possibly unaligned stack pointer */
#endif

#ifdef CONFIG_ARCH_FPU
	/* Restore the state of the floating point registers. */

	add		r1, r0, #(4*REG_S0)		/* R1=Address of FP register storage */
	restorefpu	r1, r2
#endif

	/* Switch back SVC mode and return with shadow SPSR */

	cps		#PSR_MODE_SVC

	/* Upon return from arm_syscall, r0 holds the pointer to the register
	 * state save area to use to restore the registers.  This may or may not
	 * be the same value that was passed to arm_syscall:  It will differ if a
	 * context switch is required.
	 */

	/* Restore the CPSR, SYS mode registers and return */

	ldr		r1, [r0, #(4*REG_CPSR)]		/* Fetch the return SPSR */
	msr		spsr_cxsf, r1			/* Set the return mode SPSR */

	/* Life is simple when everything is SVC mode */

	mov		r14, r0				/* (SVC) r14=Register storage area */
	ldmia		r14!, {r0-r12}			/* Restore common r0-r12 */
	ldmia		r14, {r13, r14}^		/* Restore user mode r13/r14 */
	add		r14, r14, #(4*2)		/* (SVC) r14=address of r15 storage */
	ldmia		r14, {r15}^			/* Return */
	.size	arm_vectorsvc, . - arm_vectorsvc

	.align	5

/****************************************************************************
 * Name: arm_vectordata
 *
 * Description:
 *   This is the data abort exception dispatcher. The ARM data abort exception occurs
 *   when a memory fault is detected during a data transfer.  This handler saves the
 *   current processor state and gives control to data abort handler.  This function
 *   is entered in ABORT mode with spsr = SVC CPSR, lr = SVC PC
 *
 ****************************************************************************/

	.globl	arm_dataabort
	.globl	arm_vectordata
	.type	arm_vectordata, %function

arm_vectordata:
	/* Switch to SYS mode */

#ifdef CONFIG_ARMV7A_DECODEFIQ
	cpsid		if, #PSR_MODE_SYS
#else
	cpsid		i, #PSR_MODE_SYS
#endif

	/* Create a context structure.  First set aside a stack frame
	 * and store r0-r12 into the frame.
	 */

	sub		sp, sp, #XCPTCONTEXT_SIZE
	stmia		sp, {r0-r12}			/* Save the SYS mode regs */

	cps		#PSR_MODE_ABT			/* Switch back ABT mode */

	/* Get the values for r15(pc) and CPSR in r3 and r4 */

	sub		r3, lr, #8
	mrs		r4, spsr

	cps		#PSR_MODE_SYS			/* Then switch back to SYS mode */

	/* Get the correct values of USR/SYS r13(sp) and r14(lr) in r1 and r2 */

	add		r1, sp, #XCPTCONTEXT_SIZE
	mov		r2, r14

	/* Save r13(sp), r14(lr), r15(pc), and the CPSR */

	add		r0, sp, #(4*REG_SP)		/* Offset to pc, cpsr storage */
	stmia		r0, {r1-r4}

#ifdef CONFIG_ARCH_FPU
	/* Save the state of the floating point registers. */

	add		r0, sp, #(4*REG_S0)		/* R1=Address of FP register storage */
	savefpu		r0, r1
#endif

	/* Then call the data abort handler with interrupts disabled.
	 * void arm_dataabort(struct xcptcontext *xcp)
	 */

	mov		fp, #0				/* Init frame pointer */
	mov		r0, sp				/* Get r0=xcp */
	mrc		CP15_DFAR(r1)			/* Get R1=DFAR */
	mrc		CP15_DFSR(r2)			/* Get r2=DFSR */
	mov		r4, sp				/* Save the SP in a preserved register */
	bic		sp, sp, #7			/* Force 8-byte alignment */
	bl		arm_dataabort			/* Call the handler */
	mov		sp, r4				/* Restore the possibly unaligned stack pointer */

#ifdef CONFIG_ARCH_FPU
	/* Restore the state of the floating point registers. */

	add		r1, r0, #(4*REG_S0)		/* R1=Address of FP register storage */
	restorefpu	r1, r2
#endif

	/* Switch back ABT mode and return with shadow SPSR */

	cps		#PSR_MODE_ABT

	/* Upon return from arm_dataabort, r0 holds the pointer to the register
	 * state save area to use to restore the registers.  This may or may not
	 * be the same value that was passed to arm_dataabort:  It will differ if a
	 * context switch is required.
	 */

	/* Restore the CPSR, ABT mode registers and return */

	ldr		r1, [r0, #(4*REG_CPSR)]		/* Fetch the return SPSR */
	msr		spsr_cxsf, r1			/* Set the return mode SPSR */

	/* Life is simple when everything is ABT mode */

	mov		r14, r0				/* (ABT) r14=Register storage area */
	ldmia		r14!, {r0-r12}			/* Restore common r0-r12 */
	ldmia		r14, {r13, r14}^		/* Restore user mode r13/r14 */
	add		r14, r14, #(4*2)		/* (ABT) r14=address of r15 storage */
	ldmia		r14, {r15}^			/* Return */
	.size	arm_vectordata, . - arm_vectordata

	.align	5

/****************************************************************************
 * Name: arm_vectorprefetch
 *
 * Description:
 *   This is the prefetch abort exception dispatcher. The ARM prefetch abort exception
 *   occurs when a memory fault is detected during an an instruction fetch.  This
 *   handler saves the current processor state and gives control to prefetch abort
 *   handler.  This function is entered in ABT mode with spsr = SVC CPSR, lr = SVC PC.
 *
 ****************************************************************************/

	.globl	arm_prefetchabort
	.globl	arm_vectorprefetch
	.type	arm_vectorprefetch, %function

arm_vectorprefetch:
	cpsid		if, #PSR_MODE_SYS		/* Switch to SYS mode */

	/* Create a context structure.  First set aside a stack frame
	 * and store r0-r12 into the frame.
	 */

	sub		sp, sp, #XCPTCONTEXT_SIZE
	stmia		sp, {r0-r12}			/* Save the SYS mode regs */

	cps		#PSR_MODE_ABT			/* Switch back ABT mode */

	/* Get the values for r15(pc) and CPSR in r3 and r4 */

	sub		r3, lr, #4
	mrs		r4, spsr

	cps		#PSR_MODE_SYS			/* Then switch back to SYS mode */

	/* Get the correct values of USR/SYS r13(sp) and r14(lr) in r1 and r2 */

	add		r1, sp, #XCPTCONTEXT_SIZE
	mov		r2, r14

	/* Save r13(sp), r14(lr), r15(pc), and the CPSR */

	add		r0, sp, #(4*REG_SP)		/* Offset to pc, cpsr storage */
	stmia		r0, {r1-r4}

#ifdef CONFIG_ARCH_FPU
	/* Save the state of the floating point registers. */

	add		r0, sp, #(4*REG_S0)		/* R1=Address of FP register storage */
	savefpu		r0, r1
#endif

	/* Then call the prefetch abort handler with interrupts disabled.
	 * void arm_prefetchabort(struct xcptcontext *xcp)
	 */

	mov		fp, #0				/* Init frame pointer */
	mov		r0, sp				/* Get r0=xcp */
	mrc		CP15_IFAR(r1)			/* Get R1=IFAR */
	mrc		CP15_IFSR(r2)			/* Get r2=IFSR */
	mov		r4, sp				/* Save the SP in a preserved register */
	bic		sp, sp, #7			/* Force 8-byte alignment */
	bl		arm_prefetchabort		/* Call the handler */
	mov		sp, r4				/* Restore the possibly unaligned stack pointer */

#ifdef CONFIG_ARCH_FPU
	/* Restore the state of the floating point registers. */

	add		r1, r0, #(4*REG_S0)		/* R1=Address of FP register storage */
	restorefpu	r1, r2
#endif

	/* Switch back ABT mode and return with shadow SPSR */

	cps		#PSR_MODE_ABT

	/* Upon return from arm_prefetchabort, r0 holds the pointer to the register
	 * state save area to use to restore the registers.  This may or may not
	 * be the same value that was passed to arm_prefetchabort:  It will differ if a
	 * context switch is required.
	 */

	/* Restore the CPSR, ABT mode registers and return */

	ldr		r1, [r0, #(4*REG_CPSR)]		/* Fetch the return SPSR */
	msr		spsr_cxsf, r1			/* Set the return mode SPSR */

	/* Life is simple when everything is ABT mode */

	mov		r14, r0				/* (ABT) r14=Register storage area */
	ldmia		r14!, {r0-r12}			/* Restore common r0-r12 */
	ldmia		r14, {r13, r14}^		/* Restore user mode r13/r14 */
	add		r14, r14, #(4*2)		/* (ABT) r14=address of r15 storage */
	ldmia		r14, {r15}^			/* Return */
	.size	arm_vectorprefetch, . - arm_vectorprefetch

	.align	5

/****************************************************************************
 * Name: arm_vectorundefinsn
 *
 * Description:
 *   Undefined instruction entry exception.  Entered in UND mode, spsr = SVC  CPSR,
 *   lr = SVC PC
 *
 ****************************************************************************/

	.globl	arm_undefinedinsn
	.globl	arm_vectorundefinsn
	.type	arm_vectorundefinsn, %function

arm_vectorundefinsn:
	cpsid		if, #PSR_MODE_SYS		/* Switch to SYS mode */

	/* Create a context structure.  First set aside a stack frame
	 * and store r0-r12 into the frame.
	 */

	sub		sp, sp, #XCPTCONTEXT_SIZE
	stmia		sp, {r0-r12}			/* Save the SYS mode regs */

	cps		#PSR_MODE_UND			/* Switch back UND mode */

	/* Get the values for r15(pc) and CPSR in r3 and r4 */

	mov		r3, lr
	mrs		r4, spsr

	cps		#PSR_MODE_SYS			/* Then switch back to SYS mode */

	/* Get the correct values of USR/SYS r13(sp) and r14(lr) in r1 and r2 */

	add		r1, sp, #XCPTCONTEXT_SIZE
	mov		r2, r14

	/* Save r13(sp), r14(lr), r15(pc), and the CPSR */

	add		r0, sp, #(4*REG_SP)		/* Offset to pc, cpsr storage */
	stmia		r0, {r1-r4}

#ifdef CONFIG_ARCH_FPU
	/* Save the state of the floating point registers. */

	add		r0, sp, #(4*REG_S0)		/* R1=Address of FP register storage */
	savefpu		r0, r1
#endif

	/* Then call the undef insn handler with interrupts disabled.
	 * void arm_undefinedinsn(struct xcptcontext *xcp)
	 */

	mov		fp, #0				/* Init frame pointer */
	mov		r0, sp				/* Get r0=xcp */
	mov		r4, sp				/* Save the SP in a preserved register */
	bic		sp, sp, #7			/* Force 8-byte alignment */
	bl		arm_undefinedinsn		/* Call the handler */
	mov		sp, r4				/* Restore the possibly unaligned stack pointer */

#ifdef CONFIG_ARCH_FPU
	/* Restore the state of the floating point registers. */

	add		r1, r0, #(4*REG_S0)		/* R1=Address of FP register storage */
	restorefpu	r1, r2
#endif

	/* Switch back UND mode and return with shadow SPSR */

	cps		#PSR_MODE_UND

	/* Upon return from arm_undefinedinsn, r0 holds the pointer to the register
	 * state save area to use to restore the registers.  This may or may not
	 * be the same value that was passed to arm_undefinedinsn:  It will differ if a
	 * context switch is required.
	 */

	/* Restore the CPSR, UND mode registers and return */

	ldr		r1, [r0, #(4*REG_CPSR)]		/* Fetch the return SPSR */
	msr		spsr_cxsf, r1			/* Set the return mode SPSR */

	/* Life is simple when everything is UND mode */

	mov		r14, r0				/* (UND) r14=Register storage area */
	ldmia		r14!, {r0-r12}			/* Restore common r0-r12 */
	ldmia		r14, {r13, r14}^		/* Restore user mode r13/r14 */
	add		r14, r14, #(4*2)		/* (UND) r14=address of r15 storage */
	ldmia		r14, {r15}^			/* Return */
	.size	arm_vectorundefinsn, . - arm_vectorundefinsn

	.align	5

/****************************************************************************
 * Name: arm_vectorfiq
 *
 * Description:
 *   Shouldn't happen unless a arm_decodefiq() is provided.  FIQ is primarily used
 *   with the TrustZone feature in order to handle secure interrupts.
 *
 ****************************************************************************/

#ifdef CONFIG_ARMV7A_DECODEFIQ
	.globl	arm_decodefiq
#endif
	.globl	arm_vectorfiq
	.type	arm_vectorfiq, %function

arm_vectorfiq:
#ifdef CONFIG_ARMV7A_DECODEFIQ
	cpsid		if, #PSR_MODE_SYS		/* Switch to SYS mode */

	/* Create a context structure.  First set aside a stack frame
	 * and store r0-r12 into the frame.
	 */

	sub		sp, sp, #XCPTCONTEXT_SIZE
	stmia		sp, {r0-r12}			/* Save the SYS mode regs */

	cps		#PSR_MODE_FIQ			/* Switch back FIQ mode */

	/* Get the values for r15(pc) and CPSR in r3 and r4 */

	sub		r3, lr, #4
	mrs		r4, spsr

	cps		#PSR_MODE_SYS			/* Then switch back to SYS mode */

	/* Get the correct values of USR/SYS r13(sp) and r14(lr) in r1 and r2 */

	add		r1, sp, #XCPTCONTEXT_SIZE
	mov		r2, r14

	/* Save r13(sp), r14(lr), r15(pc), and the CPSR */

	add		r0, sp, #(4*REG_SP)		/* Offset to pc, cpsr storage */
	stmia		r0, {r1-r4}

#ifdef CONFIG_ARCH_FPU
	/* Save the state of the floating point registers. */

	add		r0, sp, #(4*REG_S0)		/* R1=Address of FP register storage */
	savefpu		r0, r1
#endif

	/* Then call the FIQ handler with interrupts disabled. */

	mov		fp, #0				/* Init frame pointer */
	mov		r0, sp				/* Get r0=xcp */

#if CONFIG_ARCH_INTERRUPTSTACK > 7
	/* Call arm_decodefiq() on the interrupt stack */

	setfiqstack	r1, r4				/* SP = interrupt stack top */
	str		r0, [sp, #-4]!			/* Save the xcp address at SP-4 then update SP */
	mov		r4, sp				/* Save the SP in a preserved register */
	bic		sp, sp, #7			/* Force 8-byte alignment */
	bl		arm_decodefiq			/* Call the handler */
	ldr		sp, [r4]			/* Restore the user stack pointer */
#else
	/* Call arm_decodefiq() on the user stack */

	mov		r4, sp				/* Save the SP in a preserved register */
	bic		sp, sp, #7			/* Force 8-byte alignment */
	bl		arm_decodefiq			/* Call the handler */
	mov		sp, r4				/* Restore the possibly unaligned stack pointer */
#endif

#ifdef CONFIG_ARCH_FPU
	/* Restore the state of the floating point registers. */

	add		r1, r0, #(4*REG_S0)		/* R1=Address of FP register storage */
	restorefpu	r1, r2
#endif

	/* Switch back FIQ mode and return with shadow SPSR */

	cps		#PSR_MODE_FIQ

	/* Upon return from arm_decodefiq, r0 holds the pointer to the register
	 * state save area to use to restore the registers.  This may or may not
	 * be the same value that was passed to arm_decodefiq:  It will differ if a
	 * context switch is required.
	 */

	/* Restore the CPSR, FIQ mode registers and return */

	ldr		r1, [r0, #(4*REG_CPSR)]		/* Fetch the return SPSR */
	msr		spsr_cxsf, r1			/* Set the return mode SPSR */

	/* Life is simple when everything is FIQ mode */

	mov		r14, r0				/* (FIQ) r14=Register storage area */
	ldmia		r14!, {r0-r7}			/* Restore common r0-r7 */
	ldmia		r14, {r8-r14}^			/* Restore user mode r8-r14 */
	add		r14, r14, #(4*7)		/* (FIQ) r14=address of r15 storage */
	ldmia		r14, {r15}^			/* Return */

#if !defined(CONFIG_SMP) && CONFIG_ARCH_INTERRUPTSTACK > 7
.Lfiqstacktop:
	.word	g_fiqstacktop
#endif

#else
	subs	pc, lr, #4
#endif
	.size	arm_vectorfiq, . - arm_vectorfiq

/****************************************************************************
 *  Name: g_intstackalloc/g_intstacktop
 ****************************************************************************/

#if !defined(CONFIG_SMP) && CONFIG_ARCH_INTERRUPTSTACK > 7
	.bss
	.balign	8

	.globl	g_intstackalloc
	.type	g_intstackalloc, object
	.globl	g_intstacktop
	.type	g_intstacktop, object

g_intstackalloc:
	.skip	((CONFIG_ARCH_INTERRUPTSTACK + 4) & ~7)
g_intstacktop:
	.size	g_intstacktop, 0
	.size	g_intstackalloc, (CONFIG_ARCH_INTERRUPTSTACK & ~7)

/****************************************************************************
 *  Name: g_fiqstackalloc/g_fiqstacktop
 ****************************************************************************/

	.globl	g_fiqstackalloc
	.type	g_fiqstackalloc, object
	.globl	g_fiqstacktop
	.type	g_fiqstacktop, object

g_fiqstackalloc:
	.skip	((CONFIG_ARCH_INTERRUPTSTACK + 4) & ~7)
g_fiqstacktop:
	.size	g_fiqstacktop, 0
	.size	g_fiqstackalloc, (CONFIG_ARCH_INTERRUPTSTACK & ~7)

#endif /* !CONFIG_SMP && CONFIG_ARCH_INTERRUPTSTACK > 7 */
	.end
