# Philosophy around Errors

The goal in Kerrek's error handling is to try to take the good parts from other systems of error handling and avoid the bad. It's a synthesis of other error handling systems. You can think of it like exceptions without deep error hierarchies and propagation or "errors as values" with less ceremony at every point of failure.

From my discussion with ChatGPT in refining some ideas I've had about error handling, it listed the following properties/guarantees/summary of the Kerrek error handling system:

- No generic `error` soup.
- No type assertions just to discover what went wrong.
- No `try`/`catch` unwinding across half the application.
- No `Result<T, E>` boilerplate everywhere.
- No silently ignored fallible operations.
- No accidental propagation of implementation details across API boundaries.
- Multiple normal return values remain completely natural.
- Errors can carry rich, concrete typed information.
- The compiler knows every failure path.
- Recovery can be as concise as expr catch fallback.
- More complex recovery can live in a block-level handler.
- `continue` provides a type-checked replacement for the failed computation.

# Semantics

Each function can return multiple errors and it may be fallible. Fallible functions may specify one type that is passed to the subsequent error handler.

```kerrek
func never_fails() -> Integer, Decimal(10, 2), String {
	\\ implementation omitted
}

func might_fail() -> Boolean ! {
	\\ implementation omitted
}

func might_fail_with_no_values() -> ! {
	\\ implementation omitted
}

func fails_with_a_value() -> String, String ! FailureType {
	\\ implementation omitted
}
```

A function which fails without any error value can only be handled by an inline `catch`

You can handle errors in a few ways

```kerrek
func serialize_finances(w: io.Writer, account: FinancialAccount) ! SerializationError {
	catch io.WriteError { \\ will handle any io.WriteError for the rest of the block
		\\ the error value is implicitly assigned to the `err` name within the catch block
		if err.sink_kind == .TTY {
			panic("writes are not expected to fail on a tty");
		}
		fail .CannotWrite;
	}

	let today = date.today();

	binio.write_date(w, today);
	binio.write_bcd(w, account.account_id, 20);
	binio.write_pascal_string(w, account.account_first_name);
	binio.write_pascal_string(w, account.account_last_name);
	binio.write_bcd(w, account.balance, 24);

	\\ catch expression with a value instead of a block continues with the provided value
	let age = time.since(account.opened_on) catch 0 time.Day;

	\\ catch expression with a block allows you to execute statements such as fail
	let checksum = calc_checksum(today, account.account_id, account.balance) catch {
		fail .ChecksumFailed;
	};
}

func contrived() ! ContrivedError {
	let contrived_complex_expr = get_flask(
		\\ catch expressions can exist inside an expression
		move(.Dennis) catch { fail .CannotMoveDennis; },
		throw_baby(400 si.Meter per si.Second),
	) + 8
		\\ you can also chain catch expressions corresponding to different types
		catch CantGetYeFlask { continue 0; }
		catch OverflowError {
			fail .FlaskOverflow
		}
		catch { fail .IDKLOL };  \\ catches the error from throw_baby
	\\ a catch expression with no specified types catches whatever is left unhandled deeper within
	\\ the expression, but provides no inspection capabilities on the error value
}
```

`continue` statements within a `catch` expression block must return the same result types as the outermost expression.

`continue` statements within a `catch` statement block must be bare and are only valid if either the zero value is valid for every possible result this is applied to or the return value is ignored.
