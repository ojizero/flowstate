# Validation

Tested on September 25, 2026 with an Apple M3 Max, 48 GB RAM, macOS 27.0 build 26A428, and Xcode 27. The app targets macOS and iOS 26+. These timings are exploratory, with warm OS model assets and other development work running on the Mac.

## Builds and checks

- Swift package app and command line tool compile, including the release app bundle.
- The native Xcode project builds for macOS and for a generic iOS device without signing. No physical iPhone inference test was performed.
- Six Swift Testing checks cover lossless mixed-script chunking, long unbroken text, empty input, Arabic-English selection, missing confidence, overlapping timestamps, and preserving unopposed tail words.
- The packaged macOS app launches. Visual UI inspection was unavailable because this environment has no screen-capture access. Inference was exercised through the CLI using the same core as the UI.
- Synthetic recordings exercised actual `.m4a` decoding, model downloads, Arabic and English recognition, all cleanup trials, and JSON export. No recording was submitted to an external transcription provider.

## Supplied Voice Memo

The supplied file, "Fallacies of productivity", is 99.69 seconds, mono AAC at 48 kHz. Two full experiment runs are saved under the git-ignored `Results/` directory. The first used pipeline version 1; version 2 uses stronger cleanup instructions and groups candidates into six-second intervals for LLM reconciliation.

The second run measured:

| Stage | Time |
| --- | ---: |
| Arabic DictationTranscriber, excluding preparation | 1.64 s |
| English SpeechTranscriber, excluding preparation | 1.40 s |
| Arabic transcript cleanup | 1.67 s |
| English transcript cleanup | 3.87 s |
| Confidence merge cleanup | 3.67 s |
| LLM candidate reconciliation and cleanup | 4.69 s |

Arabic recognition returned only six timed text runs. English returned 149. The English transcript includes apparent phonetic substitutions for Arabic speech. The confidence merge retained one Arabic word, which the subsequent LLM edit dropped. The revised reconciliation prompt fixed the first run's JSON-like formatting, but copied poor Arabic recognition into its result. No manually corrected reference transcript was available, so these observations are not a measured word error rate.

This sample supports the speed and local-execution feasibility of the pipeline. It does not validate dependable Arabic-English transcription. Better formatting cannot recover words that neither recognizer captured correctly.

## Unsupported Arabic experiment

`SystemLanguageModel.default.supportsLocale(ar-SA)` returned false, but a short Arabic cleanup request succeeded in 2.30 seconds and a mixed Arabic-English text request succeeded in 2.13 seconds. Both preserved the supplied words and added punctuation. The actual Voice Memo also completed all Arabic-bearing LLM calls without a framework error. Another synthetic mixed-language test changed dialect and phrasing, so successful generation is not evidence of faithful editing.

## Remaining experiments

The most useful next comparison is resetting the Arabic recognizer on shorter audio windows, with overlap to preserve boundary words, then comparing against a manually corrected transcript. This may help recognition after English passages, but has not been tested here. If built-in recognition still omits Arabic, a local third-party multilingual speech model would be a separate architectural experiment. This POC intentionally stays within Apple's built-in models.

## Personalization checks

Pipeline version 3 adds a local glossary and correction examples. Thirteen tests pass, including seven new checks for mixed-script phrase boundaries, conflicting aliases, extracting multiple edits, insertions/deletions, disabled personalization, prompt budgets, persistence, corrupt-file handling, and opening old experiments.

A separate temporary profile was used for live testing. It defined `to doist` as an alias for `Todoist` and learned an edit from "We should review the pool request before deploying." to "We should review the pull request before deploying." On the new input "Please check the pool request in to doist before deploying.", the control left "pool request" unchanged. Personalized cleanup produced "Please check the pull request in Todoist before deploying." The output recorded the actual glossary/example context used.

The initial prompting attempt did not apply the saved correction; naming the mistaken phrase and the preferred phrase explicitly, alongside their original context, made the test succeed. This is one synthetic case, not a general accuracy result. The glossary replacement is deterministic; learning from examples still depends on model behavior. No test vocabulary or synthetic edits were added to the user's real profile.

An Arabic audio smoke test also exercised `AnalysisContext.contextualStrings` through DictationTranscriber and exported the supplied hint list. The iOS build verifies compilation only; personalization quality and persistence on a physical iPhone still need testing.
