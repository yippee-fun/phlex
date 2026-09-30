# Contributing to Phlex

## Priorities

We’re trying to provide the best possible developer experience for the people using Phlex in their apps and the best possible performance for the users of those apps.

Phlex is incredibly complex and requires a lot of meta-programming but when you use it, it feels simple. Phlex views feel like plain old Ruby objects. You just subclass and define a couple of methods. That’s it. That’s how it should be.

## Setup

- Install dependencies `bundle install`
- Run the tests `bundle exec qt`

## Tests

Tests are written using [Quickdraw](https://github.com/joeldrapper/quickdraw) and placed in the `quickdraw` folder. You can run these tests with:

```
bundle exec qt
```

## Documentation

Documentation is deployed when it’s merged into the `latest` branch with a release. But you can build and preview the docs locally by running `bin/docs`.
