namespace eval c {
    variable prelude {
        #include <tcl.h>
        #include <inttypes.h>
        #include <stdint.h>
    }
    variable code [list]
    variable procs [dict create]

    variable argtypes {
        int { expr {{ Tcl_GetIntFromObj(interp, $obj, &$argname); }}}
        Tcl_Obj* { expr {{ $argname = $obj; }}}
        default {
            if {[string index $argtype end] == "*"} {
                expr {{ sscanf(Tcl_GetString($obj), "($argtype) 0x%p", &$argname); }}
            } else {
                error "Unrecognized argtype $argtype"
            }
        }
    }
    ::proc argtype {t h} { variable argtypes; linsert argtypes 0 $t [subst {expr {{$h}}}] }

    variable rtypes {
        int { expr {{
            Tcl_SetObjResult(interp, Tcl_NewIntObj(rv));
            return TCL_OK;
        }}}
        Tcl_Obj* { expr {{
            Tcl_SetObjResult(interp, rv);
            return TCL_OK;
        }}}
        default {
            if {[string index $rtype end] == "*"} {
                expr {{
                    Tcl_SetObjResult(interp, Tcl_ObjPrintf("($rtype) 0x%" PRIxPTR, (uintptr_t) rv));
                    return TCL_OK;
                }}
            } else {
                error "Unrecognized rtype $rtype"
            }
        }
    }
    ::proc rtype {t h} { variable rtypes; linsert rtypes 0 $t [subst {expr {{$h}}}] }

    ::proc include {h} {
        variable code
        lappend code "#include $h"
    }
    ::proc code {newcode} { variable code; lappend code $newcode }
    ::proc struct {type fields} {
        variable code
        lappend code [subst {
            typedef struct $type $type;
            struct $type {
                $fields
            };
        }]
    }

    ::proc "proc" {name args rtype body} {
        # puts "$name $args $rtype $body"
        variable argtypes
        variable rtypes

        set arglist [list]
        set argnames [list]
        set loadargs [list]
        for {set i 0} {$i < [llength $args]} {incr i 2} {
            set argtype [lindex $args $i]
            set argname [lindex $args [expr {$i+1}]]
            lappend arglist "$argtype $argname"
            lappend argnames $argname

            if {$argtype == "Tcl_Interp*" && $argname == "interp"} { continue }

            set obj [subst {objv\[1 + [llength $loadargs]\]}]
            lappend loadargs [subst {
                $argtype $argname;
                [subst [switch $argtype $argtypes]]
            }]
        }
        if {$rtype == "void"} {
            set saverv [subst {
                $name ([join $argnames ", "]);
                return TCL_OK;
            }]
        } else {
            set saverv [subst {
                $rtype rv = $name ([join $argnames ", "]);
                [subst [switch $rtype $rtypes]]
            }]
        }
        
        set uniquename [string map {":" "_"} [uplevel [list namespace current]]]__$name
        variable procs
        dict set procs $name [subst {
            static $rtype $name ([join $arglist ", "]) {
                $body
            }

            static int [set name]_Cmd(ClientData cdata, Tcl_Interp* interp, int objc, Tcl_Obj* const objv\[]) {
                if (objc != 1 + [llength $loadargs]) {
                    Tcl_SetResult(interp, "Wrong number of arguments to $name", NULL);
                    return TCL_ERROR;
                }
                [join $loadargs "\n"]
                $saverv
            }
        }]
    }

    variable cflags [ switch $tcl_platform(os) {
        Darwin { expr { [file exists "$::tcl_library/../../Tcl"] ?
                        [list -I$::tcl_library/../../Headers $::tcl_library/../../Tcl] :
                        [list -I$::tcl_library/../../include $::tcl_library/../libtcl8.6.dylib]
                    } }
        Linux { list -I/usr/include/tcl8.6 -ltcl8.6 }
    } ]
    ::proc cflags {args} { variable cflags; lappend cflags {*}$args }
    ::proc compile {} {
        variable prelude
        variable code
        variable procs
        variable cflags

        set init [subst {
            int Cfile_Init(Tcl_Interp* interp) {
                [join [lmap name [dict keys $procs] { subst {
                    Tcl_CreateObjCommand(interp, "[uplevel [list namespace current]]::$name", [set name]_Cmd, NULL, NULL);
                }}] "\n"]
                return TCL_OK;
            }
        }]
        set sourcecode [join [list \
                                  $prelude \
                                  {*}$code \
                                  {*}[dict values $procs] \
                                  $init \
                                 ] "\n"]

        # puts "=====================\n$sourcecode\n====================="

        set cfd [file tempfile cfile cfile.c]; puts $cfd $sourcecode; close $cfd
        exec cc -Wall -g -shared -fPIC {*}$cflags $cfile -o [file rootname $cfile][info sharedlibextension]
        load [file rootname $cfile][info sharedlibextension] cfile

        set code [list]
        set procs [dict create]
    }

    namespace export *
    namespace ensemble create
}

# FIXME: legacy critcl stuff below:

if {![info exists ::livecprocs]} {set ::livecprocs [dict create]}
proc livecproc {name args} {
    if {[dict exists $::livecprocs $name $args]} {
        # promote this proc
        dict set ::livecprocs $name [dict create $args [dict get $::livecprocs $name $args]]
    } else { ;# compile
        critcl::cproc $name$::stepCount {*}$args
        dict set ::livecprocs $name $args $name$::stepCount
    }
    proc $name {args} {
        set name [lindex [info level 0] 0]
        [lindex [dict values [dict get $::livecprocs $name]] end] {*}$args
    }
}
