# Contributing to PlatenKit

Run commands from the repository root on a Mac with a Swift 6 toolchain. The package tests exercise rendering, printer encoders and Bluetooth flow control offline.

```zsh
swift test
swift build -c release
```

CI also renders the documented Moon label with the release CLI and builds the unsigned SwiftUI bench for iOS. The checked-in Xcode project works directly from a clone. When changing its targets or settings, update both the XcodeGen spec and the generated project. [CI workflow](.github/workflows/ci.yml) · [Project spec](BenchApp/project.yml) · [Build commands](README.md#build-and-verify)

## Report a printer result

Use a fresh run ID and state the printer model, host OS, loaded stock dimensions and command language. Include the endpoint and byte count if the job reached Bluetooth. Record what came out of the selected printer, including the number of labels and any QR payload you scanned. Use test artwork when sharing a photo or journal. [Printer report form](.github/ISSUE_TEMPLATE/printer-report.yml) · [Example with traces and paper results](BenchRuns/2026-11-23-moon-0132Z/README.md)

## Open a pull request

Keep each commit focused on one change and use a Conventional Commit subject, such as `fix(rongta): preserve row padding`. Include a regression test for changes to rendering or wire formats and describe how you verified the result. A physical result is especially helpful for a new printer adapter. [iPhone bench procedure](QUICKSTART.md#4-verify-paper-on-a-real-iphone)
