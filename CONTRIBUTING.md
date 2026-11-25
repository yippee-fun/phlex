# Contributing to Phlex

## Priorities

We’re trying to provide the best possible developer experience for the people using Phlex in their apps and the best possible performance for the users of those apps.

Phlex is incredibly complex and requires a lot of meta-programming but when you use it, it feels simple. Phlex views feel like plain old Ruby objects. You just subclass and define a couple of methods. That’s it. That’s how it should be.

## Setup

- Install dependencies `bundle install`
- Run the tests `bundle exec qd`

## Tests

Tests are written using [Quickdraw](https://github.com/joeldrapper/quickdraw) and placed in the `quickdraw` folder. You can run these tests with:

```
bundle exec qd
```

## C extension

`ext/phlex_native` serialises attributes in C. It must produce exactly the same output, and raise exactly the same errors, as the Ruby in `lib/phlex/sgml/attributes.rb`, handing anything uncommon back to Ruby. It assumes core methods such as `String#gsub` and `Hash#each` haven’t been redefined globally, and that `Phlex::SGML::Attributes` hasn’t been overridden.

`gem install phlex` builds it on CRuby 4.0 or later when a C compiler is available. Everywhere else, including JRuby, TruffleRuby and failed builds, the install still succeeds and Phlex uses Ruby. Setting `PHLEX_NATIVE=false` while installing skips it.

To run the tests with it loaded:

```
mise run native:test
```

To build it with AddressSanitizer and UndefinedBehaviorSanitizer and run the differential tests while the GC compacts and runs constantly, use a Ruby built with AddressSanitizer, as the `native-sanitizers` CI job does:

```
PHLEX_NATIVE_SANITIZE=true bundle exec rake compile
PHLEX_NATIVE=true PHLEX_NATIVE_STRESS=true PHLEX_NATIVE_SANITIZE=true bundle exec qd ./quickdraw/native/attributes.test.rb
```

Run `bundle exec rake clobber` afterwards, or the extension stays loaded for every test run.

## Documentation

Documentation is deployed when it’s merged into the `latest` branch with a release. But you can build and preview the docs locally by running `bin/docs`.
