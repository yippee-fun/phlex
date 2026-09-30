# Phlex

[![Ruby Users Forum](https://img.shields.io/discourse/topics?server=https%3A%2F%2Fwww.rubyforum.org&style=flat&logo=discourse&label=Ruby%20Users%20Forum)](https://www.rubyforum.org/tag/phlex)

Phlex lets you build object-oriented web views in pure Ruby.

- [v2 Docs](https://www.phlex.fun)
- [v1 Docs](https://v1.phlex.fun)

## Troubleshooting

### Remote debugging with Puma

If attaching the Ruby debugger to a Puma request already stopped at `debugger`
produces `Stop by SIGURG`, jumps to `Puma::Single#run`, or leaves the server
unresponsive, attach without requesting another pause:

```sh
bundle exec rdbg --attach --nonstop
```

Restart the server first if it is already unresponsive. Wait until it reports
`wait for debugger connection...` before attaching.
You can then evaluate expressions and use `continue` to resume the request.
The `--nonstop` option skips the extra pause on attachment; it does not disable
your breakpoints. If you attach before a breakpoint is reached, the application
keeps running until it hits one, or you press Ctrl-C in the debugger to pause it.

This is a workaround for an [upstream ruby/debug issue](https://github.com/ruby/debug/issues/1121)
that also reproduces without Phlex. See [Phlex #958](https://github.com/yippee-fun/phlex/issues/958)
and [Puma #3627](https://github.com/puma/puma/issues/3627) for the related reports.

## Community

Join us in the `phlex` tag on the [Ruby Users Forum](https://www.rubyforum.org/tag/phlex).

## Versioning and Maintenance

Phlex does not follow Semantic Versioning (SemVer). Instead, we follow [BreakVer](https://www.taoensso.com/break-versioning).

### Security

When a security issue is brought to our attention, we aim to release patches as soon as possible. We aim to patch with a new `non-breaking` version:

- every `minor` version that was released in the last year;
- the latest `minor` version of the latest two `major` versions, even if over a year old; and
- the `main` branch in GitHub.
