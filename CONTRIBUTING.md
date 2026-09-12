# Contributing

IncidentDeck uses small issue-driven changes and requires reproducible checks before merge.

## Before opening a pull request

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
```

Keep domain behavior deterministic and inject time, IDs, storage paths, and transports at boundaries. Do not add cloud services, analytics, or notification providers merely for portfolio optics.

Security fixes must solve the underlying finding rather than disable analysis or weaken CI.
