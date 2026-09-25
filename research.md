# Feasibility notes

Checked September 25, 2026, against Apple's documentation and the APIs on this Mac.

The proposed architecture is feasible for supported languages. Apple exposes local recorded-audio transcription through SpeechAnalyzer and text editing through Foundation Models. Mixed Arabic and English remains an experiment. Two recognizers provide alternative hypotheses, not a guarantee that either gets the language switches right.

## Device observations

The development Mac runs macOS 27.0, build 26A428, on arm64. Runtime queries returned:

| Capability | Observed |
| --- | --- |
| `SystemLanguageModel.default.availability` | `available` |
| Foundation Models English locale | Supported |
| Foundation Models Arabic locale | Unsupported |
| SpeechTranscriber English | Supported; installed |
| SpeechTranscriber Arabic | Not listed |
| DictationTranscriber Arabic, `ar_SA` | Supported; initially not installed |

The app probes these lists rather than hardcoding a universal language matrix. Model availability varies with hardware, OS, asset downloads, language settings, and region. The POC targets OS 26 APIs even though development is on OS 27.

## Evidence and design decisions

[Apple's SpeechAnalyzer introduction](https://developer.apple.com/videos/play/wwdc2025/277/) describes an on-device recognizer designed for recorded conversations and long-form audio, shared with system apps. Its file-transcription example consumes results concurrently, reads the audio file, and finalizes through the final audio timestamp. This POC uses the same lifecycle and preserves raw output before cleanup.

[DictationTranscriber documentation](https://developer.apple.com/documentation/speech/dictationtranscriber) states that it uses the system dictation models in their on-device configuration and excludes locales only supported over the network. It provides the Arabic pass on this Mac without violating the local-model requirement. A speech locale is selected for each pass; simultaneous Arabic-English accuracy is not established by a list of individually supported locales.

[Foundation Models language guidance](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models) requires checking locale support and describes unsupported-language errors. It also notes that short unsupported-language phrases can escape detection. Therefore both outcomes are informative: a rejection exposes a limit, while generated Arabic still needs quality evaluation. The runner attempts Arabic by default because testing this behavior is the purpose of the POC.

[Apple's current Intelligence requirements and language list](https://support.apple.com/en-us/121115) exclude Arabic. Siri or dictation language support should not be treated as evidence of Foundation Models language support. The runtime check on this Mac agrees with the published limitation.

[Apple's context-window guidance](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window) documents the limited session budget for the OS 26 on-device model. The POC uses short chunks and fresh sessions rather than passing an entire long recording through one session. All generations explicitly select `SystemLanguageModel.default`; none select the newer Private Cloud Compute model.

## What still needs validation

Use the user's Voice Memos to test dialect, code-switch boundaries, distant speech, and technical vocabulary. Measure transcription accuracy separately from editing accuracy. In particular, an LLM must not repair a plausible but incorrect recognition by inventing a more fluent sentence.

The confidence merge is a transparent baseline. Scores between SpeechTranscriber and DictationTranscriber are not established as comparable. Timestamp overlap may join several tokens into one choice. The LLM reconciliation trial can use both candidates but cannot recover information missing from both, and Arabic rejection may prevent it from running at all.

Privacy and cost are promising properties of this architecture: local inference requires no per-request provider billing. They do not by themselves prove low latency, low battery use, or accuracy. Measure a cold run and repeated warm runs on the actual Mac and iPhone before deciding whether this can replace a daily dictation tool.

## Local personalization

[Apple's contextualStrings documentation](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings) describes short vocabulary hints for DictationTranscriber and limits them to 100 phrases. Flowstate supplies those hints through AnalysisContext for the dictation pass. This documented support should not be generalized to SpeechTranscriber.

[Apple's prompting guidance](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model) describes using instructions and examples to guide generation. Flowstate stores user edits locally, retrieves relevant examples, and includes them in cleanup requests. Explicit glossary aliases are handled separately as whole-phrase replacements. Neither mechanism updates the built-in model's weights.

[Foundation Models adapters](https://developer.apple.com/apple-intelligence/foundation-models-adapter/) provide a separate training and deployment route with an adapter entitlement. The POC does not require adapters or an entitlement; its editable local profile provides a smaller experiment that can be compared directly with a baseline.
