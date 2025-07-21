all: myprog.sna rainbow_code.tap rainbow_demo.tap

myprog.sna myprog.sld rainbow_code.tap: rainbow.asm
	sjasmplus --sld=myprog.sld --fullpath rainbow.asm

basic.tap: RAINBOW.bas
	zmakebas -a 2000 -n "RAINBOW" -o basic.tap RAINBOW.bas

rainbow_demo.tap: basic.tap rainbow_code.tap
	cat basic.tap rainbow_code.tap > rainbow_demo.tap

clean:
	rm -f *.tap
	rm -f myprog*
	rm -rf .tmp/

.PHONY: all clean