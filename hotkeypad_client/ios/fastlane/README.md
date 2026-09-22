fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios build

```sh
[bundle exec] fastlane ios build
```

Build the release .ipa with Flutter (flutter build ipa)

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Push store listing text/screenshots only — no binary, no build

Useful for getting metadata approved/updated ahead of a release, or fixing a typo without a new build.

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload the latest build to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Build, then upload binary + full store listing to App Store Connect

Pass submit: true to also submit the new version for review.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
