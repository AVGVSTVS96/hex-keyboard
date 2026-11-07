# iikb privacy policy

iikb is a keyboard and an app for iPhone and iPad. What you type and say stays on your iPhone. iikb has no account, no
ads, no analytics and no server of its own that receives your data.

## What stays on your iPhone

- What the keyboard learns: where your thumbs land, the words and phrases you use, your emoji and GIF picks.
- Your clipboard history, kept by the keyboard so you can paste it again.
- Dictation: recordings and transcripts are made on the iPhone by the voice model you pick, and kept there until you
  delete them.
- Your typing and dictation stats.

Deleting iikb deletes all of it.

## What leaves your iPhone, and only when you use it

- **Voice models.** The first time you dictate, iikb downloads its speech model from Hugging Face. Nothing you say is
  sent; the model runs on the iPhone.
- **GIF search.** What you type into GIF search goes to KLIPY, which returns the GIFs, with a random ID made for this
  install that KLIPY uses to rank results. Nothing else you type is sent.
- **Sources you add.** A source is a web service you choose to plug in. iikb sends it the text of the field you're typing
  in, as [docs/sources.md](sources.md) describes. None is added unless you add it.
- **Computers you add.** If you add your own Mac to Stats, iikb reads the typing counts it shares, over your own network.

## Full Access

iOS asks you to allow Full Access for a keyboard that uses the network or shares data with its app. iikb needs it for
haptics, voice typing, GIFs, the clipboard history, Your Taps and sources. Without it, iikb still types and corrects,
with nothing leaving the keyboard.

## Contact

iikb is open source: [github.com/AVGVSTVS96/iikb](https://github.com/AVGVSTVS96/iikb). Questions go to its
[issues](https://github.com/AVGVSTVS96/iikb/issues).
