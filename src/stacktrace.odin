package main

import "base:runtime"
import "core:debug/trace"
import "core:fmt"
import "core:os"
import "core:strings"

MAX_DUMPED_STACK_FRAMES :: #config(MAX_STACK_FRAMES, 100)

panic_with_stack_trace :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	fmt.eprintfln("%s: %s", prefix, message)
	{
		stack := trace.capture_n(MAX_DUMPED_STACK_FRAMES, 2) // skip over this proc and panic itself
		locations, err := trace.resolve(stack)
		if err == nil {
			fmt.eprintfln("stack trace (most recent call last):")
			#reverse for frame in locations {
				if strings.ends_with(frame.file_path, ".odin") {
					fmt.eprintfln(" - %s(...)", frame.procedure)
					fmt.eprintfln("\tin %s:%d:%d", frame.file_path, frame.line, frame.column)
				}
			}
		} else {
			fmt.eprintfln("cannot populate stack trace")
		}
		// why bother cleaning up allocations if we're panicking anyway?
	}
	os.exit(-1)
}
