package savedvars

import (
	"bytes"
	"io"
	"reflect"
	"strings"
	"testing"
)

func TestParseValues(t *testing.T) {
	tests := []struct {
		name string
		src  string
		want map[string]any
	}{
		{"empty", "", map[string]any{}},
		{"header comment only", "-- header\n", map[string]any{}},
		{"string", `A = "hi"`, map[string]any{"A": "hi"}},
		{"single quote", `A = 'hi'`, map[string]any{"A": "hi"}},
		{"integer", `A = 42`, map[string]any{"A": int64(42)}},
		{"negative", `A = -7`, map[string]any{"A": int64(-7)}},
		{"float", `A = 1.5`, map[string]any{"A": 1.5}},
		{"leading dot float", `A = .5`, map[string]any{"A": 0.5}},
		{"exponent", `A = 1e3`, map[string]any{"A": 1000.0}},
		{"signed exponent", `A = 2E-1`, map[string]any{"A": 0.2}},
		{"big integer becomes float", `A = 99999999999999999999`, map[string]any{"A": 1e20}},
		{"booleans and nil", `A = true B = false C = nil`, map[string]any{"A": true, "B": false, "C": nil}},
		{"empty table", `A = {}`, map[string]any{"A": map[string]any{}}},
		{"named fields", `A = { x = 1, ["y"] = 2; z = "s", }`, map[string]any{"A": map[string]any{"x": int64(1), "y": int64(2), "z": "s"}}},
		{"array", `A = { 10, 20, 30, -- [3]
}`, map[string]any{"A": []any{int64(10), int64(20), int64(30)}}},
		{"explicit index array", `A = { [1] = "a", [2] = "b" }`, map[string]any{"A": []any{"a", "b"}}},
		{"float index array", `A = { [1.0] = "a" }`, map[string]any{"A": []any{"a"}}},
		{"sparse array becomes map", `A = { [1] = "a", [3] = "c" }`, map[string]any{"A": map[string]any{"1": "a", "3": "c"}}},
		{"mixed keys become map", `A = { "a", x = 1 }`, map[string]any{"A": map[string]any{"1": "a", "x": int64(1)}}},
		{"fractional key", `A = { [1.5] = "a" }`, map[string]any{"A": map[string]any{"1.5": "a"}}},
		{"nested", `A = { { x = { 1 } } }`, map[string]any{"A": []any{map[string]any{"x": []any{int64(1)}}}}},
		{"several assignments", "A = 1\nB = 2", map[string]any{"A": int64(1), "B": int64(2)}},
		{"nil positional", `A = { nil, 2 }`, map[string]any{"A": []any{nil, int64(2)}}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Parse(strings.NewReader(tc.src))
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("got %#v, want %#v", got, tc.want)
			}
		})
	}
}

func TestParseEscapes(t *testing.T) {
	tests := []struct{ src, want string }{
		{`A = "a\\b"`, "a\\b"},
		{`A = "a\"b"`, `a"b`},
		{`A = 'a\'b'`, "a'b"},
		{`A = "a\nb"`, "a\nb"},
		{`A = "a\rb"`, "a\rb"},
		{`A = "a\tb"`, "a\tb"},
		{`A = "\a\b\f\v"`, "\a\b\f\v"},
		{`A = "\65\066\0067"`, "AB\x067"},
		{"A = \"a\\\nb\"", "a\nb"},
	}
	for _, tc := range tests {
		got, err := Parse(strings.NewReader(tc.src))
		if err != nil {
			t.Fatalf("%q: %v", tc.src, err)
		}
		if got["A"] != tc.want {
			t.Errorf("%q: got %q, want %q", tc.src, got["A"], tc.want)
		}
	}
}

func TestParseErrors(t *testing.T) {
	tests := []struct {
		name string
		src  string
		want string
	}{
		{"unterminated string", "A = 1\nB = \"abc", "line 2, column 5: unterminated string"},
		{"newline in string", "A = \"ab\ncd\"", "line 1, column 5: unterminated string"},
		{"escape too large", `A = "\256"`, "decimal escape too large"},
		{"invalid escape", `A = "\q"`, "invalid escape"},
		{"trailing backslash", `A = "\`, "unterminated string"},
		{"inf", `A = inf`, "unexpected"},
		{"negative inf", `A = -inf`, "invalid number"},
		{"nan", `A = nan`, "unexpected"},
		{"bad exponent", `A = 1e`, "invalid number exponent"},
		{"missing equals", `A 1`, `unexpected "1"`},
		{"missing value", `A =`, "unexpected"},
		{"unclosed table", "A = { 1,", "unexpected"},
		{"missing comma", "A = { 1 2 }", `unexpected "2"`},
		{"bad key", `A = { [true] = 1 }`, "unexpected"},
		{"missing bracket", `A = { ["x" = 1 }`, "unexpected"},
		{"bad field equals", `A = { x 1 }`, "unexpected"},
		{"unexpected char", `A = @`, "unexpected character"},
		{"statement start", `1 = 2`, "unexpected"},
		{"name as value", `A = B`, "unexpected"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Parse(strings.NewReader(tc.src))
			if err == nil {
				t.Fatal("expected an error")
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("got %q, want it to contain %q", err, tc.want)
			}
		})
	}
}

func TestSyntaxErrorIs(t *testing.T) {
	_, err := Parse(strings.NewReader(`A = @`))
	if !errorsIs(err, ErrSyntax) {
		t.Fatalf("expected ErrSyntax, got %v", err)
	}
}

func errorsIs(err, target error) bool {
	type is interface{ Is(error) bool }
	e, ok := err.(is)
	return ok && e.Is(target)
}

func TestParseDepth(t *testing.T) {
	nest := func(n int) string {
		return "A = " + strings.Repeat("{", n) + strings.Repeat("}", n)
	}
	if _, err := Parse(strings.NewReader(nest(MaxDepth))); err != nil {
		t.Fatalf("depth %d: %v", MaxDepth, err)
	}
	_, err := Parse(strings.NewReader(nest(MaxDepth + 1)))
	if err == nil || !strings.Contains(err.Error(), "nested deeper") {
		t.Fatalf("depth %d: got %v", MaxDepth+1, err)
	}
}

func TestParseTableCountLimit(t *testing.T) {
	src := "A = {" + strings.Repeat("{},", MaxTables) + "}"
	_, err := Parse(strings.NewReader(src))
	if err == nil || !strings.Contains(err.Error(), "tables") {
		t.Fatalf("got %v", err)
	}
}

type repeatReader struct{ left int64 }

func (r *repeatReader) Read(p []byte) (int, error) {
	if r.left <= 0 {
		return 0, io.EOF
	}
	n := int64(len(p))
	if n > r.left {
		n = r.left
	}
	copy(p[:n], bytes.Repeat([]byte{' '}, int(n)))
	r.left -= n
	return int(n), nil
}

func TestParseSizeLimit(t *testing.T) {
	if _, err := Parse(&repeatReader{left: 70 << 20}); err == nil {
		t.Fatal("expected an error for 70 MiB")
	}
}

type failingReader struct{}

func (failingReader) Read([]byte) (int, error) { return 0, io.ErrClosedPipe }

func TestParseReadError(t *testing.T) {
	if _, err := Parse(failingReader{}); err == nil {
		t.Fatal("expected a read error")
	}
}

func FuzzParse(f *testing.F) {
	seeds := []string{
		"", `A = 1`, `A = { "x", y = { [1] = 2 }, } -- c`, `A = "\65\n"`, `A = {{{{`, `A = -`, `A = 1e`, "A = '\\",
		`PaparazziDB = { ["captures"] = { { ["file"] = "x", }, -- [1]
}, }`,
	}
	for _, s := range seeds {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, src string) {
		_, _ = Parse(strings.NewReader(src))
	})
}
