# Kerrek
An experimental new programming language that checks your assumptions

# Roadmap

## STAGE 0: Proof of Concept - written in Python, compiles to C99

For the time being, I just want to prove out the concept of the language, so the goal is just to get a working compiler that parses Kerrek code and outputs C99 code.

The compiler will eventually be written in a compiled language, but it isn't clear to me right now whether I'll bootstrap ASAP or use C or modern C++. I just want to test out my ideas in a language I'm comfortable using. Go would have been another acceptable option for me, but I don't think it would be the final language anyway.

The C99 backend will always be a thing, as it helps to ensure trust by being able to start with a known safe compiler and verifiable source code (though it will be ugly generated code) and bootstrap from there.
