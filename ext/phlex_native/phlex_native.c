// Native attribute serialisation for Phlex.
//
// Every function here mirrors a method in lib/phlex/sgml/attributes.rb and
// must produce byte-identical output. Anything outside the common path (Set,
// Date, Time, SafeObject, :style, subclasses, objects with singleton classes,
// non-ASCII top-level names, broken encodings, or anything the Ruby version
// would raise on) makes the whole call fall back to the Ruby implementation.

#include <ruby.h>
#include <ruby/encoding.h>
#include <ruby/ractor.h>
#include <limits.h>
#include <string.h>

#define MAX_DEPTH 32
#define PREFIX_CAPACITY 1024
#define NORMALIZED_CAPACITY 16

static ID id_to_s, id_lshift, id_unsafe_reference_p, id_unsafe_reference_list_p, id_Phlex, id_SGML, id_Attributes, id_SafeObject, id_SafeValue;
static VALUE sym_style, sym_id, sym_underscore;
static VALUE empty_string;
static int utf8_index, usascii_index;

// Set once by native_prepended, before any of them are read.
static VALUE attributes_module = Qnil, safe_object_module = Qnil, safe_value_class = Qnil;

typedef struct {
	VALUE receiver;
	VALUE string;
	char *ptr;
	// The string's length before anything was written.
	long base;
	long length;
	long capacity;
	int depth;
	char prefix[PREFIX_CAPACITY];
} output_t;

typedef struct {
	output_t *output;
	long prefix_length;
	int fallback;
} nested_t;

// Writes after the end of a plain, UTF-8 String, leaving its length alone
// until the output is finished, so Ruby run in the meantime, or an exception,
// sees the string as it was.
static void output_init(output_t *o, VALUE receiver, VALUE string) {
	o->receiver = receiver;
	o->string = string;
	// String#<< forgets a broken coderange, and keeps any other.
	int coderange = ENC_CODERANGE(string);
	rb_str_modify(string);
	if (coderange != ENC_CODERANGE_BROKEN) ENC_CODERANGE_SET(string, coderange);
	o->base = RSTRING_LEN(string);
	o->length = o->base;
	o->ptr = RSTRING_PTR(string);
	o->capacity = (long)rb_str_capacity(string);
	o->depth = 0;
}

// rb_str_set_len works out the coderange of what was written, as String#<< would.
static inline void output_finish(output_t *o) {
	rb_str_set_len(o->string, o->length);
}

// Whether `string` is the output, which can move as it grows, so it can't be copied into itself.
static inline int output_p(output_t *o, VALUE string) {
	return string == o->string;
}

typedef struct {
	VALUE receiver;
	ID method;
	VALUE argument;
	int argc;
} call_t;

static VALUE run_call(VALUE arg) {
	call_t *c = (call_t *)arg;
	return rb_funcallv(c->receiver, c->method, c->argc, &c->argument);
}

// Ruby sees the string terminated where it was, and anything that changes it
// in the meantime is refused, since what's been written would be lost. Only
// Phlex's own methods and Float#to_s are called, so growing the string and
// shrinking it back, which this can't see, would take a redefinition.
static VALUE output_call(output_t *o, VALUE receiver, ID method, int argc, VALUE argument) {
	char first = o->ptr[o->base];
	o->ptr[o->base] = '\0';
	call_t c = { receiver, method, argument, argc };
	VALUE result = run_call((VALUE)&c);
	if (RSTRING_PTR(o->string) != o->ptr || RSTRING_LEN(o->string) != o->base || (long)rb_str_capacity(o->string) != o->capacity ||
		OBJ_FROZEN(o->string) || ENCODING_GET(o->string) != utf8_index) {
		rb_raise(rb_eRuntimeError, "the buffer changed while attributes were written to it");
	}
	o->ptr[o->base] = first;
	RB_GC_GUARD(result);
	return result;
}

typedef struct {
	output_t *output;
	long expand;
} expand_t;

static VALUE run_expand(VALUE arg) {
	expand_t *e = (expand_t *)arg;
	rb_str_set_len(e->output->string, e->output->length);
	rb_str_modify_expand(e->output->string, e->expand);
	return Qnil;
}

// Ruby raises the same error when a string would outgrow a long, which is 32 bits on Windows.
#define RAISE_TOO_BIG() rb_raise(rb_eArgError, "string size too big")

// Growing keeps what's been written, so it's committed while the string
// grows, and the string is put back as it was afterwards, even on an exception.
static void reserve(output_t *o, long n) {
	if (n > LONG_MAX - o->length) RAISE_TOO_BIG();
	if (o->length + n <= o->capacity) return;
	VALUE string = o->string;
	int coderange = ENC_CODERANGE(string);
	char first = o->ptr[o->base];
	// Cleared, so committing doesn't scan what's been written.
	ENC_CODERANGE_CLEAR(string);
	expand_t e = { o, (o->length > n && o->length <= LONG_MAX / 2) ? o->length : n };
	int state = 0;
	rb_protect(run_expand, (VALUE)&e, &state);
	rb_str_set_len(string, o->base);
	o->ptr = RSTRING_PTR(string);
	o->capacity = (long)rb_str_capacity(string);
	o->ptr[o->base] = first;
	ENC_CODERANGE_SET(string, coderange);
	if (state) {
		o->ptr[o->base] = '\0';
		rb_jump_tag(state);
	}
}

static inline void put(output_t *o, const char *p, long n) {
	reserve(o, n);
	memcpy(o->ptr + o->length, p, n);
	o->length += n;
}

#define PUT_LITERAL(o, literal) put(o, literal, sizeof(literal) - 1)

static inline void put_char(output_t *o, char c) {
	reserve(o, 1);
	o->ptr[o->length++] = c;
}

static long count_byte(const char *p, long n, char c) {
	long count = 0;
	for (const char *q = p, *end = p + n; (q = memchr(q, c, end - q)); q++) count++;
	return count;
}

// Appends with `"`, `<` and `>` replaced by `&quot;`, `&lt;` and `&gt;`, and
// `_` by `-` when dasherizing, as UNSAFE_VALUE_CHARS and VALUE_ESCAPES do.
// Space is reserved before reading, so nothing can allocate mid-copy.
static void put_value(output_t *o, const char *p, long n, int dasherize) {
	long quotes = count_byte(p, n, '"');
	long angles = count_byte(p, n, '<') + count_byte(p, n, '>');

	if (!quotes && !angles && !(dasherize && memchr(p, '_', n))) {
		put(o, p, n);
		return;
	}

	if (quotes > (LONG_MAX - n) / 5 || angles > (LONG_MAX - n - quotes * 5) / 3) RAISE_TOO_BIG();
	reserve(o, n + quotes * 5 + angles * 3);
	char *out = o->ptr + o->length;
	for (long i = 0; i < n; i++) {
		char c = p[i];
		if (c == '"') {
			memcpy(out, "&quot;", 6);
			out += 6;
		} else if (c == '<') {
			memcpy(out, "&lt;", 4);
			out += 4;
		} else if (c == '>') {
			memcpy(out, "&gt;", 4);
			out += 4;
		} else {
			*out++ = (dasherize && c == '_') ? '-' : c;
		}
	}
	o->length = out - o->ptr;
}

// A String the Ruby version would append to its UTF-8 buffer without raising
// or changing the buffer's encoding.
static inline int compatible_string(VALUE s) {
	int index = ENCODING_GET(s);
	int coderange = rb_enc_str_coderange(s);
	if (coderange == ENC_CODERANGE_BROKEN) return 0;
	if (index == utf8_index || index == usascii_index) return 1;
	return coderange == ENC_CODERANGE_7BIT && rb_enc_asciicompat(rb_enc_from_index(index));
}

static inline int plain_string_p(VALUE v) {
	return RB_TYPE_P(v, T_STRING) && RBASIC_CLASS(v) == rb_cString;
}

static inline int plain_hash_p(VALUE v) {
	return RB_TYPE_P(v, T_HASH) && RBASIC_CLASS(v) == rb_cHash;
}

static inline int plain_array_p(VALUE v) {
	return RB_TYPE_P(v, T_ARRAY) && RBASIC_CLASS(v) == rb_cArray;
}

// The bytes of a String or Symbol key, and whether `_` becomes `-`.
static int key_bytes(VALUE k, const char **p, long *n, int *dasherize) {
	VALUE s;
	if (SYMBOL_P(k)) {
		s = rb_sym2str(k);
		*dasherize = 1;
	} else if (plain_string_p(k)) {
		s = k;
		*dasherize = 0;
	} else {
		return 0;
	}
	if (!compatible_string(s)) return 0;
	*p = RSTRING_PTR(s);
	*n = RSTRING_LEN(s);
	return 1;
}

static inline int unsafe_name_char_p(unsigned char c) {
	switch (c) {
		case '<': case '>': case '&': case '"': case '\'': case '/': case '=':
		case ' ': case '\t': case '\n': case '\v': case '\f': case '\r': case 0:
			return 1;
		default:
			return 0;
	}
}

// Integer and Float values. Strings and Symbols are handled by the callers
// because the two differ in whether `_` is dasherized.
static int put_number(output_t *o, VALUE v) {
	if (FIXNUM_P(v)) {
		char digits[24];
		int n = snprintf(digits, sizeof digits, "%ld", FIX2LONG(v));
		put(o, digits, n);
		return 1;
	}

	VALUE s;
	if (RB_TYPE_P(v, T_BIGNUM) && RBASIC_CLASS(v) == rb_cInteger) {
		s = rb_big2str(v, 10);
	} else if (RB_FLOAT_TYPE_P(v)) {
		s = output_call(o, v, id_to_s, 0, Qnil);
		if (!plain_string_p(s) || output_p(o, s) || !compatible_string(s) || memchr(RSTRING_PTR(s), '"', RSTRING_LEN(s))) return 0;
	} else {
		return 0;
	}
	put(o, RSTRING_PTR(s), RSTRING_LEN(s));
	RB_GC_GUARD(s);
	return 1;
}

static inline int safe_value_p(VALUE v) {
	return RB_TYPE_P(v, T_OBJECT) && RBASIC_CLASS(v) == safe_value_class;
}

static int put_scalar(output_t *o, VALUE v) {
	if (safe_value_p(v)) {
		VALUE s = output_call(o, v, id_to_s, 0, Qnil);
		if (!plain_string_p(s) || output_p(o, s) || !compatible_string(s)) return 0;
		put_value(o, RSTRING_PTR(s), RSTRING_LEN(s), 0);
		RB_GC_GUARD(s);
		return 1;
	}
	if (plain_string_p(v)) {
		if (output_p(o, v) || !compatible_string(v)) return 0;
		put_value(o, RSTRING_PTR(v), RSTRING_LEN(v), 0);
		RB_GC_GUARD(v);
		return 1;
	}
	if (SYMBOL_P(v)) {
		VALUE s = rb_sym2str(v);
		if (!compatible_string(s)) return 0;
		put_value(o, RSTRING_PTR(s), RSTRING_LEN(s), 1);
		RB_GC_GUARD(s);
		return 1;
	}
	return put_number(o, v);
}

// generate_nested_tokens, written from `start`. Emptiness is relative to `start`.
static int put_tokens(output_t *o, VALUE tokens, long start) {
	if (++o->depth > MAX_DEPTH) return 0;

	for (long i = 0, length = RARRAY_LEN(tokens); i < length; i++) {
		VALUE token = rb_ary_entry(tokens, i);
		if (!RTEST(token)) continue;

		if (plain_array_p(token)) {
			if (RARRAY_LEN(token) == 0) continue;
			long mark = o->length;
			if (mark > start) put_char(o, ' ');
			long inner = o->length;
			if (!put_tokens(o, token, inner)) return 0;
			if (o->length == inner) o->length = mark;
			continue;
		}

		if (o->length > start) put_char(o, ' ');
		if (!put_scalar(o, token)) return 0;
	}

	o->depth--;
	return 1;
}

static int put_nested(output_t *o, VALUE hash, long prefix_length);
static int unsafe_attribute_p(const char *p, long n);

// Whether Ruby must check a nested name joined to its base: it normalises to
// an unsafe name, such as `http-equiv`, or isn't ASCII, which Ruby downcases.
static int nested_name_needs_ruby_p(const char *name, long n) {
	// With a namespace prefix, the local name could be a reference, which Ruby refuses.
	if (memchr(name, ':', n)) return 1;

	char normalized[NORMALIZED_CAPACITY];
	long normalized_length = 0;

	for (long i = 0; i < n; i++) {
		unsigned char c = (unsigned char)name[i];
		if (c >= 0x80) return 1;
		unsigned char lower = (c >= 'A' && c <= 'Z') ? c + 32 : c;
		if ((lower >= 'a' && lower <= 'z') || lower == '-') {
			if (normalized_length == NORMALIZED_CAPACITY) return 0;
			normalized[normalized_length++] = lower;
		}
	}

	return unsafe_attribute_p(normalized, normalized_length);
}

static int nested_each(VALUE k, VALUE v, VALUE arg) {
	nested_t *nested = (nested_t *)arg;
	output_t *o = nested->output;
	if (!RTEST(v)) return ST_CONTINUE;

	long length;
	if (k == sym_underscore) {
		length = nested->prefix_length - 1;
		// The base on its own is a name too, which Ruby checks as it emits it.
		if (!safe_value_p(v) && nested_name_needs_ruby_p(o->prefix, length)) goto fallback;
	} else {
		const char *p;
		long n;
		int dasherize;
		if (!key_bytes(k, &p, &n, &dasherize)) goto fallback;
		if (n > PREFIX_CAPACITY - 1 - nested->prefix_length) goto fallback;
		char *name = o->prefix + nested->prefix_length;
		for (long i = 0; i < n; i++) {
			if (unsafe_name_char_p(p[i])) goto fallback;
			name[i] = (dasherize && p[i] == '_') ? '-' : p[i];
		}
		length = nested->prefix_length + n;
		if (!safe_value_p(v) && nested_name_needs_ruby_p(o->prefix, length)) goto fallback;
	}

	if (v == Qtrue) {
		put_char(o, ' ');
		put(o, o->prefix, length);
	} else if (plain_hash_p(v)) {
		o->prefix[length] = '-';
		if (!put_nested(o, v, length + 1)) goto fallback;
	} else if (plain_array_p(v)) {
		long mark = o->length;
		put_char(o, ' ');
		put(o, o->prefix, length);
		PUT_LITERAL(o, "=\"");
		long start = o->length;
		if (!put_tokens(o, v, start)) goto fallback;
		if (o->length == start) o->length = mark;
		else put_char(o, '"');
	} else {
		put_char(o, ' ');
		put(o, o->prefix, length);
		PUT_LITERAL(o, "=\"");
		if (!put_scalar(o, v)) goto fallback;
		put_char(o, '"');
	}
	return ST_CONTINUE;

fallback:
	nested->fallback = 1;
	return ST_STOP;
}

static int put_nested(output_t *o, VALUE hash, long prefix_length) {
	if (++o->depth > MAX_DEPTH) return 0;
	nested_t nested = { o, prefix_length, 0 };
	rb_hash_foreach(hash, nested_each, (VALUE)&nested);
	o->depth--;
	return !nested.fallback;
}

typedef struct {
	output_t *output;
	long start;
	int fallback;
} styles_t;

// One `property: value;` from generate_styles with a Hash. Ruby checks the
// key before it skips a nil value, so the key is checked first here too.
static int style_each(VALUE k, VALUE v, VALUE arg) {
	styles_t *styles = (styles_t *)arg;
	output_t *o = styles->output;

	VALUE property;
	int dasherize;
	if (SYMBOL_P(k)) {
		property = rb_sym2str(k);
		dasherize = 1;
	} else if (plain_string_p(k)) {
		property = k;
		dasherize = 0;
	} else {
		goto fallback;
	}
	if (!compatible_string(property)) goto fallback;

	if (!RTEST(v)) return ST_CONTINUE;

	if (o->length > styles->start) put_char(o, ' ');
	put_value(o, RSTRING_PTR(property), RSTRING_LEN(property), dasherize);
	RB_GC_GUARD(property);
	PUT_LITERAL(o, ": ");
	if (!put_scalar(o, v)) goto fallback;
	put_char(o, ';');
	return ST_CONTINUE;

fallback:
	styles->fallback = 1;
	return ST_STOP;
}

// generate_styles with a Hash, written from `start`.
static int put_style_hash(output_t *o, VALUE hash, long start) {
	styles_t styles = { o, start, 0 };
	rb_hash_foreach(hash, style_each, (VALUE)&styles);
	return !styles.fallback;
}

// A String or safe value from a style Array, with `;` added unless it ends with one.
static void put_declaration(output_t *o, VALUE declaration, long start) {
	const char *p = RSTRING_PTR(declaration);
	long n = RSTRING_LEN(declaration);
	int terminated = n > 0 && p[n - 1] == ';';

	if (o->length > start) put_char(o, ' ');
	put_value(o, p, n, 0);
	RB_GC_GUARD(declaration);
	if (!terminated) put_char(o, ';');
}

// generate_styles with an Array, written from `start`. Like Array#each, the
// length is read on every iteration.
static int put_style_array(output_t *o, VALUE declarations, long start) {
	for (long i = 0; i < RARRAY_LEN(declarations); i++) {
		VALUE declaration = RARRAY_AREF(declarations, i);
		if (!RTEST(declaration)) continue;

		if (plain_string_p(declaration)) {
			if (output_p(o, declaration) || !compatible_string(declaration)) return 0;
			if (RSTRING_LEN(declaration) == 0) continue;
			put_declaration(o, declaration, start);
		} else if (safe_value_p(declaration)) {
			VALUE value = output_call(o, declaration, id_to_s, 0, Qnil);
			if (!plain_string_p(value) || output_p(o, value) || !compatible_string(value)) return 0;
			put_declaration(o, value, start);
		} else if (plain_hash_p(declaration)) {
			long mark = o->length;
			if (mark > start) put_char(o, ' ');
			long inner = o->length;
			if (!put_style_hash(o, declaration, inner)) return 0;
			if (o->length == inner) o->length = mark;
		} else {
			return 0;
		}
	}
	return 1;
}

// What REF_ATTRIBUTES and REF_LIST_ATTRIBUTES make of a normalised name.
#define NOT_REFERENCE 0
#define REFERENCE 1
#define REFERENCE_LIST 2
// `data`, a reference unless its value is a Hash, which expands into `data-*` attributes.
#define DATA_REFERENCE 3

static int reference_kind(const char *p, long n) {
	switch (n) {
		case 2: return (memcmp(p, "to", 2) == 0 || memcmp(p, "by", 2) == 0) ? REFERENCE : NOT_REFERENCE;
		case 3: return memcmp(p, "src", 3) == 0 ? REFERENCE : NOT_REFERENCE;
		case 4:
			if (memcmp(p, "data", 4) == 0) return DATA_REFERENCE;
			return (memcmp(p, "href", 4) == 0 || memcmp(p, "ping", 4) == 0 || memcmp(p, "from", 4) == 0) ? REFERENCE : NOT_REFERENCE;
		case 6:
			if (memcmp(p, "values", 6) == 0) return REFERENCE_LIST;
			return (memcmp(p, "action", 6) == 0 || memcmp(p, "lowsrc", 6) == 0 || memcmp(p, "dynsrc", 6) == 0) ? REFERENCE : NOT_REFERENCE;
		case 9: return memcmp(p, "xlinkhref", 9) == 0 ? REFERENCE : NOT_REFERENCE;
		case 10: return (memcmp(p, "formaction", 10) == 0 || memcmp(p, "background", 10) == 0) ? REFERENCE : NOT_REFERENCE;
		default: return NOT_REFERENCE;
	}
}

static int unsafe_attribute_p(const char *p, long n) {
	switch (n) {
		case 6: return memcmp(p, "srcdoc", 6) == 0;
		case 7: return memcmp(p, "sandbox", 7) == 0;
		case 10: return memcmp(p, "http-equiv", 10) == 0;
		default: return 0;
	}
}

// unsafe_reference? (or unsafe_reference_list? for a list) on the value written
// from `start`. The cheap check is the same one the Ruby version makes; anything
// it can't rule out goes to Ruby.
static int unsafe_reference_p(output_t *o, long start, int kind) {
	const char *p = o->ptr + start;
	long n = o->length - start;
	if (!memchr(p, '&', n) && !(memchr(p, ':', n) && (memchr(p, 'j', n) || memchr(p, 'J', n)))) return 0;
	ID check = kind == REFERENCE_LIST ? id_unsafe_reference_list_p : id_unsafe_reference_p;
	return RTEST(output_call(o, o->receiver, check, 1, rb_utf8_str_new(p, n)));
}

// One attribute whose name has passed the top-level checks.
static int put_attribute(output_t *o, VALUE k, const char *name, long name_length, VALUE v, int reference) {
	if (reference && safe_value_p(v)) reference = 0;

	if (v == Qtrue) {
		put_char(o, ' ');
		put(o, name, name_length);
		return 1;
	}

	int hash = plain_hash_p(v);

	if (k == sym_style && !reference && (hash || plain_array_p(v))) {
		long mark = o->length;
		put_char(o, ' ');
		put(o, name, name_length);
		PUT_LITERAL(o, "=\"");
		long start = o->length;
		if (!(hash ? put_style_hash(o, v, start) : put_style_array(o, v, start))) return 0;
		// generate_styles returns nil when there are no declarations.
		if (o->length == start) o->length = mark;
		else put_char(o, '"');
		return 1;
	}

	if (hash) {
		if (k == sym_style || reference || name_length + 1 > PREFIX_CAPACITY) return 0;
		memcpy(o->prefix, name, name_length);
		o->prefix[name_length] = '-';
		return put_nested(o, v, name_length + 1);
	}

	long mark = o->length;
	put_char(o, ' ');
	put(o, name, name_length);
	PUT_LITERAL(o, "=\"");
	long start = o->length;

	if (plain_array_p(v)) {
		if (k == sym_style || !put_tokens(o, v, start)) return 0;
		if (o->length == start) {
			// drop_reference? raises on the nil an empty token list produces.
			if (reference) return 0;
			o->length = mark;
			return 1;
		}
	} else if (!put_scalar(o, v)) {
		return 0;
	}

	if (reference && unsafe_reference_p(o, start, reference)) {
		// Only safe values are never dropped, and Ruby decides for anything that's one.
		if (RTEST(rb_obj_is_kind_of(v, safe_value_class))) return 0;
		o->length = mark;
		return 1;
	}

	put_char(o, '"');
	return 1;
}

static int top_level_each(VALUE k, VALUE v, VALUE arg) {
	nested_t *top = (nested_t *)arg;
	output_t *o = top->output;
	if (!RTEST(v)) return ST_CONTINUE;

	const char *p;
	long n;
	int dasherize;
	if (!key_bytes(k, &p, &n, &dasherize) || n == 0) goto fallback;

	// The name is copied out of the key so it can't move while the value is written.
	char stack_name[256];
	if (n > (long)sizeof stack_name) goto fallback;
	char *name = stack_name;

	char normalized[NORMALIZED_CAPACITY];
	long normalized_length = 0;
	// The normalised local name, after the last `:`, which decides whether it's a reference.
	char local[NORMALIZED_CAPACITY];
	long local_length = 0;
	int simple = n > 0, unsafe_char = 0, has_dash = 0;

	for (long i = 0; i < n; i++) {
		unsigned char c = (dasherize && p[i] == '_') ? '-' : (unsigned char)p[i];
		if (c >= 0x80) goto fallback;
		name[i] = c;
		if (!((c >= 'a' && c <= 'z') || c == '-')) simple = 0;
		if (unsafe_name_char_p(c)) unsafe_char = 1;
		if (c == ':') local_length = 0;
		unsigned char lower = (c >= 'A' && c <= 'Z') ? c + 32 : c;
		if ((lower >= 'a' && lower <= 'z') || lower == '-') {
			if (lower == '-') has_dash = 1;
			if (normalized_length < NORMALIZED_CAPACITY) normalized[normalized_length] = lower;
			normalized_length++;
			if (local_length < NORMALIZED_CAPACITY) local[local_length] = lower;
			local_length++;
		}
	}

	// Safe values may use event handler and other unsafe attribute names.
	if (!safe_value_p(v)) {
		if (normalized_length > 2 && normalized[0] == 'o' && normalized[1] == 'n' && !has_dash) goto fallback;
		if (normalized_length <= NORMALIZED_CAPACITY && unsafe_attribute_p(normalized, normalized_length)) goto fallback;
	}
	if (!simple && unsafe_char) goto fallback;
	if (n == 2 && (name[0] | 32) == 'i' && (name[1] | 32) == 'd' && k != sym_id) goto fallback;

	int reference = local_length <= NORMALIZED_CAPACITY ? reference_kind(local, local_length) : NOT_REFERENCE;
	// Anything that isn't a plain Hash or a scalar falls back to Ruby anyway.
	if (reference == DATA_REFERENCE) reference = plain_hash_p(v) ? NOT_REFERENCE : REFERENCE;
	if (!put_attribute(o, k, name, n, v, reference)) goto fallback;
	return ST_CONTINUE;

fallback:
	top->fallback = 1;
	return ST_STOP;
}

static VALUE new_output_string(void) {
	VALUE string = rb_str_buf_new(128);
	rb_enc_associate_index(string, utf8_index);
	ENC_CODERANGE_SET(string, ENC_CODERANGE_7BIT);
	return string;
}

// Writes the serialised attributes after the end of `string`, or returns 0
// to fall back, leaving it as it was.
static int generate(output_t *o, VALUE attributes) {
	nested_t top = { o, 0, 0 };
	rb_hash_foreach(attributes, top_level_each, (VALUE)&top);
	if (top.fallback) {
		o->ptr[o->base] = '\0';
		return 0;
	}
	output_finish(o);
	return 1;
}

typedef struct {
	output_t *output;
	VALUE attributes;
} generate_t;

static VALUE run_generate(VALUE arg) {
	generate_t *g = (generate_t *)arg;
	return generate(g->output, g->attributes) ? Qtrue : Qfalse;
}

static inline int appendable_p(VALUE buffer) {
	return plain_string_p(buffer) && ENCODING_GET(buffer) == utf8_index && !OBJ_FROZEN(buffer);
}

// Phlex::Native::SerializedAttributes.fetch(attributes) { generate in Ruby }
// generate_attributes itself isn't prepended, so a fallback doesn't run the C twice.
static VALUE native_fetch(VALUE self, VALUE attributes) {
	// The block loads Phlex::SGML::Attributes, which prepends Phlex::Native::Attributes.
	if (NIL_P(attributes_module) || !plain_hash_p(attributes)) return rb_yield_values(0);

	output_t o;
	output_init(&o, attributes_module, new_output_string());
	return generate(&o, attributes) ? o.string : rb_yield_values(0);
}

// Phlex::Native::SerializedAttributes.append(buffer, attributes) { generate in Ruby }
// The same as `buffer << fetch(attributes) { ... }`, without the intermediate String.
static VALUE native_append(VALUE self, VALUE buffer, VALUE attributes) {
	if (NIL_P(attributes_module) || !plain_hash_p(attributes) || !appendable_p(buffer)) {
		VALUE result = native_fetch(self, attributes);
		if (plain_string_p(buffer)) rb_str_concat(buffer, result);
		else rb_funcall(buffer, id_lshift, 1, result);
		return buffer;
	}

	output_t o;
	output_init(&o, attributes_module, buffer);
	generate_t g = { &o, attributes };
	int state = 0;
	VALUE written = rb_protect(run_generate, (VALUE)&g, &state);
	if (state) {
		// Terminated again where it was, unless Ruby changed it.
		if (RSTRING_PTR(buffer) == o.ptr && RSTRING_LEN(buffer) == o.base && (long)rb_str_capacity(buffer) == o.capacity) o.ptr[o.base] = '\0';
		rb_jump_tag(state);
	}
	if (!RTEST(written)) rb_str_concat(buffer, rb_yield_values(0));
	return buffer;
}

// Phlex::Native::Attributes.prepended(base), called once when attributes.rb
// loads, so the constants are set before anything reads them and no Ractor
// ever writes them.
static VALUE native_prepended(VALUE self, VALUE base) {
	VALUE sgml = rb_const_get(rb_const_get(rb_cObject, id_Phlex), id_SGML);
	safe_object_module = rb_const_get(sgml, id_SafeObject);
	safe_value_class = rb_const_get(sgml, id_SafeValue);
	rb_gc_register_mark_object(safe_object_module);
	rb_gc_register_mark_object(safe_value_class);

	VALUE attributes = rb_const_get(sgml, id_Attributes);
	rb_gc_register_mark_object(attributes);
	attributes_module = attributes;

	return rb_call_super(1, &base);
}

static VALUE serialize_validated(VALUE self, int argc, VALUE *argv, int reference) {
	rb_check_arity(argc, 3, 3);
	VALUE k = argv[0], name = argv[1], v = argv[2];
	if (!RTEST(v)) return empty_string;
	if (!plain_string_p(name) || !compatible_string(name)) return rb_call_super(argc, argv);

	char stack_name[256];
	long n = RSTRING_LEN(name);
	if (n > (long)sizeof stack_name) return rb_call_super(argc, argv);
	memcpy(stack_name, RSTRING_PTR(name), n);

	// The compiler only calls reference_attribute for reference names, but
	// which kind of reference this is depends on the name, which Ruby
	// normalises with a Unicode-aware downcase.
	if (reference) {
		char normalized[NORMALIZED_CAPACITY];
		long normalized_length = 0;
		for (long i = 0; i < n; i++) {
			unsigned char c = (unsigned char)stack_name[i];
			if (c >= 0x80) return rb_call_super(argc, argv);
			// As in Ruby, only the local name, after the last `:`, counts.
			if (c == ':') normalized_length = 0;
			unsigned char lower = (c >= 'A' && c <= 'Z') ? c + 32 : c;
			if ((lower >= 'a' && lower <= 'z') || lower == '-') {
				if (normalized_length < NORMALIZED_CAPACITY) normalized[normalized_length] = lower;
				normalized_length++;
			}
		}
		if (normalized_length == 6 && memcmp(normalized, "values", 6) == 0) reference = REFERENCE_LIST;
	}

	output_t o;
	output_init(&o, self, new_output_string());
	if (!put_attribute(&o, k, stack_name, n, v, reference)) return rb_call_super(argc, argv);
	// A dropped reference returns the literal "" in Ruby.
	if (reference && o.length == 0) return empty_string;
	output_finish(&o);
	return o.string;
}

// Phlex::SGML::Attributes.attribute(k, name, v)
static VALUE native_attribute(int argc, VALUE *argv, VALUE self) {
	return serialize_validated(self, argc, argv, 0);
}

// Phlex::SGML::Attributes.reference_attribute(k, name, v)
static VALUE native_reference_attribute(int argc, VALUE *argv, VALUE self) {
	return serialize_validated(self, argc, argv, 1);
}

void Init_phlex_native(void) {
	rb_ext_ractor_safe(true);

	id_to_s = rb_intern("to_s");
	id_lshift = rb_intern("<<");
	id_unsafe_reference_p = rb_intern("unsafe_reference?");
	id_unsafe_reference_list_p = rb_intern("unsafe_reference_list?");
	id_Phlex = rb_intern("Phlex");
	id_SGML = rb_intern("SGML");
	id_Attributes = rb_intern("Attributes");
	id_SafeObject = rb_intern("SafeObject");
	id_SafeValue = rb_intern("SafeValue");
	sym_style = ID2SYM(rb_intern("style"));
	sym_id = ID2SYM(rb_intern("id"));
	sym_underscore = ID2SYM(rb_intern("_"));
	utf8_index = rb_utf8_encindex();
	usascii_index = rb_usascii_encindex();

	empty_string = rb_ractor_make_shareable(rb_utf8_str_new("", 0));
	rb_gc_register_mark_object(empty_string);

	VALUE mNative = rb_define_module_under(rb_define_module("Phlex"), "Native");

	// Prepended to Phlex::SGML::Attributes' singleton class.
	VALUE mNativeAttributes = rb_define_module_under(mNative, "Attributes");
	rb_define_method(mNativeAttributes, "attribute", native_attribute, -1);
	rb_define_method(mNativeAttributes, "reference_attribute", native_reference_attribute, -1);
	rb_define_singleton_method(mNativeAttributes, "prepended", native_prepended, 1);

	VALUE mSerializedAttributes = rb_define_module_under(mNative, "SerializedAttributes");
	rb_define_singleton_method(mSerializedAttributes, "fetch", native_fetch, 1);
	rb_define_singleton_method(mSerializedAttributes, "append", native_append, 2);
}
