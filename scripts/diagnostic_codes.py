#!/usr/bin/env python3

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


DEFAULT_CODES_PATH = Path(__file__).resolve().parents[1] / "src/frontend/diagnostics/codes.odin"
SECTION_FOR_ORIGIN = {
    "Lexer": "Lexer diagnostics",
    "Parser": "Parser diagnostics",
    "Resolution": "Resolver diagnostics",
    "Semantic": "Semantic analysis diagnostics",
    "Unknown": "MISC",
}
LEVELS = ("Notice", "Warning", "Error")
CATEGORIES = (
    "General",
    "Unused",
    "Deprecated",
    "Dubious",
    "Performance",
    "Portability",
    "Style",
)
CODE_RE = re.compile(r"^\t([A-Za-z][A-Za-z0-9_]*),$")
METADATA_RE = re.compile(r"^\t\.([A-Za-z][A-Za-z0-9_]*) = ")
SUMMARY_RE = re.compile(r'\bsummary\s*=\s*("(?:\\.|[^"\\])*")')


@dataclass
class Code:
    name: str
    summary: str | None
    comment_start: int | None
    line: int


@dataclass
class Metadata:
    name: str
    start: int
    end: int
    summary: str | None


def _bounds(lines: list[str], start: str, end: str) -> tuple[int, int]:
    try:
        first = next(i for i, line in enumerate(lines) if line.startswith(start))
        last = next(i for i in range(first + 1, len(lines)) if lines[i].startswith(end))
    except StopIteration as error:
        raise ValueError(f"could not find the section from {start!r} to {end!r}") from error
    return first, last


def _codes(lines: list[str]) -> dict[str, Code]:
    start, end = _bounds(lines, "Code :: enum {", "Code_Metadata :: struct {")
    result: dict[str, Code] = {}
    for i in range(start + 1, end):
        match = CODE_RE.match(lines[i].rstrip("\n"))
        if match is None:
            continue
        comment_start = i
        comments: list[str] = []
        while comment_start > start + 1:
            candidate = lines[comment_start - 1].rstrip("\n")
            if not candidate.startswith("\t//") or candidate.startswith("\t// =="):
                break
            comment_start -= 1
            text = candidate[3:]
            comments.append(text[1:] if text.startswith(" ") else text)
        comments.reverse()
        result[match.group(1)] = Code(
            match.group(1),
            " ".join(comments) if comments else None,
            comment_start if comments else None,
            i,
        )
    return result


def _metadata(lines: list[str]) -> dict[str, Metadata]:
    start, end = _bounds(lines, "CODE_METADATA := [Code]Code_Metadata {", "_fmt_code :: proc")
    result: dict[str, Metadata] = {}
    i = start + 1
    while i < end:
        match = METADATA_RE.match(lines[i])
        if match is None:
            i += 1
            continue
        entry_start = i
        if lines[i].rstrip().endswith("},"):
            entry_end = i + 1
        else:
            i += 1
            while i < end and lines[i].rstrip("\n") != "\t},":
                i += 1
            if i == end:
                raise ValueError(f"unterminated metadata for {match.group(1)}")
            entry_end = i + 1
        text = "".join(lines[entry_start:entry_end])
        summary_match = SUMMARY_RE.search(text)
        if summary_match is None and re.search(r"\bsummary\s*=", text):
            raise ValueError(f"invalid summary string for {match.group(1)}")
        result[match.group(1)] = Metadata(
            match.group(1),
            entry_start,
            entry_end,
            json.loads(summary_match.group(1)) if summary_match else None,
        )
        i = entry_end
    return result


def _comment_lines(summary: str) -> list[str]:
    return [f"\t// {summary}\n"]


def _with_summary(entry: list[str], summary: str) -> list[str]:
    literal = json.dumps(summary, ensure_ascii=False)
    if len(entry) == 1:
        line = entry[0]
        close = line.rfind("}")
        separator = "" if line[:close].rstrip().endswith("{") else ", "
        return [f"{line[:close]}{separator}summary = {literal}{line[close:]}"]
    return [*entry[:-1], f"\t\tsummary = {literal},\n", entry[-1]]


def _synchronized(lines: list[str]) -> list[str]:
    codes = _codes(lines)
    metadata = _metadata(lines)
    if codes.keys() != metadata.keys():
        missing_metadata = sorted(codes.keys() - metadata.keys())
        missing_codes = sorted(metadata.keys() - codes.keys())
        problems = []
        if missing_metadata:
            problems.append(f"missing metadata: {', '.join(missing_metadata)}")
        if missing_codes:
            problems.append(f"missing enum codes: {', '.join(missing_codes)}")
        raise ValueError("; ".join(problems))

    summaries: dict[str, str | None] = {}
    for name, code in codes.items():
        meta_summary = metadata[name].summary
        summaries[name] = meta_summary if meta_summary is not None else code.summary
        if name != "TBD" and summaries[name] is None:
            raise ValueError(f"{name} has neither a summary nor a preceding comment")
        if summaries[name] is not None and ("\n" in summaries[name] or "\r" in summaries[name]):
            raise ValueError(f"{name} has a summary that does not fit on one line")

    replacements: list[tuple[int, int, list[str]]] = []
    for name, code in codes.items():
        summary = summaries[name]
        if summary is None:
            continue
        start = code.comment_start if code.comment_start is not None else code.line
        replacements.append((start, code.line, _comment_lines(summary)))
        meta = metadata[name]
        if meta.summary is None:
            replacements.append(
                (meta.start, meta.end, _with_summary(lines[meta.start : meta.end], summary))
            )

    result = lines[:]
    for start, end, replacement in sorted(replacements, reverse=True):
        result[start:end] = replacement
    return result


def _section_end(lines: list[str], section: str, within_start: str, within_end: str) -> int:
    start, end = _bounds(lines, within_start, within_end)
    is_enum = within_start.startswith("Code ::")
    heading = f"\t// == {section} ==" if is_enum else f"\t// {section}"
    headings = {
        f"\t// == {name} ==" if is_enum else f"\t// {name}"
        for name in (*SECTION_FOR_ORIGIN.values(), "TEST")
    }
    try:
        section_start = next(i for i in range(start, end) if lines[i].rstrip("\n") == heading)
    except StopIteration as error:
        raise ValueError(f"could not find the {section!r} section") from error
    insertion = next(
        (i for i in range(section_start + 1, end) if lines[i].rstrip("\n") in headings),
        end - 1,
    )
    while insertion > section_start + 1 and not lines[insertion - 1].strip():
        insertion -= 1
    return insertion


def _insert_code(
    lines: list[str], name: str, origin: str, category: str, level: str, summary: str
) -> list[str]:
    if not re.fullmatch(r"[A-Z][A-Za-z0-9]*(?:_[A-Z][A-Za-z0-9]*)*", name):
        raise ValueError("code names must use Upper_Snake_Case")
    if name in _codes(lines) or name in _metadata(lines):
        raise ValueError(f"{name} already exists")
    if not summary.strip():
        raise ValueError("summary cannot be empty")
    if "\n" in summary or "\r" in summary:
        raise ValueError("summaries must fit on one line")

    section = SECTION_FOR_ORIGIN[origin]
    enum_at = _section_end(lines, section, "Code :: enum {", "Code_Metadata :: struct {")
    lines[enum_at:enum_at] = [*_comment_lines(summary), f"\t{name},\n"]

    metadata_at = _section_end(
        lines, section, "CODE_METADATA := [Code]Code_Metadata {", "_fmt_code :: proc"
    )
    fields = [f"\t\torigin = .{origin},\n"]
    if category != "General":
        fields.append(f"\t\tcategory = .{category},\n")
    fields.extend(
        (
            f"\t\tdefault_level = .{level},\n",
            f"\t\tsummary = {json.dumps(summary, ensure_ascii=False)},\n",
        )
    )
    # TODO: Assign stable diagnostic IDs after their scheme is finalized.
    lines[metadata_at:metadata_at] = [f"\t.{name} = {{\n", *fields, "\t},\n"]
    return lines


def _format(path: Path) -> None:
    formatter = (
        os.environ.get("ODIN_FMT") or shutil.which("odin-fmt") or shutil.which("odinfmt")
    )
    if formatter is None and (ols := shutil.which("ols")) is not None:
        bundled_formatter = Path(ols).resolve().with_name("odinfmt")
        if bundled_formatter.is_file():
            formatter = str(bundled_formatter)
    if formatter is None:
        raise ValueError("could not find odin-fmt or odinfmt; set ODIN_FMT to its path")
    subprocess.run([formatter, str(path), "-w"], check=True)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Add and synchronize diagnostic codes.")
    parser.add_argument("-p", "--path", type=Path, default=DEFAULT_CODES_PATH)
    subparsers = parser.add_subparsers(dest="command", required=True)

    add = subparsers.add_parser("add", help="add a diagnostic enum value and its metadata")
    add.add_argument("name")
    add.add_argument("summary", help="one-line summary, or - to read it from stdin")
    add.add_argument("-o", "--origin", choices=SECTION_FOR_ORIGIN, required=True)
    add.add_argument("-l", "--level", choices=LEVELS, default="Error")
    add.add_argument("-c", "--category", choices=CATEGORIES, default="General")

    subparsers.add_parser("sync", help="rewrite comments from authoritative summaries")
    subparsers.add_parser("check", help="check that comments match summaries")
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        original = args.path.read_text().splitlines(keepends=True)
        synchronized = _synchronized(original)
        if args.command == "check":
            if synchronized != original:
                print(f"{args.path}: diagnostic comments and summaries are not synchronized", file=sys.stderr)
                return 1
            return 0

        if args.command == "add":
            summary = sys.stdin.read().rstrip("\n") if args.summary == "-" else args.summary
            synchronized = _insert_code(
                synchronized, args.name, args.origin, args.category, args.level, summary
            )
            synchronized = _synchronized(synchronized)

        args.path.write_text("".join(synchronized))
        _format(args.path)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
