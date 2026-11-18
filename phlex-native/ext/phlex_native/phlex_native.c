// Native attribute serialisation for Phlex.
//
// Every function here mirrors a method in lib/phlex/sgml/attributes.rb and
// must produce byte-identical output. Anything outside the common path (Set,
// Date, Time, SafeObject, :style, subclasses, objects with singleton classes,
// non-ASCII top-level names, broken encodings, or anything the Ruby version
// would raise on) makes the whole call fall back to the Ruby implementation.

#include <ruby.h>
#include <ruby/encoding.h>
#include <limits.h>
#include <string.h>

#define MAX_DEPTH 32
#define PREFIX_CAPACITY 1024
#define NORMALIZED_CAPACITY 16

static ID id_to_s, id_unsafe_reference_p, id_Phlex, id_SGML, id_Attributes, id_SafeObject, id_SafeValue;
static VALUE sym_style, sym_id, sym_underscore;
static VALUE empty_string;
static int utf8_index, usascii_index;

// Resolved on first use, since Phlex::SGML is autoloaded after this extension.
static VALUE sgml_constant(VALUE *slot, ID name) {
	if (NIL_P(*slot)) {
		VALUE sgml = rb_const_get(rb_const_get(rb_cObject, id_Phlex), id_SGML);
		*slot = rb_const_get(sgml, name);
		rb_gc_register_mark_object(*slot);
	}
	return *slot;
}

static VALUE attributes_module = Qnil, safe_object_module = Qnil, safe_value_class = Qnil;

typedef struct {
	VALUE receiver;
	VALUE string;
	char *ptr;
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

static void output_init(output_t *o, VALUE receiver) {
	o->receiver = receiver;
	o->string = rb_str_buf_new(128);
	rb_enc_associate_index(o->string, utf8_index);
	o->ptr = RSTRING_PTR(o->string);
	o->length = 0;
	o->capacity = (long)rb_str_capacity(o->string);
	o->depth = 0;
}

static VALUE output_finish(output_t *o) {
	rb_str_set_len(o->string, o->length);
	ENC_CODERANGE_CLEAR(o->string);
	return o->string;
}

// Ruby raises the same error when a string would outgrow a long, which is 32 bits on Windows.
#define RAISE_TOO_BIG() rb_raise(rb_eArgError, "string size too big")

static void reserve(output_t *o, long n) {
	if (n > LONG_MAX - o->length) RAISE_TOO_BIG();
	if (o->length + n <= o->capacity) return;
	rb_str_set_len(o->string, o->length);
	rb_str_modify_expand(o->string, (o->length > n && o->length <= LONG_MAX / 2) ? o->length : n);
	o->ptr = RSTRING_PTR(o->string);
	o->capacity = (long)rb_str_capacity(o->string);
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

// Appends with `"` replaced by `&quot;`, and `_` by `-` when dasherizing.
// Space is reserved before reading, so nothing can allocate mid-copy.
static void put_value(output_t *o, const char *p, long n, int dasherize) {
	long quotes = 0;
	for (const char *q = p, *end = p + n; (q = memchr(q, '"', end - q)); q++) quotes++;

	if (!quotes && !(dasherize && memchr(p, '_', n))) {
		put(o, p, n);
		return;
	}

	if (quotes > (LONG_MAX - n) / 5) RAISE_TOO_BIG();
	reserve(o, n + quotes * 5);
	char *out = o->ptr + o->length;
	for (long i = 0; i < n; i++) {
		char c = p[i];
		if (c == '"') {
			memcpy(out, "&quot;", 6);
			out += 6;
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
		s = rb_funcall(v, id_to_s, 0);
		if (!plain_string_p(s) || !compatible_string(s) || memchr(RSTRING_PTR(s), '"', RSTRING_LEN(s))) return 0;
	} else {
		return 0;
	}
	put(o, RSTRING_PTR(s), RSTRING_LEN(s));
	RB_GC_GUARD(s);
	return 1;
}

static inline int safe_value_p(VALUE v) {
	return RB_TYPE_P(v, T_OBJECT) && RBASIC_CLASS(v) == sgml_constant(&safe_value_class, id_SafeValue);
}

static int put_scalar(output_t *o, VALUE v) {
	if (safe_value_p(v)) {
		VALUE s = rb_funcall(v, id_to_s, 0);
		if (!plain_string_p(s) || !compatible_string(s)) return 0;
		put_value(o, RSTRING_PTR(s), RSTRING_LEN(s), 0);
		RB_GC_GUARD(s);
		return 1;
	}
	if (plain_string_p(v)) {
		if (!compatible_string(v)) return 0;
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

static int nested_each(VALUE k, VALUE v, VALUE arg) {
	nested_t *nested = (nested_t *)arg;
	output_t *o = nested->output;
	if (!RTEST(v)) return ST_CONTINUE;

	long length;
	if (k == sym_underscore) {
		length = nested->prefix_length - 1;
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
			if (!compatible_string(declaration)) return 0;
			if (RSTRING_LEN(declaration) == 0) continue;
			put_declaration(o, declaration, start);
		} else if (safe_value_p(declaration)) {
			VALUE value = rb_funcall(declaration, id_to_s, 0);
			if (!plain_string_p(value) || !compatible_string(value)) return 0;
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

static int ref_attribute_p(const char *p, long n) {
	switch (n) {
		case 3: return memcmp(p, "src", 3) == 0;
		case 4: return memcmp(p, "href", 4) == 0 || memcmp(p, "ping", 4) == 0;
		case 6: return memcmp(p, "action", 6) == 0 || memcmp(p, "lowsrc", 6) == 0 || memcmp(p, "dynsrc", 6) == 0;
		case 9: return memcmp(p, "xlinkhref", 9) == 0;
		case 10: return memcmp(p, "formaction", 10) == 0 || memcmp(p, "background", 10) == 0;
		default: return 0;
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

// unsafe_reference? on the value written from `start`. The cheap check is the
// same one the Ruby version makes; anything it can't rule out goes to Ruby.
static int unsafe_reference_p(output_t *o, long start) {
	const char *p = o->ptr + start;
	long n = o->length - start;
	if (!memchr(p, '&', n) && !(memchr(p, ':', n) && (memchr(p, 'j', n) || memchr(p, 'J', n)))) return 0;
	return RTEST(rb_funcall(o->receiver, id_unsafe_reference_p, 1, rb_utf8_str_new(p, n)));
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

	if (reference && unsafe_reference_p(o, start)) {
		// Safe objects are never dropped, and anything can be made one.
		if (RTEST(rb_obj_is_kind_of(v, sgml_constant(&safe_object_module, id_SafeObject)))) return 0;
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
	if (!key_bytes(k, &p, &n, &dasherize)) goto fallback;

	// The name is copied out of the key so it can't move while the value is written.
	char stack_name[256];
	if (n > (long)sizeof stack_name) goto fallback;
	char *name = stack_name;

	char normalized[NORMALIZED_CAPACITY];
	long normalized_length = 0;
	int simple = n > 0, unsafe_char = 0, has_dash = 0;

	for (long i = 0; i < n; i++) {
		unsigned char c = (dasherize && p[i] == '_') ? '-' : (unsigned char)p[i];
		if (c >= 0x80) goto fallback;
		name[i] = c;
		if (!((c >= 'a' && c <= 'z') || c == '-')) simple = 0;
		if (unsafe_name_char_p(c)) unsafe_char = 1;
		unsigned char lower = (c >= 'A' && c <= 'Z') ? c + 32 : c;
		if ((lower >= 'a' && lower <= 'z') || lower == '-') {
			if (lower == '-') has_dash = 1;
			if (normalized_length < NORMALIZED_CAPACITY) normalized[normalized_length] = lower;
			normalized_length++;
		}
	}

	// Safe values may use event handler and other unsafe attribute names.
	if (!safe_value_p(v)) {
		if (normalized_length > 2 && normalized[0] == 'o' && normalized[1] == 'n' && !has_dash) goto fallback;
		if (normalized_length <= NORMALIZED_CAPACITY && unsafe_attribute_p(normalized, normalized_length)) goto fallback;
	}
	if (!simple && unsafe_char) goto fallback;
	if (n == 2 && (name[0] | 32) == 'i' && (name[1] | 32) == 'd' && k != sym_id) goto fallback;

	int reference = normalized_length <= NORMALIZED_CAPACITY && ref_attribute_p(normalized, normalized_length);
	if (!put_attribute(o, k, name, n, v, reference)) goto fallback;
	return ST_CONTINUE;

fallback:
	top->fallback = 1;
	return ST_STOP;
}

// The serialised attributes, or Qundef to fall back.
static VALUE generate(VALUE receiver, VALUE attributes) {
	if (!plain_hash_p(attributes)) return Qundef;
	output_t o;
	output_init(&o, receiver);
	nested_t top = { &o, 0, 0 };
	rb_hash_foreach(attributes, top_level_each, (VALUE)&top);
	return top.fallback ? Qundef : output_finish(&o);
}

// Phlex::Native::SerializedAttributes.fetch(attributes) { generate in Ruby }
// generate_attributes itself isn't prepended, so a fallback doesn't run the C twice.
static VALUE native_fetch(VALUE self, VALUE attributes) {
	VALUE result = generate(sgml_constant(&attributes_module, id_Attributes), attributes);
	return result == Qundef ? rb_yield_values(0) : result;
}

static VALUE serialize_validated(VALUE self, int argc, VALUE *argv, int reference) {
	rb_check_arity(argc, 3, 3);
	VALUE k = argv[0], name = argv[1], v = argv[2];
	if (!RTEST(v)) return empty_string;
	if (!plain_string_p(name) || !compatible_string(name)) return rb_call_super(argc, argv);

	output_t o;
	output_init(&o, self);
	char stack_name[256];
	long n = RSTRING_LEN(name);
	if (n > (long)sizeof stack_name) return rb_call_super(argc, argv);
	memcpy(stack_name, RSTRING_PTR(name), n);

	if (!put_attribute(&o, k, stack_name, n, v, reference)) return rb_call_super(argc, argv);
	// A dropped reference returns the literal "" in Ruby.
	if (reference && o.length == 0) return empty_string;
	return output_finish(&o);
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
	id_unsafe_reference_p = rb_intern("unsafe_reference?");
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

	empty_string = rb_obj_freeze(rb_utf8_str_new("", 0));
	rb_gc_register_mark_object(empty_string);

	VALUE mNative = rb_define_module_under(rb_define_module("Phlex"), "Native");

	// Prepended to Phlex::SGML::Attributes' singleton class.
	VALUE mNativeAttributes = rb_define_module_under(mNative, "Attributes");
	rb_define_method(mNativeAttributes, "attribute", native_attribute, -1);
	rb_define_method(mNativeAttributes, "reference_attribute", native_reference_attribute, -1);

	VALUE mSerializedAttributes = rb_define_module_under(mNative, "SerializedAttributes");
	rb_define_singleton_method(mSerializedAttributes, "fetch", native_fetch, 1);
}
