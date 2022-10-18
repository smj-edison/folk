TCL_HOME := /opt/homebrew/Cellar/tcl-tk/8.6*
ifeq ($(wildcard $(TCL_HOME)/*),)
	TCL_HOME := /usr/local/Cellar/tcl-tk/8.6*
endif
ifeq ($(wildcard $(TCL_HOME)/*),)
	TCL_HOME := /usr
endif
start:
	$(TCL_HOME)/bin/tclsh main.tcl
stop:
	killall -9 tclsh || true
	while pgrep tclsh >/dev/null; do sleep 0.1; done
restart: stop start

TCLKIT = ~/Downloads/tclkit-8.6.3*
Folk.app:
	rm -r /tmp/folk.vfs; mkdir /tmp/folk.vfs
	cp -r * /tmp/folk.vfs
	cd /tmp; tclsh ~/Downloads/sdx*kit wrap folk -runtime $(TCLKIT)

NODE := localhost
show-statements:
	echo Statements::showGraph | nc -w 5 $(NODE) 4273
show-trie:
	echo 'trie dot [set Statements::statementClauseToId]' | nc -w 5 $(NODE) 4273 | dot -Tpdf > trie.pdf

assert-tags:
	echo 'set ::debug true; Assert camera claims tag 1 has center {400 400} size {100} with generation 0; Assert camera claims tag 2 has center {200 200} size {100} with generation 0; Step; set ::debug false; set ::stepTime' | nc -w1 folk0.local 4273
retract-tags:
	echo 'Retract camera claims tag 1 has center {400 400} size {100} with generation 0; Retract camera claims tag 2 has center {200 200} size {100} with generation 0; Step; set ::stepTime' | nc -w1 folk0.local 4273
