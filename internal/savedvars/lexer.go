package savedvars

import (
	"fmt"
	"strconv"
	"strings"
)

type tokenKind int

const (
	tokEOF tokenKind = iota
	tokIdent
	tokString
	tokNumber
	tokSymbol
)

type token struct {
	kind tokenKind
	text string
	num  any
	line int
	col  int
}

type lexer struct {
	src  []byte
	pos  int
	line int
	col  int
}

func newLexer(src []byte) *lexer {
	return &lexer{src: src, line: 1, col: 1}
}

type syntaxError struct {
	line, col int
	msg       string
}

func (e *syntaxError) Error() string {
	return fmt.Sprintf("line %d, column %d: %s", e.line, e.col, e.msg)
}

func (l *lexer) errorf(line, col int, format string, args ...any) error {
	return &syntaxError{line: line, col: col, msg: fmt.Sprintf(format, args...)}
}

func (l *lexer) peekByte(offset int) byte {
	if l.pos+offset >= len(l.src) {
		return 0
	}
	return l.src[l.pos+offset]
}

func (l *lexer) advance() byte {
	c := l.src[l.pos]
	l.pos++
	if c == '\n' {
		l.line++
		l.col = 1
	} else {
		l.col++
	}
	return c
}

func (l *lexer) skipSpace() {
	for l.pos < len(l.src) {
		c := l.src[l.pos]
		switch {
		case c == ' ' || c == '\t' || c == '\r' || c == '\n':
			l.advance()
		case c == '-' && l.peekByte(1) == '-':
			for l.pos < len(l.src) && l.src[l.pos] != '\n' {
				l.advance()
			}
		default:
			return
		}
	}
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

func isIdentStart(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

func (l *lexer) next() (token, error) {
	l.skipSpace()
	line, col := l.line, l.col
	if l.pos >= len(l.src) {
		return token{kind: tokEOF, line: line, col: col}, nil
	}
	c := l.src[l.pos]
	switch {
	case isIdentStart(c):
		start := l.pos
		for l.pos < len(l.src) && (isIdentStart(l.src[l.pos]) || isDigit(l.src[l.pos])) {
			l.advance()
		}
		return token{kind: tokIdent, text: string(l.src[start:l.pos]), line: line, col: col}, nil
	case c == '"' || c == '\'':
		return l.lexString(c, line, col)
	case isDigit(c) || c == '-' || (c == '.' && isDigit(l.peekByte(1))):
		return l.lexNumber(line, col)
	case strings.IndexByte("{}[]=,;", c) >= 0:
		l.advance()
		return token{kind: tokSymbol, text: string(c), line: line, col: col}, nil
	}
	return token{}, l.errorf(line, col, "unexpected character %q", c)
}

func (l *lexer) lexNumber(line, col int) (token, error) {
	start := l.pos
	if l.src[l.pos] == '-' {
		l.advance()
		if !isDigit(l.peekByte(0)) && !(l.peekByte(0) == '.' && isDigit(l.peekByte(1))) {
			return token{}, l.errorf(line, col, "invalid number")
		}
	}
	isFloat := false
	for isDigit(l.peekByte(0)) {
		l.advance()
	}
	if l.peekByte(0) == '.' {
		isFloat = true
		l.advance()
		for isDigit(l.peekByte(0)) {
			l.advance()
		}
	}
	if c := l.peekByte(0); c == 'e' || c == 'E' {
		isFloat = true
		l.advance()
		if c := l.peekByte(0); c == '+' || c == '-' {
			l.advance()
		}
		if !isDigit(l.peekByte(0)) {
			return token{}, l.errorf(line, col, "invalid number exponent")
		}
		for isDigit(l.peekByte(0)) {
			l.advance()
		}
	}
	text := string(l.src[start:l.pos])
	if !isFloat {
		if n, err := strconv.ParseInt(text, 10, 64); err == nil {
			return token{kind: tokNumber, text: text, num: n, line: line, col: col}, nil
		}
	}
	f, err := strconv.ParseFloat(text, 64)
	if err != nil {
		return token{}, l.errorf(line, col, "invalid number %q", text)
	}
	return token{kind: tokNumber, text: text, num: f, line: line, col: col}, nil
}

func (l *lexer) lexString(quote byte, line, col int) (token, error) {
	l.advance()
	var sb strings.Builder
	for {
		if l.pos >= len(l.src) || l.src[l.pos] == '\n' {
			return token{}, l.errorf(line, col, "unterminated string")
		}
		c := l.advance()
		if c == quote {
			return token{kind: tokString, text: sb.String(), line: line, col: col}, nil
		}
		if c != '\\' {
			sb.WriteByte(c)
			continue
		}
		if l.pos >= len(l.src) {
			return token{}, l.errorf(line, col, "unterminated string")
		}
		escLine, escCol := l.line, l.col
		e := l.advance()
		switch e {
		case 'n':
			sb.WriteByte('\n')
		case 'r':
			sb.WriteByte('\r')
		case 't':
			sb.WriteByte('\t')
		case 'a':
			sb.WriteByte('\a')
		case 'b':
			sb.WriteByte('\b')
		case 'f':
			sb.WriteByte('\f')
		case 'v':
			sb.WriteByte('\v')
		case '\\', '"', '\'', '\n':
			sb.WriteByte(e)
		default:
			if !isDigit(e) {
				return token{}, l.errorf(escLine, escCol, "invalid escape \\%c", e)
			}
			n := int(e - '0')
			for i := 0; i < 2 && isDigit(l.peekByte(0)); i++ {
				n = n*10 + int(l.advance()-'0')
			}
			if n > 255 {
				return token{}, l.errorf(escLine, escCol, "decimal escape too large")
			}
			sb.WriteByte(byte(n))
		}
	}
}
