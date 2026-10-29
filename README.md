# Dogecat Cross

Frogger-style game for the Solana OS badge, for the Breakpoint / Solana BP Badge App Store. You play a dogecat — a cat riding a doge — and hop it across lanes of traffic to the goal.

The title card is a Game Boy-style splash: **DOGECAT CROSS**, the line “a dogecat.com game”, and a blinking press-SELECT prompt. After a crash the card shows score, best, and press SELECT to retry.

## Install on a badge

1. Open the App Store at <https://solanadefcon.com/store/>.
2. Paste `jscianna/dogecat-cross` (a full `https://github.com/jscianna/dogecat-cross` URL works too).
3. Pick `dogecat-cross.lua`.
4. Enter the badge’s eight-character ID. On the badge that is **Settings → Identity**.
5. Send the offer. The person holding the badge presses SELECT to accept. Sending does not install anything by itself.

The broker reads `scripts/*.lua` from the repo’s default branch (`main`). The app id is the filename without `.lua`: `dogecat-cross`.

## Try it on the virtual badge

<https://solanadefcon.com/badge/> runs the same Solana OS Lua runtime in the browser.

1. Open the virtual badge and turn **Talk to a broker** on so the badge registers.
2. Copy the badge ID shown next to the screen.
3. Send `dogecat-cross.lua` from the App Store using that ID.
4. On the badge, accept the offer with SELECT, then launch **Dogecat Cross** from the launcher.

Keyboard on the virtual badge: arrow keys move, Enter or Z is SELECT, Esc or X is CANCEL. Holding CANCEL for about a second and a half force-quits back to the launcher even if a game has grabbed the button.

## Controls

- **D-pad** — hop one step. Up heads toward the goal.
- **SELECT** — start from the title, or retry after a splat.
- **CANCEL** — quit to the launcher from the title or during play (`badge.system.exit()`). On the game-over screen, CANCEL returns to the title.

## How to play

The yellow curb and the green rows are safe. Cars and trucks run the dark lanes, quicker as you get closer to the top, and a little quicker again each time you reach the goal. Every new step toward the goal scores, and a full crossing adds a bonus. Touching a vehicle ends the run.

The best score is kept on the badge with `badge.storage.kv` under the key `best` (4 characters; the store’s limit is 8). It survives a relaunch.

## Size

`scripts/dogecat-cross.lua` is **13,708 bytes**. The App Store allows 96 KB per script; this build stays well under the ~50 KB headroom target. There are no image files. The dogecat, traffic, and roads are drawn with `badge.gfx` primitives.

## SDK

Callbacks are `on_start`, `on_update(dt)`, `on_draw`, `on_button`, and `on_stop`. Drawing, input, LEDs, and the high score go through the `badge` global documented at <https://solanadefcon.com/os/>. The script does not use wallet, Phantom, or on-chain calls.

## License

MIT. See [LICENSE](LICENSE).
