catch {
    package require starkit
    starkit::startup
}

namespace eval MatchCache {
    variable cache [dict create] ;# Dict<Pattern, List<StatementId>>
    proc set {pattern ids} {
        # Called whenever a manual match was carried out,
        # to cache the result.
        variable cache
        dict set cache $pattern $ids
    }
    proc add {clause id} {
        # Called whenever a new statement is added.
        # Check if that statement matches any existing cached relations.
        # TODO: Can we do efficient relation-matching?
        variable cache
        dict for {pattern _} $cache {
            if {[Statements::unify $pattern $clause] != false} {
                dict lappend cache $pattern $id
            }
        }
    }
    proc uncache {pattern id} {
        
    }

    proc exists {pattern} { variable cache; return [dict exists $cache $pattern] }
    proc get {pattern} { variable cache; return [dict get $cache $pattern] }
}

namespace eval Statements { ;# singleton Statement store
    variable statements [dict create] ;# Dict<StatementId, Statement>
    variable nextStatementId 1
    proc reset {} {
        variable statements
        variable nextStatementId
        set statements [dict create]
        set nextStatementId 1
    }

    proc add {clause {parents {}}} {
        # empty set of parents = an assertion
        # returns {statement-id set-of-parents-id}

        variable statements
        variable nextStatementId

        # is this clause already present in the existing statement set?
        set matches [findMatches $clause]
        if {[llength $matches] == 1} {
            set id [dict get [lindex $matches 0] __matcheeId]
            dict with statements $id {
                set newSetOfParentsId [expr {[lindex $setsOfParents end-1] + 1}]
                dict set setsOfParents $newSetOfParentsId $parents
                return [list $id $newSetOfParentsId]
            }

        } elseif {[llength $matches] == 0} {
            set id [incr nextStatementId]
            set stmt [statement create $clause [dict create 0 $parents]]
            dict set statements $id $stmt

            MatchCache::add $clause $id

            return [list $id 0]

        } else {
            # there are somehow multiple existing matches. this seems bad
            puts BAD
        }
    }
    proc exists {id} { variable statements; return [dict exists $statements $id] }
    proc get {id} { variable statements; return [dict get $statements $id] }
    proc remove {id} { variable statements; dict unset statements $id }
    proc size {} { variable statements; return [dict size $statements] }
    proc countSetsOfParents {} {
        variable statements
        set count 0
        dict for {_ stmt} $statements {
            set count [expr { $count + [dict size [statement setsOfParents $stmt]] }]
        }
        return $count
    }
    
    proc unify {a b} {
        if {[llength $a] != [llength $b]} { return false }

        set match [dict create]
        for {set i 0} {$i < [llength $a]} {incr i} {
            set aWord [lindex $a $i]
            set bWord [lindex $b $i]
            if {[regexp {^/([^/]+)/$} $aWord -> aVarName]} {
                dict set match $aVarName $bWord
            } elseif {[regexp {^/([^/]+)/$} $bWord -> bVarName]} {
                dict set match $bVarName $aWord
            } elseif {$aWord != $bWord} {
                return false
            }
        }
        return $match
    }
    proc findMatches {pattern} {
        variable statements
        # Returns a list of bindings like {{name Bob age 27 __matcheeId 6} {name Omar age 28 __matcheeId 7}}

        if {[MatchCache::exists $pattern]} { return MatchCache::get $pattern }

        set matches [list]
        dict for {id stmt} $statements {
            set match [unify $pattern [statement clause $stmt]]
            if {$match != false} {
                dict set match __matcheeId $id
                lappend matches $match
            }
        }

        MatchCache::set $pattern $matches
        return $matches
    }

    proc graph {} {
        variable statements
        set dot [list]
        dict for {id stmt} $statements {
            lappend dot "subgraph cluster_$id {"
            lappend dot "color=lightgray;"

            set label [string map {"\"" "\\\""} [statement clause $stmt]]
            lappend dot "$id \[label=\"$id: $label\"\];"

            dict for {setOfParentsId parents} [statement setsOfParents $stmt] {
                lappend dot "\"$id $setOfParentsId\" \[label=\"$id#$setOfParentsId: $parents\"\];"
                lappend dot "\"$id $setOfParentsId\" -> $id;"
            }

            lappend dot "}"
            dict for {child _} [statement children $stmt] {
                lappend dot "$id -> \"$child\";"
            }
        }
        return "digraph { rankdir=LR; [join $dot "\n"] }"
    }
    proc showGraph {} {
        set fp [open "statements.dot" "w"]
        puts -nonewline $fp [graph]
        close $fp
        exec dot -Tpdf statements.dot > statements.pdf
    }
    proc openGraph {} {
        exec open statements.pdf
    }
}

namespace eval statement { ;# statement record type
    namespace export create
    proc create {clause {setsOfParents {}} {children {}}} {
        # clause = [list the fox is out]
        # parents = [dict create 0 [list 2 7] 1 [list 8 5]]
        # children = [dict create [list 9 0] true]
        return [dict create \
                    clause $clause \
                    setsOfParents $setsOfParents \
                    children $children]
    }

    namespace export clause setsOfParents children
    proc clause {stmt} { return [dict get $stmt clause] }
    proc setsOfParents {stmt} { return [dict get $stmt setsOfParents] }
    proc children {stmt} { return [dict get $stmt children] }

    namespace ensemble create
}

set ::log [list]

# invoke at top level, add/remove independent 'axioms' for the system
proc Assert {args} {lappend ::log [list Assert $args]}
proc Retract {args} {lappend ::log [list Retract $args]}

# invoke from within a When context, add dependent statements
proc Say {args} {
    upvar __matcherId matcherId
    upvar __matcheeId matcheeId
    set ::log [linsert $::log 0 [list Say [list $matcherId $matcheeId] $args]]
}
proc Claim {args} { uplevel [list Say someone claims {*}$args] }
proc Wish {args} { uplevel [list Say someone wishes {*}$args] }
proc When {args} {
    set env [uplevel {
        set ___env $__env ;# inherit existing environment

        # get local variables and serialize them
        # (to fake lexical scope)
        foreach localName [info locals] {
            if {![string match "__*" $localName]} {
                dict set ___env $localName [set $localName]
            }
        }
        set ___env
    }]
    uplevel [list Say when {*}$args with environment $env]
}

proc StepImpl {} {
    # should this do reduction of assert/retract ?

    proc runWhen {__env __body} {
        dict with __env $__body
    }

    proc reactToStatementAddition {id} {
        set clause [statement clause [Statements::get $id]]
        if {[lindex $clause 0] == "when"} {
            # is this a When? match it against existing statements
            # when the time is /t/ { ... } with environment /env/ -> the time is /t/
            set unwhenizedClause [lreplace [lreplace $clause end-3 end] 0 0]
            set matches [concat [Statements::findMatches $unwhenizedClause] \
                             [Statements::findMatches [list /someone/ claims {*}$unwhenizedClause]]]
            set body [lindex $clause end-3]
            set env [lindex $clause end]
            foreach match $matches {
                set __env [dict merge \
                               $env \
                               $match \
                               [dict create __matcherId $id]]
                runWhen $__env $body
            }

        } else {
            # is this a statement? match it against existing whens
            # the time is 3 -> when the time is 3 /__body/ with environment /__env/
            proc whenize {clause} { return [list when {*}$clause /__body/ with environment /__env/] }
            set matches [Statements::findMatches [whenize $clause]]
            if {[Statements::unify [lrange $clause 0 1] [list /someone/ claims]] != false} {
                # Omar claims the time is 3 -> when the time is 3 /__body/ with environment /__env/
                lappend matches {*}[Statements::findMatches [whenize [lrange $clause 2 end]]]
            }
            foreach match $matches {
                set __env [dict merge \
                               [dict get $match __env] \
                               $match \
                               [dict create __matcherId $id]]
                runWhen $__env [dict get $match __body]
            }
        }
    }
    proc reactToStatementRemoval {id} {
        # unset all things downstream of statement
        set children [statement children [Statements::get $id]]
        dict for {child _} $children {
            lassign $child childId childSetOfParentsId
            if {![Statements::exists $childId]} { continue } ;# if was removed earlier
            set childSetsOfParents [statement setsOfParents [Statements::get $childId]]
            set parentsInSameSet [dict get $childSetsOfParents $childSetOfParentsId]

            # this set of parents will be dead, so remove the set from
            # the other parents in the set
            foreach parentId $parentsInSameSet {
                dict with Statements::statements $parentId {
                    dict unset children $child
                }
            }

            dict with Statements::statements $childId {
                dict unset setsOfParents $childSetOfParentsId

                # is this child out of parent sets? => it's dead
                if {[dict size $setsOfParents] == 0} {
                    reactToStatementRemoval $childId
                    Statements::remove $childId
                }
            }
        }
    }

    # puts ""
    # puts "Step:"
    # puts "-----"

    # puts "Now processing log: $::log"
    while {[llength $::log]} {
        # TODO: make this log-shift more efficient?
        set entry [lindex $::log 0]
        set ::log [lreplace $::log 0 0]

        set op [lindex $entry 0]
        # puts "$op: [string map {\n { }} [string range $entry 0 100]]"
        if {$op == "Assert"} {
            set clause [lindex $entry 1]
            # insert empty environment if not present
            if {[lindex $clause 0] == "when" && [lrange $clause end-2 end-1] != "with environment"} {
                set clause [list {*}$clause with environment {}]
            }
            lassign [Statements::add $clause] id ;# statement without parents
            reactToStatementAddition $id

        } elseif {$op == "Retract"} {
            set clause [lindex $entry 1]
            foreach bindings [Statements::findMatches $clause] {
                set id [dict get $bindings __matcheeId]
                reactToStatementRemoval $id
                Statements::remove $id
            }

        } elseif {$op == "Say"} {
            set parents [lindex $entry 1]
            set clause [lindex $entry 2]
            lassign [Statements::add $clause $parents] id setOfParentsId
            # list this statement as a child under each of its parents
            foreach parentId $parents {
                dict with Statements::statements $parentId {
                    dict set children [list $id $setOfParentsId] true
                }
            }
            reactToStatementAddition $id
        }
    }

    if {[namespace exists Display]} {
        Display::commit ;# TODO: this is weird, not right level
    }
}

set ::acceptNum 0
proc accept {chan addr port} {
    puts "$::nodename: Start [incr ::acceptNum]"
    
    # (mostly for the Pi)
    # we want to be able to asynchronously receive statements
    set script ""
    try {
        while {[gets $chan line] != -1} {
            append script $line\n
            if {[info complete $script]} {
                puts "$::nodename: Recv"
                if {[catch {
                    puts $chan [eval $script]; flush $chan
                } ret]} {
                    catch {
                        puts "$::nodename: Error on receipt: $ret" ;# "broken pipe"
                        puts $chan $ret; flush $chan
                    }
                }
                set script ""
            }
        }
    } finally {
        puts "$::nodename: Done $::acceptNum"
        close $chan
    }
}
set ::nodename [info hostname]
if {[catch {socket -server accept 4273}]} {
    set ::nodename "[info hostname]-1"
    puts "$::nodename: Note: There's already a Folk node running on this machine."
    socket -server accept 4274
}

set ::stepCount 0
set ::stepTime "none"
proc Step {} {
    # puts "$::nodename: Step"

    Retract $::nodename has step count $::stepCount
    incr ::stepCount
    Assert $::nodename has step count $::stepCount
    set ::stepTime [time {StepImpl}]
}

source "lib/math.tcl"

# this defines $this in the contained scopes
Assert when /this/ has program code /code/ {
    if {[catch $code err] == 1} {
        puts "$::nodename: Error in $this: $err"
    }
}

if {$tcl_platform(os) eq "Darwin"} {
    if {$tcl_version eq 8.5} {
        error "Don't use Tcl 8.5 / macOS system Tcl. Quitting."
    }
}

if {[info exists ::env(FOLK_ENTRY)]} {
    set entry $::env(FOLK_ENTRY)

} elseif {$tcl_platform(os) eq "Darwin"} {
    #     if {[catch {source [file join $::starkit::topdir laptop.tcl]}]} 
    set entry "laptop.tcl"

} else {
    set entry "pi/pi.tcl"
}

source $entry
