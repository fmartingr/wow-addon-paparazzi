// Package savedvars parses the subset of Lua that World of Warcraft writes to SavedVariables files.
// The parser runs no code and has no dependencies.
package savedvars

import (
	"errors"
	"fmt"
	"io"
	"math"
	"sort"
	"strconv"
)

// Limits protect against hostile or corrupt input.
const (
	MaxInputSize = 64 << 20
	MaxDepth     = 64
	MaxTables    = 1 << 20
)

type parser struct {
	lex   *lexer
	tok   token
	depth int
	count int
}

// Parse reads a SavedVariables file and returns its top-level assignments.
// Tables with the keys 1..n become []any. Other tables become map[string]any.
func Parse(r io.Reader) (map[string]any, error) {
	src, err := io.ReadAll(io.LimitReader(r, MaxInputSize+1))
	if err != nil {
		return nil, err
	}
	if len(src) > MaxInputSize {
		return nil, fmt.Errorf("input is larger than %d bytes", MaxInputSize)
	}

	p := &parser{lex: newLexer(src)}
	if err := p.step(); err != nil {
		return nil, err
	}
	out := map[string]any{}
	for p.tok.kind != tokEOF {
		if p.tok.kind != tokIdent {
			return nil, p.unexpected()
		}
		name := p.tok.text
		if err := p.step(); err != nil {
			return nil, err
		}
		if err := p.expect("="); err != nil {
			return nil, err
		}
		value, err := p.value()
		if err != nil {
			return nil, err
		}
		out[name] = value
	}
	return out, nil
}

func (p *parser) step() error {
	tok, err := p.lex.next()
	if err != nil {
		return err
	}
	p.tok = tok
	return nil
}

func (p *parser) unexpected() error {
	what := p.tok.text
	if p.tok.kind == tokEOF {
		what = "end of input"
	}
	return p.lex.errorf(p.tok.line, p.tok.col, "unexpected %q", what)
}

func (p *parser) isSymbol(s string) bool {
	return p.tok.kind == tokSymbol && p.tok.text == s
}

func (p *parser) expect(s string) error {
	if !p.isSymbol(s) {
		return p.unexpected()
	}
	return p.step()
}

func (p *parser) value() (any, error) {
	tok := p.tok
	switch tok.kind {
	case tokString:
		return tok.text, p.step()
	case tokNumber:
		return tok.num, p.step()
	case tokIdent:
		switch tok.text {
		case "true":
			return true, p.step()
		case "false":
			return false, p.step()
		case "nil":
			return nil, p.step()
		}
	case tokSymbol:
		if tok.text == "{" {
			return p.table()
		}
	}
	return nil, p.unexpected()
}

type tableBuilder struct {
	numeric map[int64]any
	named   map[string]any
	next    int64
}

func (b *tableBuilder) setKey(key any, value any) {
	switch k := key.(type) {
	case int64:
		b.numeric[k] = value
	case float64:
		if k == math.Trunc(k) && math.Abs(k) < 1<<53 {
			b.numeric[int64(k)] = value
		} else {
			b.named[strconv.FormatFloat(k, 'g', -1, 64)] = value
		}
	case string:
		b.named[k] = value
	}
}

func (b *tableBuilder) result() any {
	if len(b.named) == 0 && len(b.numeric) > 0 {
		isArray := true
		for i := int64(1); i <= int64(len(b.numeric)); i++ {
			if _, ok := b.numeric[i]; !ok {
				isArray = false
				break
			}
		}
		if isArray {
			list := make([]any, len(b.numeric))
			for i := range list {
				list[i] = b.numeric[int64(i+1)]
			}
			return list
		}
	}

	out := make(map[string]any, len(b.named)+len(b.numeric))
	for k, v := range b.named {
		out[k] = v
	}
	keys := make([]int64, 0, len(b.numeric))
	for k := range b.numeric {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i] < keys[j] })
	for _, k := range keys {
		out[strconv.FormatInt(k, 10)] = b.numeric[k]
	}
	return out
}

func (p *parser) table() (any, error) {
	p.depth++
	p.count++
	if p.count > MaxTables {
		return nil, p.lex.errorf(p.tok.line, p.tok.col, "more than %d tables", MaxTables)
	}
	defer func() { p.depth-- }()
	if p.depth > MaxDepth {
		return nil, p.lex.errorf(p.tok.line, p.tok.col, "tables are nested deeper than %d levels", MaxDepth)
	}
	if err := p.expect("{"); err != nil {
		return nil, err
	}

	b := &tableBuilder{numeric: map[int64]any{}, named: map[string]any{}}
	for !p.isSymbol("}") {
		if err := p.field(b); err != nil {
			return nil, err
		}
		if p.isSymbol(",") || p.isSymbol(";") {
			if err := p.step(); err != nil {
				return nil, err
			}
			continue
		}
		if !p.isSymbol("}") {
			return nil, p.unexpected()
		}
	}
	if err := p.expect("}"); err != nil {
		return nil, err
	}
	return b.result(), nil
}

func (p *parser) field(b *tableBuilder) error {
	switch {
	case p.isSymbol("["):
		if err := p.step(); err != nil {
			return err
		}
		var key any
		switch p.tok.kind {
		case tokString:
			key = p.tok.text
		case tokNumber:
			key = p.tok.num
		default:
			return p.unexpected()
		}
		if err := p.step(); err != nil {
			return err
		}
		if err := p.expect("]"); err != nil {
			return err
		}
		if err := p.expect("="); err != nil {
			return err
		}
		value, err := p.value()
		if err != nil {
			return err
		}
		b.setKey(key, value)
		return nil
	case p.tok.kind == tokIdent && p.tok.text != "true" && p.tok.text != "false" && p.tok.text != "nil":
		name := p.tok.text
		if err := p.step(); err != nil {
			return err
		}
		if err := p.expect("="); err != nil {
			return err
		}
		value, err := p.value()
		if err != nil {
			return err
		}
		b.named[name] = value
		return nil
	}

	value, err := p.value()
	if err != nil {
		return err
	}
	b.next++
	b.numeric[b.next] = value
	return nil
}

// ErrSyntax matches every syntax error that Parse returns.
var ErrSyntax = errors.New("syntax error")

func (e *syntaxError) Is(target error) bool { return target == ErrSyntax }
