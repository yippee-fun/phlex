# phlex-native

A C extension that serialises Phlex attributes. Add it to your Gemfile alongside `phlex` and Phlex will use it automatically:

```ruby
gem "phlex"
gem "phlex-native"
```

It produces exactly the same output, and raises exactly the same errors, as Phlex’s Ruby implementation. Anything it doesn’t handle natively (Sets, Dates, Times, subclasses of core types, objects with singleton methods, and so on) is handed back to Ruby.

With it loaded, Phlex no longer caches serialised attributes, because generating them natively is faster than looking them up.

It assumes core methods such as `String#gsub`, `Symbol#name`, `Integer#to_s`, `Float#to_s` and `Hash#each` haven’t been redefined globally, and that `Phlex::SGML::Attributes` and its methods haven’t been replaced or overridden.

## Development

From this directory:

```sh
bundle install
bundle exec rake compile
```

Then from the repository root:

```sh
PHLEX_NATIVE=true bundle exec qt
```

To build with AddressSanitizer and UndefinedBehaviorSanitizer, and run the differential tests while the GC compacts and runs constantly, use a Ruby built with AddressSanitizer, as the `native-sanitizers` CI job does:

```sh
PHLEX_NATIVE_SANITIZE=true bundle exec rake compile
PHLEX_NATIVE=true PHLEX_NATIVE_STRESS=true bundle exec qt ./phlex-native/quickdraw/attributes.test.rb
```

## Releasing

The precompiled gems are cross-compiled in Docker (OrbStack works) with [rake-compiler-dock](https://github.com/rake-compiler/rake-compiler-dock). Each one has a binary for every supported Ruby version. From this directory:

```sh
bundle exec rake gem             # pkg/phlex-native-VERSION.gem, compiled on install
bundle exec rake gem:native      # pkg/phlex-native-VERSION-PLATFORM.gem for every platform
```
