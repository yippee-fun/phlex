# phlex-native

A C extension that serialises Phlex attributes. It needs the latest stable Ruby (currently 4.0). Add it to your Gemfile alongside `phlex` and Phlex will use it automatically:

```ruby
gem "phlex"
gem "phlex-native"
```

It produces exactly the same output, and raises exactly the same errors, as Phlex’s Ruby implementation. Anything it doesn’t handle natively (Sets, Dates, Times, subclasses of core types, objects with singleton methods, and so on) is handed back to Ruby. Each release depends on exactly one version of Phlex, the one whose Ruby it mirrors.

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
PHLEX_NATIVE=true PHLEX_NATIVE_STRESS=true bundle exec qt ./phlex-native/quickdraw/attributes.test.rb
```

## Releasing

1. Release Phlex first. This gem depends on exactly the version in `lib/phlex/version.rb`.
2. Bump `spec.version` in `phlex-native.gemspec`.
3. With Docker running (OrbStack works), from the repository root:

```sh
mise run native:package  # phlex-native/pkg: the source gem, and a precompiled gem for each platform
mise run native:release  # gem push each of them
```

The precompiled gems are cross-compiled with [rake-compiler-dock](https://github.com/rake-compiler/rake-compiler-dock), one platform at a time. The source gem compiles on install, for platforms without one.
