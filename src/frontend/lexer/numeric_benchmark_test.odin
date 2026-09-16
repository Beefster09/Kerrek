#+test
package lexer

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:testing"
import "core:time"


RUN_NUMERIC_BENCHMARKS :: #config(RUN_NUMERIC_BENCHMARKS, false)
NUMERIC_BENCHMARK_ROUNDS :: #config(NUMERIC_BENCHMARK_ROUNDS, 100_000)
NUMERIC_BENCHMARK_SAMPLES :: 9

@(rodata)
NUMERIC_INTEGER_BENCHMARK_CORPUS := [?]string {
	"0!",
	"42!",
	"000_001!",
	"1_000_000!",
	"123456789012345678!",
	"0xdead_BEEF!",
	"0x0123_4567_89ab_cdef!",
	"0o7_654_321!",
	"0b1010_1100_1111_0000!",
}

@(rodata)
NUMERIC_MIXED_BENCHMARK_CORPUS := [?]string {
	"0!",
	"1_000_000!",
	"0xdead_BEEF!",
	"0o7_654_321!",
	"0b1010_1100_1111_0000!",
	"12.50e-1!",
	"1_2.5_0e-1_0!",
	"0.001_20!",
	"1e1_0!",
	"0x1.8p1!",
	"0x1.a_bp+1_0!",
	"0x0.08p0!",
}

@(rodata)
NUMERIC_SCANNER_BENCHMARK_CORPUS := [?]string {
	"0!",
	"000_001!",
	"1_000_000!",
	"123456789012345678!",
	"12.50e-1!",
	"1_2.5_0e-1_0!",
	"0.001_20!",
	"1e1_0!",
	"0xdead_BEEF!",
	"0x0123_4567_89ab_cdef!",
	"0x1.8p1!",
	"0x1.a_bp+1_0!",
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

_benchmark_current_numeric_matcher :: proc(
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

_benchmark_dfa_numeric_matcher :: proc(
	corpus: []string,
	rounds: int,
) -> Numeric_Benchmark_Result {
	result: Numeric_Benchmark_Result
	watch: time.Stopwatch
	time.stopwatch_start(&watch)
	for _ in 0 ..< rounds {
		for source in corpus {
			numeric, length := _match_numeric_dfa({}, source)
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
	precision: u32,
	ok: bool,
) {
	checksum^ = checksum^ * 1099511628211 ~
	            u64(length) ~
	            u64(format) << 16 ~
	            u64(precision) << 24 ~
	            u64(ok) << 32
}

_benchmark_current_numeric_scanner :: proc(
	corpus: []string,
	rounds: int,
) -> Numeric_Benchmark_Result {
	result: Numeric_Benchmark_Result
	watch: time.Stopwatch
	time.stopwatch_start(&watch)
	for _ in 0 ..< rounds {
		for source in corpus {
			length: int
			format: Number_Format
			precision: u32
			ok: bool
			if strings.starts_with(source, "0x") {
				is_float: bool
				length, is_float, ok, precision = _check_hex_numeric(source[2:])
				length += 2
				format = .HexFloat if is_float else .HexInteger
			} else {
				is_fractional: bool
				length, is_fractional, ok, precision = _check_decimal_numeric(source)
				format = .Decimal if is_fractional else .DecimalInteger
			}
			assert(ok && length > 0)
			_consume_numeric_scanner_result(&result.checksum, length, format, precision, ok)
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

_benchmark_dfa_numeric_scanner :: proc(
	corpus: []string,
	rounds: int,
) -> Numeric_Benchmark_Result {
	result: Numeric_Benchmark_Result
	watch: time.Stopwatch
	time.stopwatch_start(&watch)
	for _ in 0 ..< rounds {
		for source in corpus {
			match := _scan_numeric_dfa(source)
			assert(match.ok && match.length > 0)
			_consume_numeric_scanner_result(
				&result.checksum,
				match.length,
				match.format,
				match.precision,
				match.ok,
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

_run_numeric_scanner_benchmark :: proc(t: ^testing.T, corpus: []string) {
	warmup_rounds := max(NUMERIC_BENCHMARK_ROUNDS / 20, 1)
	warm_current := _benchmark_current_numeric_scanner(corpus, warmup_rounds)
	warm_dfa := _benchmark_dfa_numeric_scanner(corpus, warmup_rounds)
	testing.expectf(t, warm_current.checksum == warm_dfa.checksum, "scanner warm-up checksums differ")

	current_samples: [NUMERIC_BENCHMARK_SAMPLES]time.Duration
	dfa_samples: [NUMERIC_BENCHMARK_SAMPLES]time.Duration
	reference: Numeric_Benchmark_Result
	for i in 0 ..< NUMERIC_BENCHMARK_SAMPLES {
		current, dfa: Numeric_Benchmark_Result
		if i % 2 == 0 {
			current = _benchmark_current_numeric_scanner(corpus, NUMERIC_BENCHMARK_ROUNDS)
			dfa = _benchmark_dfa_numeric_scanner(corpus, NUMERIC_BENCHMARK_ROUNDS)
		} else {
			dfa = _benchmark_dfa_numeric_scanner(corpus, NUMERIC_BENCHMARK_ROUNDS)
			current = _benchmark_current_numeric_scanner(corpus, NUMERIC_BENCHMARK_ROUNDS)
		}
		testing.expectf(t, current.checksum == dfa.checksum, "scanner sample %d checksums differ", i)
		current_samples[i] = current.duration
		dfa_samples[i] = dfa.duration
		reference = current
	}

	slice.sort(current_samples[:])
	slice.sort(dfa_samples[:])
	current_median := current_samples[NUMERIC_BENCHMARK_SAMPLES / 2]
	dfa_median := dfa_samples[NUMERIC_BENCHMARK_SAMPLES / 2]
	current_ns := f64(time.duration_nanoseconds(current_median)) / f64(reference.calls)
	dfa_ns := f64(time.duration_nanoseconds(dfa_median)) / f64(reference.calls)
	current_mib := f64(reference.processed) /
	               (1024 * 1024) /
	               (f64(time.duration_nanoseconds(current_median)) / 1e9)
	dfa_mib := f64(reference.processed) /
	           (1024 * 1024) /
	           (f64(time.duration_nanoseconds(dfa_median)) / 1e9)
	fmt.printfln(
		"scanner  %d calls  current %.2f ns/literal %.2f MiB/s  DFA %.2f ns/literal %.2f MiB/s  DFA/current %.3fx",
		reference.calls,
		current_ns,
		current_mib,
		dfa_ns,
		dfa_mib,
		dfa_ns / current_ns,
	)
}

_run_numeric_benchmark_corpus :: proc(
	t: ^testing.T,
	name: string,
	corpus: []string,
) {
	warmup_rounds := max(NUMERIC_BENCHMARK_ROUNDS / 20, 1)
	warm_current := _benchmark_current_numeric_matcher(corpus, warmup_rounds)
	warm_dfa := _benchmark_dfa_numeric_matcher(corpus, warmup_rounds)
	testing.expectf(t, warm_current.checksum == warm_dfa.checksum, "%s warm-up checksums differ", name)

	current_samples: [NUMERIC_BENCHMARK_SAMPLES]time.Duration
	dfa_samples: [NUMERIC_BENCHMARK_SAMPLES]time.Duration
	reference: Numeric_Benchmark_Result
	for i in 0 ..< NUMERIC_BENCHMARK_SAMPLES {
		current, dfa: Numeric_Benchmark_Result
		if i % 2 == 0 {
			current = _benchmark_current_numeric_matcher(corpus, NUMERIC_BENCHMARK_ROUNDS)
			dfa = _benchmark_dfa_numeric_matcher(corpus, NUMERIC_BENCHMARK_ROUNDS)
		} else {
			dfa = _benchmark_dfa_numeric_matcher(corpus, NUMERIC_BENCHMARK_ROUNDS)
			current = _benchmark_current_numeric_matcher(corpus, NUMERIC_BENCHMARK_ROUNDS)
		}

		testing.expectf(t, current.checksum == dfa.checksum, "%s sample %d checksums differ", name, i)
		current_samples[i] = current.duration
		dfa_samples[i] = dfa.duration
		reference = current
	}

	slice.sort(current_samples[:])
	slice.sort(dfa_samples[:])
	current_median := current_samples[NUMERIC_BENCHMARK_SAMPLES / 2]
	dfa_median := dfa_samples[NUMERIC_BENCHMARK_SAMPLES / 2]
	current_ns := f64(time.duration_nanoseconds(current_median)) / f64(reference.calls)
	dfa_ns := f64(time.duration_nanoseconds(dfa_median)) / f64(reference.calls)
	current_mib := f64(reference.processed) /
	               (1024 * 1024) /
	               (f64(time.duration_nanoseconds(current_median)) / 1e9)
	dfa_mib := f64(reference.processed) /
	           (1024 * 1024) /
	           (f64(time.duration_nanoseconds(dfa_median)) / 1e9)

	fmt.printfln(
		"%s %d calls  current %.2f ns/literal %.2f MiB/s  DFA %.2f ns/literal %.2f MiB/s  DFA/current %.3fx",
		name,
		reference.calls,
		current_ns,
		current_mib,
		dfa_ns,
		dfa_mib,
		dfa_ns / current_ns,
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
	_run_numeric_scanner_benchmark(t, NUMERIC_SCANNER_BENCHMARK_CORPUS[:])
	_run_numeric_benchmark_corpus(t, "integers", NUMERIC_INTEGER_BENCHMARK_CORPUS[:])
	_run_numeric_benchmark_corpus(t, "mixed", NUMERIC_MIXED_BENCHMARK_CORPUS[:])
}
