package require Thread

namespace eval Display {
    variable displayThread [thread::create {
        source pi/Display.tcl
        Display::init

        thread::wait
    }]
    puts "dt $displayThread"

    variable displayList [list]

    proc fillRect {fb x0 y0 x1 y1 color} {
        lappend Display::displayList [list Display::fillRect $fb $x0 $y0 $x1 $y1 $color]
    }

    proc stroke {points width color} {
        lappend Display::displayList [list Display::stroke $points $width $color]
    }

    proc text {fb x y fontSize text} {
        lappend Display::displayList [list Display::text $fb $x $y $fontSize $text]
    }

    proc commit {} {
        thread::send -async $Display::displayThread [format {
            # Draw the display list
            %s
            # (slow, should be abortable by newcomer commits)

            commitThenClearStaging
        } [join $Display::displayList "\n"]]
        
        # Make a new display list
        set Display::displayList [list]
    }
}

# Camera thread
set cameraThread [thread::create [format {
    source pi/Camera.tcl
    Camera::init
    AprilTags::init

    while true {
        set frame [Camera::frame]

        set commands [list "Retract camera claims the camera frame is /something/" \
                          "Assert camera claims the camera frame is \"$frame\"" \
                          "Retract camera claims tag /something/ has center /something/ size /something/"]

        set grayFrame [yuyv2gray $frame $Camera::WIDTH $Camera::HEIGHT]
        set tags [AprilTags::detect $grayFrame]
        freeGray $grayFrame

        foreach tag $tags {
            lappend commands "Assert camera claims tag [dict get $tag id] has center {[dict get $tag center]} size [dict get $tag size]"
        }

        # lappend commands "Step {}"

        # send this script back to the main Folk thread
        thread::send -async "%s" [join $commands "\n"]
    }
} [thread::id]]]
puts "ct $cameraThread"

set keyboardThread [thread::create [format {
    source pi/Keyboard.tcl
    Keyboard::init

    set chs [list]
    while true {
        lappend chs [Keyboard::getChar]

        thread::send -async "%s" [subst {
            Retract keyboard claims the keyboard character log is /something/
            Assert keyboard claims the keyboard character log is "$chs"
        }]
    }
} [thread::id]]]
puts "kt $keyboardThread"

proc every {ms body} {
    try $body
    after $ms [list after idle [namespace code [info level 0]]]
}
every 32 {Step {}}
