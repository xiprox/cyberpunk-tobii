# Tobii Head Tracking for Cyberpunk 2077

`RECORD.md` holds what we found and decided, newest entry first; add an entry when a finding or decision changes how the mod works.
Don't edit `version.txt`, `CHANGELOG.md`, or `.release-please-manifest.json` by hand: release-please's pull request changes them.

## Commits

Every commit message is a [Conventional Commit](https://www.conventionalcommits.org), because release-please turns `feat` and `fix` commits into releases and skips any message it can't parse.
release-please writes `CHANGELOG.md` from commit titles.
A `feat` or `fix` title lands there verbatim, under Features or Bug Fixes, so **the title is a release note** and is written for the person reading one.

- **Type.** `feat` is anything new or changed that a player will notice, including polish worth announcing.
  `fix` is something that was wrong and now isn't.
  `style` is a change to how the settings menu or overlay looks or reads that isn't worth a line in the changelog: a reworded description, a reordered option.
  Between `feat` and `style`, ask whether the change would be announced.
  Here `style` means the mod's look, not code formatting.
  `refactor`, `docs`, `test`, `ci`, and `chore` are for changes nobody playing would notice.
  Everything but `feat` and `fix` stays out of the changelog.
- **Scope** is a part of the mod a player recognizes, never a file or a layer: `tracker` (finding and reading the Tobii tracker, its status), `camera` (how the view turns and moves: level turns, the neck, the twist, leaning), `calibration` (Recenter and Calibrate head turns), `smoothing`, `car` (the seat, the headrest lean, auto-centering), `settings` (the settings menu), `overlay`, `hotkeys`, and `install` (the release zip and its layout).
  Not `plugin` or `cet`, which are layers.
- **Title.** Say what the player gets or can now do, never what the code does, and use no internal names.
  Something to do reads as an instruction (`press Recenter from a hotkey`); something to see reads as a statement (`head turns stay level on foot`).
  No "ability to", since the Features heading already says that.
  No em dashes.
  Lower case after the colon, no full stop, and spell-checked, since the title ships in the changelog as typed.
- **One change per commit.**
  A title that needs "and" is two commits.
- **Description.** Why, never what, since the diff shows what.
  Show the concrete case rather than naming a property of it: "turning 90° left with the view pitched 12° down rolled the horizon 12°", not "for correctness".
  It never restates the title, so it's as long as the reason and no longer, and absent when the title is enough.
  Mention verification only when something went unchecked, and say what: "Untested in the passenger seat: only the driver's seat was tried in the game."

### How Claude proposes a commit

Claude commits only when asked, and never picks the wording on its own.

1. **List every proposed commit in the reply**, in order, each as a code block holding the exact title and description.
   The split is part of the proposal.
2. **Ask about one commit at a time**, in order, with one AskUserQuestion call per commit holding exactly two questions.
   The commit text goes in each option's label, where it's read at a glance; the small print under it says which option it is.
   - **`Commit 2 of 5: which title?`**, header `Title`.
     The suggested title, described as `Suggested`, then an alternative only when there's a real one, described by what it changes (`Narrower scope`).
   - **`Commit 2 of 5: which description?`**, header `Description`.
     The suggested description's first sentence, described as `Suggested`, with the full text as its preview; then `None`.
     When the suggestion is no description, `None` comes first and one short description second.

   Other is how a different wording arrives, and it's used exactly as typed.
   A different split is also given through Other, on the title question.
3. **Commit as soon as the answers arrive**, then show `git log --oneline -1` and ask about the next one.
   The co-author trailer is added to every description, including a chosen None, and isn't shown in the options.
