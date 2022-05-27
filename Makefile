# Makefile generated by BNFC.

GHC        = ghc
GHC_OPTS   = -package mtl -O3
HAPPY      = happy
HAPPY_OPTS = --array --info --ghc --coerce
ALEX       = alex
ALEX_OPTS  = --ghc



# List of goals not corresponding to file names.

.PHONY : all clean distclean

# Default goal.

all : TestCTT

%.hs : %.y
	${HAPPY} ${HAPPY_OPTS} $<

%.hs : %.x
	${ALEX} ${ALEX_OPTS} $<

TestCTT : CoreCTT.hs LexCTT.hs ParCTT.hs TestCTT.hs TypeChecker.hs Eval.hs Interval.hs Ident.hs
	${GHC} ${GHC_OPTS} $@

# Rules for cleaning generated files.

clean :
	-rm -f *.hi *.o *.log *.aux *.dvi TestCTT

distclean : clean
	-rm -f CoreCTT.hs CoreCTT.hs.bak ComposOp.hs ComposOp.hs.bak DocCTT.txt DocCTT.txt.bak ErrM.hs ErrM.hs.bak LayoutCTT.hs LayoutCTT.hs.bak LexCTT.x LexCTT.x.bak ParCTT.y ParCTT.y.bak PrintCTT.hs PrintCTT.hs.bak SkelCTT.hs SkelCTT.hs.bak TestCTT.hs TestCTT.hs.bak XMLCTT.hs XMLCTT.hs.bak ASTCTT.agda ASTCTT.agda.bak ParserCTT.agda ParserCTT.agda.bak IOLib.agda IOLib.agda.bak Main.agda Main.agda.bak CTT.dtd CTT.dtd.bak TestCTT LexCTT.hs ParCTT.hs ParCTT.info ParDataCTT.hs Makefile


# EOF
