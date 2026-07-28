# Kerrek

An experimental new programming language that checks your assumptions

# Language Design Philosophy

The goal of Kerrek is to be a pragmatic balance of features that prioritizes correctness, runtime speed, compilation speed, and encoding programmer intent, all within a data-oriented and procedural paradigm.

Locality is a big aspect of the design. You shouldn't need to analyze the call graph or do other forms of whole-program analysis to be able to understand how everything fits together or which assumptions hold. You should be able to look at any function in isolation and grok its assumptions.

## Correctness and Performance: make the 95% use cases easy to get right

Kerrek is not on a mission to squash every possible instance of every bug or entire classes of bugs. It's mathematically impossible to guarantee any nontrivial property about a program, be it memory safety or anything else.

Rather, the goal is provide tools that allow you to encode your assumptions and intent in ways that the compiler can reason about quickly and locally, all with the goal of allowing you to write fast code that you can be reasonably confident is correct. Provide tools that are *good enough* with *low overhead* instead of promising big things like zero-cost abstractions (there is no such thing) or absolute memory safety.

Kerrek is not going to prevent every bug, but I hope to make it easier to write code that is both correct and performant. This language and its runtime aren't going to be as fast as the optimally produced C program and it isn't trying to be. It just wants to help you not trip over yourself and your team.

## Immutability and encapsulation are incomplete attempts at solving the same problem

In many programs, it's unclear when data can be mutated. It's an implicit understanding that probably lives in one engineer's brain or some comment tucked away in a class definition. So programmers are just defensive about it instead. Immutability. Encapsulation. Defensive copies. All because nobody is sure when it's appropriate to mutate data. And we make computers work harder than they really need to copying objects all the time. Frameworks create convoluted "functional" mazes that pretend data doesn't change, when really they're secretly inventing a system of carefully scoped mutation.

Encapsulation tries to hide that a different way by using getters and setters, but really all that enables is ensuring variants are maintained, all at the cost of awkward method calls or property accessors that hide control flow. You can still call setters at any time, even when it might actually be invalid to do so

Why not dispense with all that ceremony and provide information to the compiler about when it is valid to mutate certain values?

## A new language? Now? In the age of agentic coding?

I know people have gotten it in their head that we don't need new programming languages anymore because LLMs have "solved programming" or some nonsense like that. They think that English is the hot new programming language. I have a whole rant why that doesn't entirely work, but I'll set it aside and acknowlege that this language has to offer something of value to AI-augmented coding to have any chance at success and adoption.

While it's not one of my primary goals per se, much of what this language does would be beneficial to agentic coding because it allows you to state and verify your assumptions around when data can be mutated and accessed, when functions can be called, and other little things which help to ensure your code is correct. And it does so with the intent of being *fast* by ensuring algorithmic complexity of static checks is linear. That matters a lot for iteration speed.

## Couldn't a lot of this be a linter?

Probably. You could encode these assumptions in comments and check them in much the same way. This may, in fact, be a possible future for Kerrek. I don't know yet, and it's something I will gladly entertain.

# Status / Roadmap

This compiler is in the early stages of experimentation and finding an identity.

## STAGE 0: Proof of Concept - written in Python, compiles to C99

For the time being, I just want to prove out the concept of the language, so the goal is just to get a working compiler that parses Kerrek code and outputs C99 code.

The compiler will eventually be written in a compiled language, but it isn't clear to me right now whether I'll bootstrap ASAP or use C or modern C++. I just want to test out my ideas in a language I'm comfortable using. Go would have been another acceptable option for an implementation language, but I don't think it would be the final language- eventually the Kerrek compiler will be written in Kerrek.

The C99 backend will always be a thing however, as it helps to ensure trust by being able to start with a known safe compiler and verifiable source code (though it will be ugly generated code) and bootstrap from there.
