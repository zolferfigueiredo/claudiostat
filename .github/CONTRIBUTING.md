# Contributing

Thanks for helping with ClaudioStat. Bug reports, ideas, translations and code are all welcome.

## Issues

- **Bugs and ideas**: [open an issue](https://github.com/zolferfigueiredo/claudiostat/issues/new/choose). Search the open ones first.
- **Security problems**: don't open an issue. Follow the [security policy](SECURITY.md).

## Pull requests

For anything bigger than a small fix, open an issue first so we can agree on the idea before you build it.

1. Fork the repository and branch from `main`.
2. Make your change. `./run.sh` builds and opens a debug copy, and `swift test` runs the tests. You need macOS 15 or later and Xcode 26.
3. If you changed the app (anything in `Sources`, `Icon`, `Package.swift` or `Info.plist`), raise both versions in `Info.plist`, for example 1.2.3 to 1.2.4.
4. Open a pull request against `main`.

CI builds and tests it on macOS, counting any compiler warning as an error. It also runs shellcheck on the scripts and checks that the version went up.

## Translations

Each language has its own file in [`Sources/ClaudioStat/Strings`](../Sources/ClaudioStat/Strings). To fix a translation, edit that file. The tests check that every language has every string and keeps placeholders like `{version}`.

## License

By contributing, you agree that your work is licensed under the [MIT License](../LICENSE).
