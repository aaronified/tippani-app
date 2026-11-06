# Changelog

All notable changes to the app are recorded here. The format is [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and the
app reads this file itself: it shows the entry for the version it has just been updated to, and the What's new screen lists every
version. Write each entry for the person using the app, in plain words.

## [Unreleased]

### Added

- The app keeps a library of its own on the phone, so it works with no server. Works and quotes, with tags, colours, favourites,
  your notes, translations and where in the book each came from, are stored in the app, and searched by their words, the work's
  title and author, who said them, and their tags. A server is something you can add later, not a way in.
- The app opens on your Library: every quote and work, searchable by words, people, works and tags, with a Favourites filter and a tag
  filter. Add a quote or a work, open one to change or delete it, and give a quote its own colour. Deleting a work says how many
  quotes go with it first.
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
