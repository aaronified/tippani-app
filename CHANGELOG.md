# Changelog

All notable changes to the app are recorded here. The format is [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and the
app reads this file itself: it shows the entry for the version it has just been updated to, and the What's new screen lists every
version. Write each entry for the person using the app, in plain words. **Start each entry with a short title and a colon**
("Sync conflicts has its own place: ..."): the app shows only that title for each change, and the full words are read here, on GitHub.

## [Unreleased]

### Added

- Unpair every device: the Paired devices screen has a button that signs out every phone of your account, this one included, after asking. Resetting the server's data stays on the web on purpose: it deletes every account's library and needs a safety copy kept somewhere a phone cannot check.
- More changes wait for the server instead of failing: renaming or recolouring a tag, deleting a tag, restoring something from the bin and saving a context rule now work with no signal. They show at once, go up in the order you made them when the server answers, and one the server then refuses is dropped and written to the app log. Merging tags, deleting for good and emptying the bin cannot be undone and still need the server.
- Covers, casts and details are kept on the phone: after each sync the phone downloads the cover pictures it does not hold and each work's description, genres and cast (60 requests a run, the rest follows at the next sync, and details are read again after two weeks), so a shelf and a work page look the same with no server. It stops after three misses in a row, when the server is not answering.

### Fixed

- A change that reached the server while its reply was lost is no longer made twice: every anthology, heading and passage you add, sent now or waiting, carries a key of its own, and a server on 3.9.0 or later answers the repeat with the first answer instead of making a second anthology or heading. An older server ignores the key and behaves as before.
- A cover or poster chosen with no signal shows at once and says "Change" instead of "Add": the phone keeps the picture and draws it while the upload waits. Choosing again replaces the upload that is still waiting instead of queueing a second one.

## [0.8.2] - 2026-11-13

### Added

- Anthologies work with no server: you can make an anthology, rename it, add and take out passages, write commentary, put headings in and move things, change its front matter and grouping, put a cover picture on it and set the search that fills it, all with no signal. It shows at once, and the phone sends it to your server, in the order you did it, the next time the server answers. Above the list it says how many changes are waiting and what the server did not take. Counting what a fill would find and making an EPUB need the server; a Markdown file is made from the phone's copy.
- Everything that only reads keeps its last answer: statistics, tags, the bin, people and characters, Checks, the metadata console, source files, imports waiting, devices, administration's lists and the daily quiz's cards open from the phone when the server cannot be reached, with a line saying it is the phone's copy and from when.
- A quote's context is on the phone for every synced quote: after each sync the phone fetches the context of every quote the server has one for, 150 at a time, so Show where it comes from works with no server. A wider window than the one you last opened is answered with the widest the phone holds.

- Anthologies look like a book: each has a landscape poster (one you choose, or one drawn from its title) and a description you write yourself, apart from the introduction. Both show on the anthology's page and in the list, and you set them from Cover and front. They work with no signal like the rest of an anthology, and the server must be updated to keep them.

### Changed

- Your settings on the server are on the Server tab: Account, Language, Text and quotes, Colours, Sections (and how long the bin keeps things), Daily review and Context around a quote moved there from Settings, and they show and change with no server too. A setting you change with no server is kept and sent later, unless you changed the same setting on the web meanwhile, which wins. Settings keeps the app's own: App colours (renamed from Colours, so the two are not confused), Tags, Read aloud, updates, backup, the log and the licences.

### Fixed

- Front matter changed with no signal no longer writes over what you edited on the web meanwhile: the epigraph, dedication and description each go up only if the server still holds what the phone held when you changed it.
- A change made while a sync was running is no longer forgotten when that run ends: another run starts and sends it.
- Quiz answers waiting for the server are cleared, and the waiting count updated, when you unpair.
- A change made with no signal is no longer lost when the server answers 502, 503, 504 or 429 as it comes back (a proxy restarting): it waits and is sent again. Only an answer that refuses the change drops it, and says so.
- Changes waiting for the server go up when it next answers, not only after the library changes: an anthology edited or a setting changed in airplane mode is sent when the phone is back on a network.
- Answers a phone gave to the daily quiz and the settings it kept from one account are forgotten on unpairing, so they are never shown to or sent for the next account.
- A context kept on the phone is read again after a month, so one edited on the server reaches it.
- The poster and the description are offered only when the server can keep them; a picture chosen from the gallery is brought down to 2000 pixels, so it fits in what waits for the server.
- The Account page no longer stays blank when the server cannot be reached: it shows who you are from the phone, says what is wrong, and has a Try again button.
- The administration shows when you open the app with no server: a phone paired as an admin remembers that it is one.
- Nothing waiting for the server is sent to another account: unpairing, forgetting the server or restoring a backup that points at another server discards what the phone kept of the old one.

## [0.8.1] - 2026-11-13

### Fixed

- Reading a file as a chosen format works: "Read this as…" on an import sent the format under a name the server does not know, so seven of the eight choices were refused. They are sent under the server's names now.
- Moving a quote to a board on the phone reaches the server: the sync asked the server for the quote with a request it does not answer, so a quote you filed under a board on the phone but not on the server never moved. It reads the quote the way the server offers.
- An old backup restores: a backup from before the server's 1.4.1 carries no key, and the server wants the word it asks for before it restores one. The app sends it when you press Restore.
- Approving staged quotes says how many matched a quote you already have: the count was read under the wrong name, so the line never appeared.
- Parts played show the character's picture: the server keeps it under a name the app did not read, so an actor's list of parts drew none.
- A tag counts every quote that wears it: standalone quotes are included when the server is 3.7.1 or newer.

## [0.8.0] - 2026-11-09

### Changed

- Four tabs: the bottom bar is now Home, Boards, Server and Settings. Boards holds your Library, Catalogue, Quotes and Anthologies as four boards: the header shows the board you are on, and you swipe or drag sideways (or press an arrow or a dot) to move to the next. The swipe works only there. Server has everything about your server in one place (connection, sync, devices, imports and checks, people, details, source files, administration and the server's log), and Settings has only the app's own (colours, language, text size, tags, reading aloud, updates, backup, the app log and licences).
- One search bar, on Home and on every board: it suggests tokens as you type (tag:, by:, in:) and then their values, and on a board it filters that board while a button widens the same words to the server's results. The old separate server search button is gone.
- Home has its own Add button, for every kind of quote: a line from a book, from a film, show or game, a standalone quote, a scanned page, spoken words, and a file import.

### Added

- Colours: Settings, Colours chooses where the app's colours come from: Material You (your wallpaper, as before), the colours of a photo you pick, or a palette (Tippani red, indigo, teal, forest, rose, amber, slate). The change shows at once.

- Edit fields suggest as you type: Who said it offers the characters of the work and of the rest of its series (the third book offers the second's characters) and who has spoken there before; Chapter offers the chapters already used in the work, in chapter order, and picking one by its name or its number fills in both; the credit on a work (author, director, studio) offers the people your server holds for that kind of work and the credits already in your library; Language and Tags offer what you already use. You can still type something new.
- Every text box capitalises as it should: names and titles by word, notes and descriptions by sentence, and nothing for passwords, addresses, tags, searches and numbers.

- The context viewer is a scroller: Show where it comes from on a quote opens one screen with everything the server stored around it, above and below, the top and bottom fading out, your quote highlighted in its colour, and more loading as you reach either end. The characters of the work are picked out in the text, each in a colour of its own (by name and by the other names the server knows), with a row of them above; pressing one opens a sheet with their portrait, description, other names and how often they are named, and buttons for their page and for your quotes of theirs. The chapter and page are a chip in the top bar.

- Quote cards: every quote in a list is now a card. The work is in a header with its cover, title, who made it and where in it (chapter, page or time), the quote sits beside a bar in its colour, the people on it are chips, and a footer holds its tags and four buttons: Copy, Read aloud, Share and More (Open, Select, Add to anthology). A long run of chips or tags scrolls sideways and fades at the edge where more is hidden.

- New icons: every icon in the app, the four section icons in the bottom bar included, is now from Tabler Icons (MIT licence). The back, close and menu buttons of every screen use them too. Settings names them at the bottom, and pressing that line lists the licences.

### Fixed

- Anthologies no longer opens saying "This phone is not paired" and needing Try again: it waits until the phone has read its pairing, then shows your anthologies. The bottom bar no longer wraps a tab's name onto two lines: when a name will not fit on one line, only the open tab keeps its name.
- Character pictures show on quote chips: a character's face now appears on its chip in every list, including for a work you have not opened, and for a name spoken in a book. The picture of the character in that work is used first, then the character's own, then the actor's.

## [0.7.0] - 2026-11-07

### Changed

- The last sentences that were still English-only (sync results, the Import and checks list, source files, backups, counts such as "1 quote" and
  "5 quotes") are in Bengali too, and Home shows a card when imported quotes are waiting for your approval, with a Review button.
- The whole app speaks English or Bengali, from one set of words: every label, button, message and hint is looked up by name, in the language you chose
  in Settings (or your phone's), using the same words as the web where the web has them. A correction made to the language files on your server reaches
  the phone, and a word with no Bengali yet shows in English rather than blank. Sync results, error messages and counts ("1 quote", "5 quotes") follow the
  language too.

### Added

- A work's quotes can be ordered (reading order, newest, oldest) and gathered under headings by chapter, colour, tag, who said it or the month
  you noted them, with a count on each heading. A quote with two tags or two speakers is under both.
- Library browsing: the Library and Catalogue lists can be sorted (title, author or maker, year either way, recently added), grouped under
  headings (author or maker, decade, where you are with it, genre, language), filtered by where you are with each work (in progress, not
  started, paused, finished, abandoned), and shown as a list or as a wall of covers whose size you set. The count of works shown is on top, and your
  choices are kept for next time.
- Find a cover online: on a work's page, Choose a cover now offers From my photos or Find one online. The online search starts with the work's own
  title and author (you can change them, and search a book by ISBN), shows what the catalogues and picture suppliers have with the name of each,
  lets you narrow to one supplier, and uses the one you press for the cover. Films, shows and games search for posters.
- Details and duplicates (Settings, Your library): the works that still lack a cover, an author, a year, a synopsis or a source, with filters for
  each gap. Press one (or press and hold to choose several) to have the server look them up again on the web and show what differs: fields that are
  empty are ticked for you, ones that would replace what you have are left for you to tick, you can pick which supplier's answer to take, and a
  field that changed since the check is left alone. The server can also fill every work's gaps by itself, and an admin can ask it to fetch missing
  covers. A second tab lists works saved twice, to merge into the one you keep (the others go to the Bin).
- Source files (Settings, Your library): the ebooks and subtitle files your quotes came from, which give a quote the lines around it. See what is
  attached to each work, read a file again, free the space of one you uploaded (after a preview of what stays), or remove one. Scan a folder on the
  server for files that fit your works: exact matches attach in one press, and the rest you look over, attach or turn down. Attach one by hand from
  the server's folders, or send one from the phone (up to 25 MB), for a book, a film or a show's episode.
- People and characters console (Settings, Your library): every person and character your server keeps, with search that also finds other
  spellings, filters for no photo or no links and by kind, and counts of works and quotes. Open one, edit its spellings (the first line is the
  name shown), merge two that are the same (you choose the name that stays; the Bin can undo it), remove one, make a new character, ask the
  server to fetch the photos and details that are missing, and clear out people and characters nothing uses. Press and hold to choose two to merge.
- A character's page can be edited: its details, its picture (from the phone, or taken away), its spellings (press one to make it a record of its
  own), merging it into another character, and removing it. A person's page gains the same for spellings, merging and removing.
- The shelf: on a work's page, say where you are with it: Reading (Watching, Playing), Paused, Abandoned or Finished, with a bar for how far you
  are, and how many times you have finished it. It is the same shelf the web keeps, so a change on either shows on the other; the library list
  shows each work's status and bar. Changing it needs your server (it is kept there), and a refusal comes back in the server's own words.
- Search is a page of its own, like the web's: a search button on the Library, Catalogue and Quotes screens and a search box on Home open it.
  With your server it forgives typos ("showing results for ..."), and reads names, tags and genres as well as the words; without one it
  searches what is on the phone, and it says which it did. Results come in sections (titles, people, characters, tags, genres, notes, quotes)
  with the words you typed marked, portraits beside people, and a press opens the book, the quote or the person. Narrow a search with a
  Filter (author, director, actor, character, speaker, tag, genre, colour, language, series), by pressing a suggestion that appears as you type, or
  by typing it (`tag:life`, `author:"Le Guin"`), and with the scope chips (books, films and shows, highlights, film lines, quotes).
- Select many at once: press and hold a quote or a work in a list (the Library, Catalogue, Quotes and a work's own page), then press others. The
  bar at the top then favourites them, changes their colour, adds a tag or takes one off, sets one field (who said it, the chapter, the page,
  the language), moves them to a board, adds them to an anthology or deletes them (with Undo). For works it sets the author or the year,
  merges several into one (their quotes move onto the one you keep) or deletes them. Every change is an ordinary edit, so it works with no
  server and syncs afterwards.
- Run the server from your phone (admin accounts only, in Settings): add a reader, make an account an admin or step down, and remove an account;
  watch the server's jobs as they run and wait (with Stop, Run again, each job's log, and the common jobs to start); make a backup of the server, keep
  it on the phone, and put one back, from the server's own copy or from a file on the phone, after keeping a safety copy of what is there now; see the
  server's version, choose the stable or pre-release line, and update it where it can update itself (or copy the command where it cannot); add and
  remove the folders its library is read from and tidy saved files nothing uses; test each source it asks for details and set or clear its keys.
- Quote screen: a Copy button puts the quote and its credit on the clipboard, and after you delete a quote an Undo button brings it back, with
  its note, tags, colour and place.
- The quote form suggests as you write: the characters of the work you chose (and who else was already quoted from it) under "Who said it", the
  chapters you already used, and the tags your library already has. Press one to fill it in.
- Import and checks, in Settings: bring in a file and look over what it holds before it joins your library. Choose a Kindle My Clippings file,
  a Kindle notebook page, Bookcision, Readest, Goodreads, Hardcover, IMDb or Markdown, and your server reads it (it works out the format
  itself, or you name it). The quotes wait in a queue you review: edit a quote's colour, favourite mark and where it came from, shift page
  numbers or timestamps for a whole file, move a group onto the right book or film, then approve or discard one quote, a book or everything.
  The phone pulls the approved quotes straight away. A count shows in Settings and on the tab.
- Import Markdown into this phone with no server: a file in the form the app exports comes straight back into the library, and a book or
  quote you already have is left as it is, so importing the same file twice changes nothing.
- Stray marks, Corrections, and Times and places, the server's three checks, each with a count. Stray marks finds footnote numbers, doubled
  spaces and hidden characters in your quotes, shows the fix beside the problem, and lets you fix or ignore each (and bring an ignored one
  back). Corrections offers the words from a work's own file where your quote differs, a bucket at a time. Times and places offers the time a
  subtitle file gives a line, or the chapter and place a book's file gives a highlight.
- Your settings, the same on the phone and the web: Settings now has the account's own preferences, kept on your server so a change on one
  reaches the other. Text and quotes sets the size of the app's text and of a quote, the line height and length of a quote, a typeface for each
  language, and which separators split "Pratchett & Gaiman" into two people (a book with two authors now shows a pill for each). Colours names
  and re-shades the six quote colours and hides the ones you do not use. Sections chooses which of Library, Catalogue, Quotes and Anthologies
  show at the bottom, and how long the Bin keeps things. Daily review sets cards a day, what they are drawn from, how hard the questions are
  and the schedule. They work without a server too, and go up when it is reachable.
- Bengali: the app can be read in Bengali (Settings, Language), or follow the phone's language. It uses the same Bengali as the web app, and
  any language or correction you add on the server (its Locales folder) reaches the phone. A line with no translation shows in English.
- Account: a page for your picture and name, changing your password (a wrong current password says so, and does not unpair the phone),
  Pushover notifications and the widget key (shown once when it is made).
- Context around a quote: how many lines of the book or film show before and after a quote, for everything (Settings) and for one work (its
  menu), with the choice of what to do to quotes you had already adjusted.
- A page for every person and character: press a pill on a quote, a work's author in its header, or a row of a film's cast, and their page opens
  with the portrait (press it to see it big), dates, bio, links by provider (IMDb, Wikipedia and the rest), signature, other spellings, the
  works they are credited on, the parts they played and the quotes that name them. A character's page names who played them in each adaptation
  (press an actor to open theirs). "Show their quotes" filters the library by that name, as a press on a pill used to. Where your server allows
  it you can edit a person from the page: their details, the portrait (from the gallery or looked up by the server) and the signature.
- Faces on work cards and the work page: a work's card shows round portraits of its author or director, the work's page shows them as pills
  in its header, and each row of the cast has the character's picture (or the actor's). On a work's own page the author is not named again on
  every quote.
- Home, with the Daily Quiz and Practice: the app now opens on Home. It greets you for the time of day with the date and a line to think on,
  counts what you keep (books and quotes, titles and lines), and has your Daily Quiz: the few quotes your server has set for today, each one a
  question (which book or film is this from, which quote is from this work, who said it, who wrote it, fill in the blank by typing or by choosing).
  After each answer you see where every option came from, with covers and portraits. Practice goes through your whole library for as long as you
  like and lets you skip. An answer given with no network waits on the phone and is sent later, counting for the day it was given. Under the cards
  are where you stand (remembered, forgetting, probably forgotten, unseen), a Shuffle button for one line at random, the quotes you saved on this
  day in earlier years, and your favourites, each with the portrait pills.
- Tags page: every tag with its colour, how many quotes wear it and its style, in Settings and under the Tag chip in the library ("Manage
  tags"). Rename a tag, change its colour and style, make a new one, delete it, or long-press several and merge them into one. A change is made
  on your server and on every quote on the phone together, so the next sync has nothing to settle; with no server the phone's quotes are still
  changed, and it says the server was not. Tap a tag to read the quotes that wear it.
- A fuller Statistics page: an activity calendar of the last half year (what you saved, answered in the quiz and practised, with a tap on any
  day), where your quotes stand on the forgetting curve, highlight tiles with covers and faces (most annotated, most quoted, most favourited
  person, best remembered, most forgotten), a timeline by year or decade, a breakdown of authors, books, series, films, shows, directors,
  actors, characters and speakers with portraits and a bar for how well each is remembered, and a chart of your highlight colours. A name or a
  tag opens the quotes behind it.
- Anthologies are complete: drag passages into order (or use Move up and Move down), write your commentary before a passage, add headings with words
  under them, group passages by book, person or character, and choose what each passage shows (who it is by, the book, your commentary, the colour
  edge, where in the work, the date). Give an anthology a cover, an epigraph and a dedication. Fill it from a search: everything, a book, a film, a
  tag, an author, a colour, a shelf, your favourites or a stretch of dates, with a preview first and an option to keep adding as new quotes arrive.
  Passages you take out can be put back from Taken out, and the whole anthology can be saved or sent as a Markdown file or an EPUB book.
- Boards in full: a board has its own page with its picture, what it is for and its quotes, which you can sort (newest, oldest, A to Z, who said it,
  colour, favourites first) and group (who said it, language, colour). Give a board a picture and a description, say what kind it is (proverbs,
  speeches, letters, essays) and, for proverbs, which languages. Hide a board you do not file on, and put the boards in the order you want: the
  filing lists follow that order and leave out hidden boards. Add the server's starter proverbs to a proverb board in the language you choose.
  Everything the web sets on a board now shows here after a sync.
- Practise an anthology: open an anthology's menu and choose Practise to be quizzed on only its passages.
- Copy picture: the share picture can be copied to the clipboard and pasted into a chat or a note, as well as shared or saved.
- Add to anthology from any list: a quote in the library has a button for it (and a long press does the same), not only on the quote's own page.
- Portraits on the people pills: the round pill on a quote (the author of a book, the speaker, the character with the actor under their name) now
  shows the photo your server holds for them, as on the web, in the library, on the quote and on every card. A character shows its own picture,
  or the actor's if it has none. The photos are kept on the phone, so they are there without the server.

### Fixed
- The Quotes tab is the quote board again: it showed every quote, including the ones from your books and films. It now shows only quotes that
  belong to no work (a line from a speech, a proverb, something someone said), as on the web; the quotes of a book are in that book.
- The bottom bar no longer cuts words off: "Anthologies" was clipped on narrower phones or with large text. The labels are a little smaller, and
  when the bar is crowded only the open tab keeps its label.
- Signatures on the share picture: a signature your server keeps as a drawn (vector) picture, which is how most are stored, was left off the
  picture. It is drawn now. The share picture also takes the portraits and signature from the phone's own copy, so it can be made without the
  server, and a book's character can show its picture too.

## [0.6.0] - 2026-11-07

### Added

- People on the share picture: when your server has a photo of the author, the actor or the speaker, the picture shows small round portraits
  beside the name, or (Backdrop) the photo big and faded in from the edge behind the words. Swap changes which person comes first or which side
  they sit on. A film's quote can show the actor or the character (Actor / Character), and Signature puts the credited person's signature in the
  corner beside the Tippani mark. These choices are remembered, and the options appear only when the server has the pictures.

## [0.5.0] - 2026-11-07

### Added

- Boards stay the same on the phone and on the server: the boards you make here go up, the ones on your server (the Proverbs, Speeches
  and Others it starts with, and any you made on the web) come down, and a rename, a colour or a delete on one side reaches the other. The
  board a quote is filed on goes both ways too. When you delete a board here that has quotes, the server moves them to one of its other
  boards, since it will not leave a quote without one. If you change a board on both sides before a sync, the server's version is kept.
- Context from your server: a quote that is on the server has a Context section on its screen. Show where it comes from asks the server for what it stored
  around the quote in its source file (the paragraphs before and after, or a film's subtitle lines), with Show more before and after up to what is stored,
  and a note where the chapter or scene ends. It is asked for when you press it and is not kept on the phone.
- Author, actor and character chips: a quote shows the people on it as chips, as the web app does. A book's quote shows its author and who said it; a
  film's, show's or game's shows each character with the actor who plays them under the name (from the work's cast). They are in the Library list
  and on the quote screen, and pressing one shows the library for that name.
- Sync is lighter: it runs a few seconds after you change something, and once a day (when the app opens, comes back to the front, or the phone gets a
  network again, or once a day passes while it is open). The every-few-minutes timer and the retries are gone. A change that could not be sent waits and
  goes at the next opening, network or change, even after the app is closed.

### Changed

- Statistics, the Bin, Anthologies and Paired devices follow the new look: the numbers are cards, the bin and the lists are cards, and an empty
  Sync conflicts says so with an icon instead of a bare line.
- The picture of a quote is drawn as the web app draws it: Newsreader set on a card with a paper grain and a thin border, the Tippani mark and
  "made with tippani" at the foot, the author and work in the credit and the chapter in a small line beneath, tags as pills, your note in
  handwriting, and Bengali and Devanagari in their own fonts. You can choose Light or Dark and one of the web's eight materials (Manuscript, Film
  assembly, Office, School, Atelier, Bindery, Quarry, Atrium), and switch on the quote's colour as a stripe. Your choices are remembered. The
  file is 1280 pixels wide and as tall as the quote needs.
- A new look: the whole app is redrawn with its own type and shapes. Quotes are set in a serif (Source Serif 4) and the rest in Inter, both
  built in so they look the same on every phone. Quotes and works are cards (a work with no cover gets a lettered one in a colour taken from
  its title), the filters sit in one row of chips, Settings is grouped into blocks, empty lists say what to do, and bars, buttons, fields,
  dialogs and sheets share one rounded shape. The colours are still your phone's own.
- The app is laid out as the web app is: Library, Catalogue, Quotes and Anthologies, each with the web app's own icon, then Settings. The Library
  is your books, the Catalogue your films, shows and games, Quotes your quotes with their boards, and Anthologies is the collections on your server
  (it is there once the app can reach one). Each section reloads when something changes under it, from another section or from a sync. The
  Anthologies entry in Settings is gone; it is a tab now.
- What's new shows each change by a short header, not its details, and ends with a link to the full changelog on GitHub. It is in Settings, and the
  same short list is what you see after an update.
- The server is a section of Settings: the Server tab is gone. Settings now opens with a Server section (the address and whether it answers, Check
  again, pairing, paired devices, sync and the other things that need the server), and the app's own settings come after it, under App.

## [0.4.0] - 2026-11-07

### Changed

- After a page is read, you pick the passage right on the picture. Every word Tesseract found is drawn over the page: tap a word to take it or
  leave it out, drag a box across words to take them, or use Select all and Clear. The words you chose, in reading order (a word cut at a line's
  end mended, a gap on the page kept as a paragraph break), fill the text box, which you can still correct by hand. If the words' places cannot
  be had, you get the plain text as before.
- Scanning a page now starts with Straighten and crop. The app works out how the page is tilted and where the text is, and shows both: turn the
  picture with the slider or the nudge buttons (up to 15 degrees either way), and drag the corners of the frame to keep only the text. Auto
  works it out again, Reset starts over, and Use as is skips it. The page is read after it is straightened and cropped, which reads better.
- Scanning a page and speaking a quote are now on the Add a quote screen itself, under the words: Scan a page and Speak. What you scan or say
  goes into the words (after what is already there, so a second page does not wipe the first), where you can correct it before saving. The
  separate scan and microphone buttons on the Library and on a work's page are gone.

### Added

- Boards, on the phone: shelves for standalone quotes. Make, rename, colour and delete them from the Boards button in the Library (deleting a
  board keeps its quotes). File a standalone quote on a board from its form (a quote from a work stays with its work). In the Library, filter
  by a board, or by quotes on none, and turn on Group by board to see a heading over each board's quotes. Boards are in your backups. They do
  not sync with the server yet.
- A work's page now shows what your server knows about it: the description, genres, publisher, page count, ISBN and series, and the cast of a
  film or show or the characters of a book. It is fetched when you open the page (and again after a day), and kept, so it is still there
  without the server.
- Covers: a book's cover or a film's poster from your server now shows on the work's page and beside it in the Library's list of works.
  The picture is fetched once and kept on the phone, so it shows again without the server. For a work that is on the server, the menu on its
  page has Choose a cover, which sends a picture from your gallery to the server as the cover.
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
