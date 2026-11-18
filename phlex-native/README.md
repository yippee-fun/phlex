# phlex-native

A C extension that serialises Phlex attributes. Add it to your Gemfile alongside `phlex` and Phlex will use it automatically:

```ruby
gem "phlex"
gem "phlex-native"
```

It produces exactly the same output, and raises exactly the same errors, as Phlex’s Ruby implementation. Anything it doesn’t handle natively (Sets, Dates, Times, safe objects, `style:` hashes, subclasses of core types, objects with singleton methods, and so on) is handed back to Ruby.

With it loaded, Phlex no longer caches serialised attributes, because generating them natively is faster than looking them up.

It assumes core methods such as `String#gsub`, `Symbol#name`, `Integer#to_s`, `Float#to_s` and `Hash#each` haven’t been redefined globally, and that `Phlex::SGML::Attributes` and its methods haven’t been replaced or overridden.

## Development

```sh
rake compile
PHLEX_NATIVE=true bundle exec qt # from the repository root
```
