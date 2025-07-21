; Rainbow Effects Processor by Dominic Robinson
; Published as "STAR TIP 1" in Your Sinclair Issue 20, page 55
; Accessed at https://spectrumcomputing.co.uk/page.php?issue_id=241&page=55 on 2025-07-20
; Decompilation by McPhail

; This routine can be relocated by adjusting the "origin", "interrupt_vector_table" and "interrupt_entry_point" variables below
; The interrupt vector table must always start at the beginning of a memory page (i.e. the low byte is zero).
; The interrupt entry point can only be placed at a location where the high and low bytes are equal, e.g. location #FEFE in hex
interrupt_vector_table EQU #bf00
interrupt_entry_point EQU #c0c0
origin EQU #c001
    ASSERT low interrupt_vector_table = 0, Interrupt vector table must start on a new page
    ASSERT high interrupt_entry_point = low interrupt_entry_point, The MSB and LSB of the interrupt entry point must be the same
    DISPLAY "Call the set-up routine at address: ",/A,init
    DISPLAY "POKE the 2-byte address of your attribute table to: ",/A,attribute_pointer
    DISPLAY "POKE the number of pixel lines to be coloured to: ",/A,pixel_lines

    ORG origin

; The "init" function is called first, to set up the interrupts.
; Nothing in the "init" function is time critical, so edit it freely.
; The "attribute_pointer" address and the next one should then be POKEd with a memory location of a list of attribute values for each line.
; Ensure the attribute list does not cross a memory page boundary. The routine will wrap around at the end of a page.
; Finally, POKE a value from 1 - 192 at the "pixel_lines" with the number of pixel lines you want to colour, from the top of the screen.
; To stop the routine, POKE a value beyond 1 - 192 to the "pixel_lines" address.
init:
    ; Disable the interrupt handler and set the address of our interrupt vector table
    di
    ld a, high interrupt_vector_table
    ld i, a

    ; Choose Interrupt Mode 2, so we have control whenever each time the screen refresh starts
    im 2

    ; Create a 257 byte interrupt vector table, containing the address of our interrupt entry point
    ld hl, interrupt_vector_table
    ld a, high interrupt_entry_point
populate_vector_table:
    ld (hl), a
    inc l
    jr nz, populate_vector_table
    inc h
    ld (hl), a

    ; We now set the instruction "JP interrupt_routine" at our interrupt entry point.
    ; At the start of every screen refresh, an interrupt will trigger.
    ; The Spectrum will pick an address from the interrupt vector table and jump to that address.
    ; (We have set things up so all of those addresses are the same, i.e. our interrupt entry point.)
    ; The code at our interrupt entry point will make an immediate jump to our actual screen painting routine.
jp_opcode EQU #c3
    ld a, jp_opcode
    ld (interrupt_entry_point), a
    ld hl, interrupt_routine
    ld (interrupt_entry_point + 1), hl
    xor a
    ld (pixel_lines), a

    ; Re-enable interrupts (we're now in Interrupt Mode 2) and return to the calling routine.
    ei
    ret
; Here ends the "init" function.

; These are the variables which will be POKEd by the user to set up the routine.
pixel_lines:
    db #00
attribute_pointer:
    db #90, #ff

; This is the main painting routine, which is called 50 times per second by the interrupt on screen refresh
; By the time we get here, we have already spect 10 T-states from the jump from the interrupt entry point
interrupt_routine:
    ; Save contents of main registers and shadow registers to the stack
    push af
    push hl
    push de
    push bc
    ex af, af'
    exx
    push af
    push hl
    push de
    push bc
    ; 96 T-states, 106 total

    ; The stack pointer will be (ab)used for colouring the screen, so save the original
    ld (interrupt_exit + 1), sp
    ; 20 T-states, 126 total

    ; Only continue if there is between 1 - 192 (?193???) pixel lines set
    ld a, (pixel_lines)
    dec a
    cp #c0
    jr nc, interrupt_exit
    ; 31 T-states, 157 total

    ; Shadow A will have number of pixel lines
    ; Shadow C will have the same
    ; Shadow DE will have the start of the attributes list
    inc a
    ld c, a
    ld de, (attribute_pointer)
    ; 28 T-states, 185 total

    ; Main HL will have start point for painting
    ; Main DE will have line width
    ; Main A wil have a bit set which will rotate on each colouring cycle. When it is set in bit 0 we are at the start of a new attribute line.
    exx
    ex af, af'
screen_attribute_area EQU #5800
line_width EQU 32
end_of_coloured_area_offset EQU 26
    ld hl, screen_attribute_area - line_width + end_of_coloured_area_offset
    ld de, line_width
    ld a, %00000001
    ; 35 T-states, 220 total

    ; Now we pause for some cycles so the pixel beam is in the right area
    ex af, af'        ; 4
    exx               ; 4
    ld a, #3e         ; 7
set_delay:
    ld b, #0f         ; 7 * 62 = 434
delay:
    djnz delay        ; (14 * 13 + 8) * 62 = 11780
    and #ff           ; 7 * 62 = 434
    inc hl            ; 6 * 62 = 372
    dec a             ; 4 * 62 = 248
    jp nz, set_delay  ; 10 * 62 = 620
    nop               ; 4
    nop               ; 4
    ; 13911 T-states, 14131 total

; On a 48K Spectrum, there are 224 T-states/scanline, 312 scanlines/frame and 64 scanlines before picture (14336)
; On a 128K Spectrum, there are 228 T-states/scanline, 311 scanlines/frame and 63 scanlines before picture (14364)
paint:
    ld a, (de)
    inc e
    exx
    ld c, a
    ex af, af'
    ; Remember a single bit is set in A at this point.
    ; This will count 8 pixel lines = 1 attribute block line,
    rrca
    ; 27 T-states, 14158 total

    jp nc, continue_block
    ; we are at the top line of an attribute block
    add hl, de
    jp colour_line
    ; 31 T-states if this path is taken, 14189 total

; This path just wastes a few cycles doing busywork to keep everything in sync
continue_block:
    ld b, (hl)
    ld b, (hl)
    ld b, (hl)
    ; 31 T-states if this path is taken, 14189 total

; Finally we set the stack pointer to the end of the attribute line we are going to colour,
; and set them tight-to-left by throwing 2-byte words onto the stack (which grows down in memory).
; If we've got the timing right, we'll set the colour just as the beam goes by and can change it
; again before the beam gets to the next line.
colour_line:
    ; C contains the attribute, so make B the same so we can set 2 bytes at a time.
    ld b, c
    ; Stack pointer to end of the coloured section of the attribute block line.
    ld sp, hl
    ; 10 T-states, 14199 total

    ; Paint the block.
    push bc
    push bc
    push bc
    push bc
    push bc
    push bc
    push bc
    push bc
    push bc
    push bc
    ; 110 T-states, 14309 total

    ; Allow the scanline to finish and circle around for the next one.
    nop
    nop
    nop
    exx
    ex af, af'
    dec c
    jp nz, paint
    ; 34 T-states
    ; 212 T-states total for this routine

; Tidy up all the registers and reset the stack pointer
interrupt_exit:
    ld sp, #7fe4
    pop bc
    pop de
    pop hl
    pop af
    ex af, af'
    exx
    pop bc
    pop de
    pop hl
    pop af

    ; process normal ROM interrupts
    jp #0038

; This is just an example program to help with debugging.
; It will not end up in the final TAP file.
start:
    call init
    ld de, attrs
    ld (attribute_pointer), de
    ld a, 16
    ld (pixel_lines), a
.wait:
    jr .wait

attrs:
    db 0, 16, 78, 34, 0, 20, 45, 99
    db 0, 8, 16, 24, 32, 40, 48, 0

    DEVICE ZXSPECTRUM48
    SLDOPT COMMENT WPMEM, LOGPOINT, ASSERTION
    SAVESNA "myprog.sna", start

    EMPTYTAP "rainbow_code.tap"
    SAVETAP "rainbow_code.tap", CODE, "democode", origin, 146