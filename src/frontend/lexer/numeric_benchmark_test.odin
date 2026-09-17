#+test
package lexer

import "core:fmt"
import "core:slice"
import "core:testing"
import "core:time"


RUN_NUMERIC_BENCHMARKS :: #config(RUN_NUMERIC_BENCHMARKS, false)
NUMERIC_BENCHMARK_ROUNDS :: #config(NUMERIC_BENCHMARK_ROUNDS, 100_000)
NUMERIC_BENCHMARK_SAMPLES :: 9

@(rodata)
NUMERIC_INTEGER_BENCHMARK_CORPUS := [?]string {
	"0",
	"42 ",
	"000_001;",
	"1_000_000tail",
	"123456789012345678🙂",
	"0xdead_BEEF)",
	"0x0123_4567_89ab_cdef\n",
	"0o7_654_321octal",
	"0b1010_1100_1111_0000_name",
}

@(rodata)
NUMERIC_MIXED_BENCHMARK_CORPUS := [?]string {
	"0",
	"1_000_000 ",
	"0xdead_BEEF;",
	"0o7_654_321octal",
	"0b1010_1100_1111_0000🔥",
	"12.50e-1?",
	"1_2.5_0e-1_0units",
	"0.001_20\n",
	"1e1_0)",
	"0x1.8p1turns",
	"0x1.a_bp+1_0]",
	"0x0.08p0",
}

@(rodata)
NUMERIC_SCANNER_BENCHMARK_CORPUS := [?]string {
	"0",
	"000_001 ",
	"1_000_000;",
	"123456789012345678tail",
	"12.50e-1?",
	"1_2.5_0e-1_0units",
	"0.001_20🙂",
	"1e1_0\n",
	"0xdead_BEEF)",
	"0x0123_4567_89ab_cdef_name",
	"0x1.8p1turns",
	"0x1.a_bp+1_0",
}

Numeric_Benchmark_Result :: struct {
	duration:  time.Duration,
	checksum:  u64,
	calls:     int,
	processed: int,
}

_consume_numeric_benchmark_result :: #force_inline proc(
	checksum: ^u64,
	numeric: Numeric,
	length: int,
) {
	numerator, numerator_inline := numeric.value.numerator.(i128)
	denominator, denominator_inline := numeric.value.denominator.(i128)
	assert(numerator_inline && denominator_inline)

	checksum^ = checksum^ * 1099511628211 ~
	            u64(length) ~
	            u64(numeric.digits) << 8 ~
	            u64(numeric.precision) << 16 ~
	            u64(numeric.format) << 24 ~
	            u64(numerator) ~
	            u64(denominator) << 1
}

_benchmark_numeric_matcher :: proc(
	corpus: []string,
	rounds: int,
) -> Numeric_Benchmark_Result {
	result: Numeric_Benchmark_Result
	watch: time.Stopwatch
	time.stopwatch_start(&watch)
	for _ in 0 ..< rounds {
		for source in corpus {
			numeric, length := _match_numeric({}, source)
			assert(length > 0)
			_consume_numeric_benchmark_result(&result.checksum, numeric, length)
		}
	}
	time.stopwatch_stop(&watch)
	result.duration = time.stopwatch_duration(watch)
	result.calls = rounds * len(corpus)
	for source in corpus {
		result.processed += rounds * len(source)
	}
	return result
}

_consume_numeric_scanner_result :: #force_inline proc(
	checksum: ^u64,
	length: int,
	format: Number_Format,
	ok: bool,
) {
	checksum^ = checksum^ * 1099511628211 ~
	            u64(length) ~
	            u64(format) << 16 ~
	            u64(ok) << 24
}

_benchmark_numeric_scanner :: proc(
	corpus: []string,
	rounds: int,
) -> Numeric_Benchmark_Result {
	result: Numeric_Benchmark_Result
	watch: time.Stopwatch
	time.stopwatch_start(&watch)
	for _ in 0 ..< rounds {
		for source in corpus {
			length, format, ok := _scan_numeric_dfa(source)
			assert(ok && length > 0)
			_consume_numeric_scanner_result(
				&result.checksum,
				length,
				format,
				ok,
			)
		}
	}
	time.stopwatch_stop(&watch)
	result.duration = time.stopwatch_duration(watch)
	result.calls = rounds * len(corpus)
	for source in corpus {
		result.processed += rounds * len(source)
	}
	return result
}

_run_numeric_scanner_benchmark :: proc(corpus: []string) {
	warmup_rounds := max(NUMERIC_BENCHMARK_ROUNDS / 20, 1)
	_ = _benchmark_numeric_scanner(corpus, warmup_rounds)

	samples: [NUMERIC_BENCHMARK_SAMPLES]time.Duration
	reference: Numeric_Benchmark_Result
	for i in 0 ..< NUMERIC_BENCHMARK_SAMPLES {
		result := _benchmark_numeric_scanner(corpus, NUMERIC_BENCHMARK_ROUNDS)
		samples[i] = result.duration
		reference = result
	}

	slice.sort(samples[:])
	median := samples[NUMERIC_BENCHMARK_SAMPLES / 2]
	ns := f64(time.duration_nanoseconds(median)) / f64(reference.calls)
	mib := f64(reference.processed) /
	               (1024 * 1024) /
	               (f64(time.duration_nanoseconds(median)) / 1e9)
	fmt.printfln(
		"scanner  %d calls  %.2f ns/literal %.2f MiB/s",
		reference.calls,
		ns,
		mib,
	)
}

_run_numeric_benchmark_corpus :: proc(
	name: string,
	corpus: []string,
) {
	warmup_rounds := max(NUMERIC_BENCHMARK_ROUNDS / 20, 1)
	_ = _benchmark_numeric_matcher(corpus, warmup_rounds)

	samples: [NUMERIC_BENCHMARK_SAMPLES]time.Duration
	reference: Numeric_Benchmark_Result
	for i in 0 ..< NUMERIC_BENCHMARK_SAMPLES {
		result := _benchmark_numeric_matcher(corpus, NUMERIC_BENCHMARK_ROUNDS)
		samples[i] = result.duration
		reference = result
	}

	slice.sort(samples[:])
	median := samples[NUMERIC_BENCHMARK_SAMPLES / 2]
	ns := f64(time.duration_nanoseconds(median)) / f64(reference.calls)
	mib := f64(reference.processed) /
	               (1024 * 1024) /
	               (f64(time.duration_nanoseconds(median)) / 1e9)

	fmt.printfln(
		"%s %d calls  %.2f ns/literal %.2f MiB/s",
		name,
		reference.calls,
		ns,
		mib,
	)
}

@(test)
benchmark_numeric_matchers :: proc(t: ^testing.T) {
	when !RUN_NUMERIC_BENCHMARKS {
		return
	}

	fmt.printfln(
		"numeric matcher benchmark: %d samples, %d rounds per corpus",
		NUMERIC_BENCHMARK_SAMPLES,
		NUMERIC_BENCHMARK_ROUNDS,
	)
	_run_numeric_scanner_benchmark(NUMERIC_SCANNER_BENCHMARK_CORPUS[:])
	_run_numeric_benchmark_corpus("integers", NUMERIC_INTEGER_BENCHMARK_CORPUS[:])
	_run_numeric_benchmark_corpus("mixed", NUMERIC_MIXED_BENCHMARK_CORPUS[:])
}
