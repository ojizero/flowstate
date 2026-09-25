# Flowstate

A native Swift experiment for transcribing Voice Memos with Apple's local speech models, then editing the text with the on-device Foundation Models LLM. macOS is the primary POC; the same SwiftUI app and core also build for iOS 26 or later.

## Run on your Mac

Requires macOS 26+, Apple silicon, and Xcode 26+ or matching Swift command line tools. Enable Apple Intelligence and let its model finish downloading to run LLM trials. Transcription can still work when the LLM is unavailable.

```sh
bash scripts/build-app.sh --open
```

Or open `Flowstate.xcodeproj` in Xcode, select **My Mac**, and Run. For an iPhone, select a physical Apple Intelligence-capable device and set your signing team. Simulator compilation does not establish model availability or performance on a phone.

1. Export a recording from Voice Memos using Share, then save it as a file.
2. Choose that recording in Flowstate. `.m4a` is supported through AVAudioFile, along with other decodable audio formats.
3. Leave **Arabic + English** selected and run the experiments.
4. Compare raw transcripts, cleanup outputs, and timings. Open **Merge & edit** to inspect timestamped alternatives or clean an edited draft without rerunning speech recognition.
5. Export JSON to keep the full experiment, including unsuccessful trials. Use **Open results** to inspect it later. Results otherwise live in memory and a new run replaces them.

Model downloads are enabled in the app for initial setup. After setup, disable the option and test without network connectivity. The CLI requires an explicit `--download-models` flag. The app does not call a cloud inference service, use Private Cloud Compute, record a microphone, or upload recordings. Apple's OS manages its model assets and services. This code-level design is not a packet-capture audit of macOS.

## What gets compared

| Trial | Input | Output |
| --- | --- | --- |
| English transcription | Original audio | Raw English-locale transcript and timed runs |
| Arabic transcription | Original audio | Raw Arabic-locale transcript and timed runs |
| English cleanup | English-locale transcript | Local LLM edit |
| Arabic cleanup | Arabic-locale transcript | Local LLM edit or recorded error |
| Confidence merge + cleanup | Timestamp-aligned candidates | Experimental merge, then LLM edit |
| LLM reconciliation + cleanup | Both timestamp-aligned candidates | LLM chooses and edits a combined transcript |

Transcription selects SpeechTranscriber if the requested locale is supported, otherwise DictationTranscriber. Both run on device. The two passes run sequentially. The app never falls back to server-backed SFSpeechRecognizer.

Arabic LLM trials run by default even if `supportsLocale` returns false. This is deliberate experimentation. A successful response does not establish reliable Arabic support. Refusals and framework errors stay visible, and other trials continue. When the model is unavailable, cleanup returns a clearly labeled whitespace-only result. Turning off the unsupported-language toggle also uses this baseline for Arabic and skips bilingual LLM reconciliation.

The confidence merge prefers Arabic at ambiguous overlaps and selects English only when its confidence exceeds Arabic by a configurable margin. The scores are not calibrated across engines. Timings may group several words together; a group selects one candidate, so fine-grained code-switches can be lost. Both original candidates remain available. The LLM reconciliation trial tests a different approach to the same ambiguity.

## Timing and evaluation

Each pass reports preparation time, transcription time, audio duration, and real-time factor. RTF is transcription seconds divided by audio seconds; below 1 means faster than real time. Preparation includes asset checks and downloads. Transcription includes analyzer/model startup, decoding, and finalization. LLM trial wall time includes all chunks and model startup. The JSON preserves measured total and preparation seconds, from which transcription time and RTF can be recomputed.

Run the same file again after models are warm. The fixed sequential order can advantage later trials through OS model caching, so these are exploratory timings, not a controlled benchmark. For quality, compare against a hand-corrected reference and the audio. Check names, numbers, negations, omitted words, Arabic dialect, and English terms separately. Fluent output can conceal errors.

Long transcripts are split on sentence or word boundaries using a conservative UTF-8 budget, with a fresh LLM session per chunk. This bounds context use but loses cross-chunk context. No input tail is deliberately truncated. A model can still omit text; keep the raw transcript. Long candidate overlap groups are split independently for reconciliation and may lose precise alignment. Those results carry a note.

## Glossary and learning from edits

Open **Personalization** to add preferred spellings, optional meanings, and aliases. For example, `Todoist` can have `to-doist` and `to doist` as aliases. Explicit aliases are case-insensitive whole-phrase replacements before and after LLM cleanup. They do not alter the raw speech output. Use narrow aliases: a broad rule can also change a legitimate word.

Choose **Edit & teach** on any raw transcript or cleaned output. Correct the text and select **Save edits as examples**. Flowstate extracts changed phrases with nearby words and saves them as examples for similar future text. This is retrieval of user-approved corrections, not model training. Examples guide the model and may be ignored; they never become automatic replacement rules. Add a glossary alias when you want an explicit replacement.

**Compare personalization on original text** runs cleanup on the same unedited input with personalization off and on, keeping both outputs and timings. This tests text cleanup only. To compare recognition hints, run the audio again with **Use glossary and saved edits** off and on.

The Arabic DictationTranscriber receives up to 100 short vocabulary hints from glossary terms and saved edits. Apple documents this hint mechanism for DictationTranscriber; the POC does not claim SpeechTranscriber uses it. Both engines benefit from glossary handling and relevant examples during cleanup. These features cannot reconstruct missing speech or establish reliable mixed-language recognition.

Preferences are saved to `Flowstate/personalization.json` in the app's local Application Support directory. The Personalization tab shows the exact path. The sandboxed Xcode app and the standalone bundle may have different support directories. There is no cloud sync, and the profile is excluded from system backups. You can edit/delete glossary entries, forget individual edits, clear learned edits, or disable personalization. The app retains at most 100 glossary entries and 200 correction examples, and limits retrieved prompt context to 1,800 UTF-8 bytes per chunk.

Exports include the profile used for a run and the actual context supplied to cleanup. Opening a saved experiment does not install its profile. Old experiment JSON files remain readable. Per-draft comparisons record their own profile snapshot because it may differ from the original run.

## Command line

```sh
# Use full Xcode if your selected Command Line Tools lack SwiftUI compiler plugins.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift run flowstate-cli capabilities
swift run flowstate-cli transcribe /path/to/memo.m4a --mode dual --download-models --output /tmp/experiment.json
swift run flowstate-cli transcribe /path/to/memo.m4a --mode english --output /tmp/english.json
swift run flowstate-cli clean /path/to/transcript.txt
swift run flowstate-cli profile add-term Todoist --aliases 'to-doist,to doist' --note 'Task manager'
swift run flowstate-cli profile learn /path/to/original.txt /path/to/corrected.txt
swift run flowstate-cli profile show
swift test
```

`--respect-language-support` skips unsupported Arabic LLM attempts. Without `--output`, the CLI prints JSON; progress goes to stderr. Avoid committing personal recordings or exported transcripts. `Samples/` and `Results/` are ignored for local testing.

`--no-personalization` bypasses the local profile. `--profile /path/to/profile.json` selects a separate profile for experiments without modifying your usual glossary or learned edits. These options work with `clean` and `transcribe`; the profile commands also accept `--profile`.

The source is split into `Sources/FlowCore` for the pipeline, `Sources/Flowstate` for SwiftUI, and `Sources/FlowCLI` for repeatable terminal runs. There are no third-party dependencies. See [research.md](research.md) for API findings and [validation.md](validation.md) for the tests performed, including the supplied Voice Memo.
