# Articulate

Articulate is a native Mac app for pronunciation practice. Choose **Modern British RP** or **American English**, hear an example, and try the prompt. Each drill shows a mouth-position diagram and a brief practice cue.

The Modern British RP drills start with the vowel in *bath*, the final vowel in *car*, and linking R in *far away*. They use contemporary Southern British pronunciation as the practice target.

**Hear example** in British RP plays a recording by a speaker from Southern England. The app shows the words in the recording next to the button. The clips work offline and their sources are listed under **Help → Audio Credits**. American English uses a macOS system voice.

## Free practice

Choose **Free practice** in the sidebar, type or paste an English sentence of up to 24 words, and read it aloud. Choose **Done speaking** to see any words that the app can suggest practising, with one short cue per highlighted word.

Free practice uses the Modern British RP target and runs on the Mac. It uses [Britfone](https://github.com/JoseLlarena/Britfone) to match the sentence to the recording and HuPER to check selected contrasts. It can give cues for the vowel in words like *bath*, R in words like *car*, quiet TH, V, short I, and SH. Audio that is difficult to align may yield fewer tips or a request to repeat the sentence.

## Run locally

From the project directory, run `bash Scripts/install-model.sh` to fetch the pinned, checksum-verified HuPER Core ML weights. The one-time download is about 317 MB. Then open `Articulate.xcodeproj` in Xcode, select **My Mac**, and press **⌘R**.

To build and launch from Terminal, run:

```sh
bash Scripts/install-model.sh
xcodebuild -project Articulate.xcodeproj -scheme Articulate -configuration Debug -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/Articulate.app
```

American English runs on macOS 14 or later. Modern British RP sound feedback, including Free Practice, requires macOS 15 or later and the installed model. The example recordings and diagrams are available while the model is missing.

Allow microphone access when macOS asks. The American English mode also requests Speech Recognition access. You can review these permissions in **System Settings → Privacy & Security**. macOS may ask again after a locally signed rebuild.

## How feedback works

In Modern British RP mode, HuPER analyses the recorded prompt locally after you select **Done speaking**. It compares the target sound with a few plausible alternatives. When the evidence is mixed, it asks for a repeat and shows a practice cue. The drills check specific contrasts such as the presence of R or a broadly different vowel. Individual vowel quality, vowel length, and intonation need separate evaluation.

In American English mode, Articulate compares the words Apple Speech recognises with the practice phrase. Apple may process audio on its servers on systems that use network recognition. Articulate holds practice audio and transcripts in memory and saves neither.

The local model is the MIT-licensed [HuPER Recognizer](https://huggingface.co/huper29/huper_recognizer) using the [HuPER Core ML conversion](https://huggingface.co/BarrySong/HuPER-CoreML). Recordings stay on the Mac in Modern British RP mode.

## Vocal Coach

Vocal Coach is a standalone Mac app for British vowel practice. Edit the large prompt to practise one word or a sentence. After a short typing pause, Emma, the British English Kokoro voice from PageHum, reads the prompt. **Hear Emma** replays it. After the first reading, select **Record** to practise up to 48 words. After recording, choose **Play my take** to listen back. After a second recording, **Compare takes** plays the previous take and then the latest, labelling each as it plays.

Emma’s teal trace appears over the words. A microphone level meter responds as you speak at your own pace. Your purple trace appears after recording. Height shows pitch relative to each speaker’s typical pitch, and thickness shows relative loudness. Gaps represent unvoiced audio. After recording, the app uses recognized word timings where available and labels estimated timing. Orange underlines identify words to practise. Select a word to see a comparison from your take or a general practice tip. The coaching panel offers Emma’s word and your word for replay when the corresponding clips are available. Steady-vowel comparisons use the first two resonances relative to the third to reduce the effect of vocal tract size. [Formant ratio research](https://pmc.ncbi.nlm.nih.gov/articles/PMC2893733/)

Vocal Coach adapts the Burg and polynomial-root steps of [Phonia](https://github.com/mkpoli/phonia/tree/663f43de63dd9dcb82a124b34739edb52635ebb6/crates/phonia-formant) for vowel analysis and uses [Britfone](https://github.com/JoseLlarena/Britfone) for cues. Sentence word timing uses Apple's local Speech framework on macOS 26 or later. The first use may download British English speech data. Practice recordings stay in memory. Voice synthesis temporarily writes the prompt and generated audio locally. Credits are available under **Help → Audio and Software Credits**.

Stage the [PageHum Apple Silicon CLI release](https://github.com/Mieraidihaimu/pagehum/releases/tag/v0.1.0) with `Scripts/stage-vocal-coach-voice.sh /path/to/pagehum-0.1.0-macOS-arm64.tar.gz`. Keep its companion checksum file alongside the archive. The script also accepts the default archive from the local PageHum checkout. Open `VocalCoach.xcodeproj` in Xcode, select **My Mac**, and press **⌘R**. The app requires Apple Silicon and macOS 15.6 or later.
