# phlex-native

A C extension that serialises Phlex attributes. It needs the latest stable Ruby (currently 4.0) and, because it compiles when it’s installed, a C compiler. Add it to your Gemfile alongside `phlex` and Phlex will use it automatically:

```ruby
gem "phlex"
gem "phlex-native"
```

It produces exactly the same output, and raises exactly the same errors, as Phlex’s Ruby implementation. Anything it doesn’t handle natively (Sets, Dates, Times, subclasses of core types, objects with singleton methods, and so on) is handed back to Ruby.

Each release depends on exactly one version of Phlex, the one whose Ruby it mirrors, and shares its version number: `phlex-native` 3.0.0 goes with `phlex` 3.0.0. A release that changes only this gem adds a fourth segment, such as 3.0.0.1.

With it loaded, Phlex no longer caches serialised attributes, because generating them natively is faster than looking them up.

It assumes core methods such as `String#gsub`, `Symbol#name`, `Integer#to_s`, `Float#to_s` and `Hash#each` haven’t been redefined globally, and that `Phlex::SGML::Attributes` and its methods haven’t been replaced or overridden.

## Development

From the repository root:

```sh
mise run setup        # installs phlex-native's build dependencies too
mise run native:test  # compiles phlex-native, then runs every test with it loaded
```

To build with AddressSanitizer and UndefinedBehaviorSanitizer, and run the differential tests while the GC compacts and runs constantly, use a Ruby built with AddressSanitizer, as the `native-sanitizers` CI job does:

```sh
(cd phlex-native && PHLEX_NATIVE_SANITIZE=true bundle exec rake compile)
PHLEX_NATIVE=true PHLEX_NATIVE_STRESS=true PHLEX_NATIVE_SANITIZE=true bundle exec qd ./phlex-native/quickdraw/attributes.test.rb
```

## Releasing

1. Release Phlex first. This gem takes its version from `lib/phlex/version.rb` and depends on exactly that version of Phlex.
2. Set `revision` in `phlex-native.gemspec`: `nil` for the first release with a new version of Phlex, then 1, 2 and so on for each release after it.
3. From the repository root:

```sh
mise run native:package  # builds the gem into phlex-native/pkg
mise run native:release  # pushes it to RubyGems
```
