# Phlex 2.4.3 vs 3.0

Five pages, each rendered by five configurations in separate processes. `compare.rb` alternates the configurations for three rounds and keeps each one’s best run per page. Every configuration renders byte-identical HTML (`bench.rb --digest`).

- `page` is the repo’s normal benchmark (`fixtures/page.rb` in `fixtures/layout.rb`): a static 100-row table.
- `dashboard`: an admin orders table, 50 rows with links, status badge components, button components with variants and Stimulus/Turbo `data` attributes.
- `article`: a text-heavy post with escaped user content, code blocks and 30 comments with avatar components.
- `catalogue`: 60 product cards of nested components, five inline SVG stars each, conditional classes and prices.
- `settings_form`: 24 labelled inputs with hints and errors wired up with ARIA, a 120-option select and checkboxes.

All but `page` share a layout component with a head, a six-link nav with `aria-current` and a footer. They use only API that both versions share.

## Results

Ruby 4.0.10 +YJIT on a shared 4-core cloud VM, so run-to-run noise is about ±10–15%: read differences under about 20% as noise. Gbit/s is output bytes × i/s × 8.

| page | 2.4.3 | 3.0 runtime | 3.0 runtime + native | 3.0 compiled | 3.0 compiled + native |
| --- | --: | --: | --: | --: | --: |
| page (34 KB) | 2,311 i/s · 0.63 Gbit/s | 1.11× | 1.13× | 25.7× | **25.2× · 15.8 Gbit/s** |
| dashboard (67 KB) | 231 i/s · 0.12 Gbit/s | 4.3× | 5.0× | 6.3× | **9.3× · 1.14 Gbit/s** |
| article (31 KB) | 465 i/s · 0.12 Gbit/s | 6.0× | 7.1× | 7.1× | **8.3× · 0.96 Gbit/s** |
| catalogue (201 KB) | 129 i/s · 0.21 Gbit/s | 3.0× | 3.6× | 5.1× | **8.3× · 1.72 Gbit/s** |
| settings_form (18 KB) | 488 i/s · 0.07 Gbit/s | 6.9× | 9.2× | 14.4× | **14.6× · 1.00 Gbit/s** |

Objects allocated per render:

| page | 2.4.3 | 3.0 runtime | 3.0 runtime + native | 3.0 compiled | 3.0 compiled + native |
| --- | --: | --: | --: | --: | --: |
| page | 1,235 | 628 | 1,239 | 21 | 22 |
| dashboard | 16,101 | 2,903 | 3,690 | 2,366 | 2,420 |
| article | 7,449 | 877 | 1,108 | 886 | 916 |
| catalogue | 25,093 | 7,313 | 8,905 | 4,874 | 4,814 |
| settings_form | 7,239 | 515 | 788 | 469 | 470 |

Raw numbers, including each run’s error, are in `results.json`.

## Reproducing

The C extension needs Ruby 4.0. Bundler puts this checkout’s `lib` on the load path through the gemspec, so if `lib/phlex_native` exists there it loads in every 3.0 configuration. Keep it out of this checkout and give the two 3.0 configurations their own copies of `lib`:

```sh
git worktree add ../phlex-2.4.3 2.4.3
bundle exec rake compile
cp -r lib ../phlex-native-lib
bundle exec rake clobber
cp -r lib ../phlex-ruby-lib

bundle exec ruby benchmarks/versions/compare.rb \
	--phlex-2 ../phlex-2.4.3/lib \
	--phlex-3 ../phlex-native-lib \
	--phlex-3-ruby ../phlex-ruby-lib \
	--rounds 3 --time 5
```

`compare.rb` aborts if a 3.0 configuration loads the extension when it shouldn’t, or doesn’t when it should, and `bench.rb` aborts if a compiled configuration leaves any of the components uncompiled. For a single configuration, run `PHLEX_LIB=path/to/lib bundle exec ruby --yjit benchmarks/versions/bench.rb [--no-compile]`.
