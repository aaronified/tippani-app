# Changelog

All notable changes to the app are recorded here. The format is [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and the
app reads this file itself: it shows the entry for the version it has just been updated to, and the What's new screen lists every
version. Write each entry for the person using the app, in plain words.

## [Unreleased]

### Added

- Sync now runs by itself once a server is paired: when the app opens, when you come back to it, a few seconds after you change something, and
  every few minutes while it is open. If the server cannot be reached it tries again after 30 seconds, then a minute, two, five. You can turn
  it off in Settings > Sync with server, which also shows when it last finished and has Sync now.
- Sync conflicts has its own place: Settings > Sync conflicts, and a badge on the Library's top bar. When the same quote or work was changed on
  the phone and on the server, it waits there, untouched. Settle one, some or none whenever you like; the rest of your library keeps syncing in
  the meantime.
- A book, film or quote that is on both the phone and the server is now one item after the first sync, not two. Before, a work you typed here
  that your server already had (or the other way round) came down as a second copy. Now they are joined; if they differ you see both
  versions in Sync and choose.
- Deleting now syncs both ways. A quote or work you delete here is deleted on your server too (it sits in the server's bin for a while, and
  you can bring it back from Settings > Bin), and one you delete on the server is removed here at the next sync. If you changed it here after
  it was deleted there, it is kept and sent up again. If your server suddenly lists far fewer items than the phone knows (it looks wiped or
  restored from an old copy), nothing is removed here and the sync says so.
- The app has Tippani's own icon: the rust speech bubble with quote marks, as a normal launcher icon, an adaptive icon for round and
  squircle masks, and a single-colour version for Android's themed icons.
- One Share screen replaces the three share buttons on a quote. Choose the format (Picture, Plain text, Markdown, WhatsApp or Reddit),
  switch parts on or off (quote, translation, speaker, author, work, year, chapter, location, date noted, tags, your note; location, date
  and year start off, as on the web), and see exactly what will be sent. A picture can be light or dark and can be shared or saved; text can
  be edited by hand, shared or copied.
- Read aloud has settings (Settings > Read aloud): pick the voice, the speed and the pitch, and try them. By default the app now picks the
  best installed voice for each quote's language, preferring higher quality and online voices, which sound far less robotic than the
  basic one. The voices come from Android's own speech service; install more in Android Settings > Text-to-speech.

## [0.3.0] - 2026-11-06

### Added

- Look up details (needs your server): when you add or edit a work, Look up details asks your server what the title most likely is and
  offers the matches; pick one to fill in the title, the author and the year. The app holds no keys of its own: the server does the lookup.
- Bin (needs your server): Settings > Bin lists what you deleted lately on the server, with how many quotes went with a book, and lets you
  restore it, delete it for good, or empty the bin. Statistics shows the server's own numbers: quotes, books, films, shows, favourites, tags,
  your busiest month and top tags.
- Anthologies (needs your server): Settings > Anthologies lists the collections you keep on the server. Open one to read its passages and your
  commentary, share it as text, rename it, or take a passage out. Make a new one from there. From any quote that is on the server, Add to
  anthology puts it at the end of one you choose, or of a new one.

## [0.2.0] - 2026-11-06

### Added

- Open a quote to read it in full, as a card with your note, its tags and the work it is from. From there you can favourite it, edit it,
  delete it, share it as text, share it as a picture, or save the picture to a file. The picture is the card you see.
- A work's page shows how many quotes, chapters and favourites it holds, lists its quotes under chapter headings in reading order (or
  newest first), and can show only the favourites.
- Read: a work's quotes as one document to read straight through, with a text-size slider, translations and your notes switched on or off,
  and Share all.
- Read aloud: a quote is spoken in its own language (or its work's) with the phone's own voices, and the Read screen reads a whole work
  quote by quote. Nothing is recorded or sent. If the phone has no voice for the language, it says so.
- Scan a page: photograph a page (or choose a picture) and Tesseract reads the text on the phone, in English, Hindi or both. Hyphenated
  line ends are mended and a paragraph's lines are joined. You correct the text, then the quote form opens to say where it is from.
  The quote is marked as scanned. Nothing leaves the phone. The button is on the library and on each work's page.
- Say a quote: press the microphone and speak, in English, Hindi or Bengali; the words appear as you speak and you correct them before
  saving. The app keeps no recording. Your phone's speech service does the listening, and on some phones it sends the audio to Google.
- The app keeps a library of its own on the phone, so it works with no server. Works and quotes, with tags, colours, favourites,
  your notes, translations and where in the book each came from, are stored in the app, and searched by their words, the work's
  title and author, who said them, and their tags. A server is something you can add later, not a way in.
- The app opens on your Library: every quote and work, searchable by words, people, works and tags, with a Favourites filter and a tag
  filter. Add a quote or a work, open one to change or delete it, and give a quote its own colour. Deleting a work says how many
  quotes go with it first.
- Send your library to your server: in Settings, once the phone is paired, "Send library to server" adds the works and quotes that are only
  on the phone. It only adds: nothing on the server is changed or deleted, what is already there is not sent again, and if the connection
  drops the rest waits for the next try.
- Sync with your server: in Settings, once the phone is paired, "Sync with server" brings down what is new or changed on the server,
  sends up the changes you made on the phone, and never deletes anything on either side. If the same quote or work was changed in both
  places, nothing is changed for it: you see both versions side by side and choose, for that quote or that work, to keep the phone's or
  the server's. When there are several, you can keep the phone's or the server's for all of them, after a confirmation.
- Export your quotes as Markdown, all of them or one work's, to share or to save as a file. It is the same format Tippani's server
  imports, so a library made on the phone can be moved to a server later.
- Backups now carry that library. Restoring replaces the library and the settings with the file's, after saying so. A damaged
  backup is refused whole: nothing is restored from it, not even the settings.
- Pair this phone with your server: make a code in Tippani's Settings on a computer, type it in the app, and the phone gets a key it
  can use and you can take away. No password is typed on the phone. Settings lists your paired devices, marks this phone, and
  unpairs any other; the app tells you if the server unpaired it.
- A server log, for an admin, in Settings, with a search, a time window and the levels to show, and Copy and Share. It is the
  server's own log and is kept apart from the app's log (now called App log): the two never share a screen or a file.
- The app opens, asks your Tippani server what it is, and tells you whether this app and that server can talk. It remembers the
  server's address, and warns you before it keeps a plain http address outside your own network.
- It checks for a newer version of itself when it opens. When there is one, a message offers to download it, and Android's installer
  takes it from there.
- After an update, a short list of what changed appears once. The same list, for every version, is under What's new in Settings.
- A log of what the app did, in Settings, that you can read, copy or share. It never holds the key that pairs the phone or anything
  you wrote.
- Backup and restore of the app's settings: a copy kept on the phone and one in your Downloads folder, and a restore from either or
  from any file you choose.
