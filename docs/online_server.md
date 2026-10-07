# Playing online with friends

PokerFection needs no outside service to play online. Whoever creates the
room **hosts** it: the game server runs inside their app, and everyone else
(the host's own app too) connects to it. Nothing goes through the internet
unless friends join from outside your home, and then they connect straight
to your device.

This guide takes you through it step by step:

1. [Host a room](#1-host-a-room-on-windows) (on Windows)
2. [Invite friends](#2-invite-friends): on the same Wi-Fi, over the
   internet, or in a browser
3. [Open the port by hand](#3-open-the-port-by-hand) when the automatic
   router setup didn't work
4. [When internet play isn't available](#4-when-internet-play-isnt-available)
5. [Host from a phone](#5-host-from-a-phone)
6. [If something goes wrong](#6-if-something-goes-wrong)

The last parts are for the curious: [checking hosting](#checking-that-hosting-works)
and [running the server on a computer of your own](#running-the-server-on-your-own-computer).

## 1. Host a room (on Windows)

A Windows PC that stays on and plugged in makes the best host. The host's
device also plays the bots and solves GTO help, so the faster it is, the
better.

1. Open PokerFection. Press **Play**, then **Multiplayer**. The **Play
   Online** screen opens.
2. Type your name.
3. Leave the **Room code or invite link** box empty and press **Create
   Room** at the bottom.
4. **The first time only**, Windows Firewall asks whether PokerFection may
   use the network:
   - tick **Private networks**;
   - also tick **Public networks** if your home network is set to "Public"
     (to check: Windows Settings > Network & internet > your Wi-Fi or
     Ethernet > Network profile type; you can switch it to **Private**
     there, which is right for a home network);
   - press **Allow access**.

   If you pressed Cancel by mistake, see
   [Friends on the same Wi-Fi can't connect](#friends-on-the-same-wi-fi-cant-connect).
5. The lobby opens. At the top:
   - the **room code** (five letters, for example `K7M2Q`) and the
     **Invite** button;
   - **Same Wi-Fi: yes**: friends on your network can join;
   - **Internet: checking…**, then **Internet: ready** (friends anywhere
     can join) or **Internet: not available** (only friends on your
     network, unless you [open the port by hand](#3-open-the-port-by-hand)
     and type your public address in the **Public address** box below it:
     then it says **Internet: set by hand**).
     The **?** next to it says why, and shows your port and local address.
6. Set the table. Everyone in the lobby sees your settings as you change
   them; only you can change them:
   - **Seats** (2 to 8), starting stack, **Ante**, **Min-Raise** rule;
   - **Help**: **None** (like Free Play), **Simple** or **Advanced** (like
     the app's training: every player's device works out GTO's answer);
   - **Time**: how long each player has to decide, **Off** (no limit,
     the default), 15, 30, 60, 90 or 120 s;
   - **Rebuys** (off by default): what happens to a player who loses all
     their chips (see [Out of chips](#out-of-chips-and-game-over));
   - **Reset Stacks Every Hand** (then nobody runs out of chips, and
     Rebuys is greyed out), **Show Play Styles** (whether guests see the
     bots' styles) and **Players Can See Others' Cards** (anyone may look
     at another player's cards; everyone is told when they do).
7. A new room has only you: the other seats are empty. Press **Add Bot**
   to seat a bot (pick its style), or **✕** to take one away. Friends who
   join take the empty seats; to remove one, tap their seat (see
   [Removing a player](#removing-a-player)).
8. Once at least 2 seats are taken, press **Start**. Everyone goes to the
   table.

Meanwhile everyone can talk in the lobby's **Chat** (see [Chat](#chat)).

During the game:

- **☰ > Edit Table** shows the seats and rules. You can add or take away
  bots, remove players and change the help, time and the two "show" options
  there; changes count from the next hand, and everyone is told. **Invite**
  is there too, for friends who come later: they sit down at the next hand.
- **☰ > Chat** has the room's chat.
- While others act, everyone's buttons become **pre-actions**: tick
  **Check/Fold**, **Check**, **Call** (the amount shown) or **Call Any**,
  and it is played the moment your turn comes, which makes the game faster.
  Check cancels itself if someone bets, Call if the bet changes, and each
  lasts until the street ends. With help on Simple the play is still
  scored; with Advanced there are none.
- **☰ > Sit Out**: from the next hand you aren't dealt in, but you keep
  your seat and your chips and watch the table (your seat says **Sitting
  out**). **I'm Back** (in ☰, or the button where your choices usually are)
  deals you in again from the next hand. Pressed between hands, it counts for the very next one:
  that hand is announced again without you (or with you). The host can sit
  out too; their app still plays the bots meanwhile.
- Players can join, leave and come back between hands; with fewer than 2
  players dealt in (the others sit out, say) the game waits.
- The host can remove a player: see [Removing a player](#removing-a-player).
- **The room lasts as long as you stay.** When you leave the table, press
  **Close Room** or close the app, the room closes for everyone ("The host
  closed the room").

### Out of chips and game over

A player who loses all their chips keeps their seat but isn't dealt in:

- **Rebuys off** (the default): they are out. Their seat says **Out**, and
  they watch the rest of the game at the table (without anyone's cards).
  **Lobby** shows the room meanwhile (**Watch** goes back to the table),
  and **Leave** leaves. A bot with no chips is out too.
- **Rebuys on**: they choose **Rebuy** (the starting stack again, from the
  next hand dealt; they watch until then) or **Leave**. Bots rebuy by
  themselves.

When only one player has chips left and nobody can rebuy, the game is over:
everyone sees "Game over: Alice wins" for a few seconds, then everyone is
back in the room's lobby, with the same seats, bots and rules. The host
presses **Start** for a new game: everyone gets the starting stack again.
Once someone has run out, players who leave count too: the last one with
chips wins. Before that, with fewer than 2 players the game just waits.

While the host is out (or sits out), the host's app still plays the bots,
but by their play style's rules: GTO bots play like TAG until the host is
dealt in again.

### Removing a player

The host taps the player's seat in the lobby (or in **☰ > Edit Table**
during the game), picks **Remove** and confirms.

- A player in the hand being played (who hasn't folded) plays it out, and
  goes when it ends (meanwhile their seat says **Leaves next hand**); anyone
  else goes at once.
- They see "The host removed you from the room"; everyone else sees
  "Ben was removed". Their seat is free (during the game, from the next
  hand).
- The room won't let them back in: not with **Rejoin Room**, nor with the
  invite or the code from the same app or browser (the app sends the room a
  random key it keeps, which says nothing else about the device). From
  another device they could still join: this is for friendly games, not a
  ban.

### Chat

Everyone in the room can chat: in the lobby (its **Chat** part), and at the
table from **☰ > Chat**, also while out of chips or waiting for a seat.

- Type a message and press Enter or the send button, or tap one of the
  quick messages: 😂 😭 😡 😱 🤥 🤡 🍀 **GG!**
- At the table, others' new messages show for a few seconds at the top of
  the table (two lines at most), then fade; they never cover your seat or
  your buttons. **☰ > Chat** has the whole conversation (with how many new
  messages came since you last looked).
- A message has up to 256 characters, on one line. Each player can send 4
  messages every 8 seconds: after that, sending is greyed out for a moment.
- The room keeps the last 64 messages: friends who join (or come back after
  their connection dropped) see them.

The room uses port **47474** on your PC (TCP for the game, UDP for finding
the room by its code). If another program already uses it, the app takes
the next free one (47475, 47476, … up to 47483); the lobby's **?** always
shows the port in use.

## 2. Invite friends

### Friends on the same Wi-Fi (easiest)

This always works, with nothing to set up.

1. Your friends open PokerFection, press **Play > Multiplayer** and type
   their name.
2. They type the room code in the **Room code or invite link** box and
   press **Join Room**. The app finds the room on the network by itself.

You can also send them the invite (next part): it carries your PC's local
address, which is tried first.

Friends on a **guest Wi-Fi** network can't reach devices on the main one
(that is what guest networks are for): everyone should use the same
network.

### Sending the invite

1. In the lobby (or **☰ > Edit Table** during the game), press **Invite**.
2. Press **Copy invite link** and paste it into a chat, e-mail or text
   message, with the room code.

The link looks like
`pokerfection://join?code=K7M2Q&server=192.168.1.20:47474&...`. On a
device with PokerFection, clicking it opens the app at Play Online with
everything filled in; your friend types their name and presses **Join
Room**. If the link doesn't open the app, they can copy it, press the
**Paste** button in the code box, and press **Join Room**.

The link lists every way to reach you, in order: your PC's addresses on the
local network first, then your public internet address when the router
opened the port (or when you typed it, see
[Open the port by hand](#3-open-the-port-by-hand)). The app tries them one
after the other.

### Friends on the internet

**If the lobby says "Internet: ready"**, your router opened the port by
itself (this is called UPnP). Just send the invite link: it now includes
your public address, and friends anywhere can join with it.

Good to know:

- The app keeps the port open while the room is open and closes it again
  when the room closes. If the app is killed, the router forgets the
  opening by itself within an hour (a few routers only when they restart).
- The port outside may differ from 47474 (when that one is taken in the
  router, the app picks another); the invite always has the right one.
  Some routers won't renew an opening: then the app opens another port
  every 20 minutes and the invite changes with it (friends already in
  stay in).
- Your router's UPnP page may list old "PokerFection" or "miniupnpd"
  entries after rooms have closed (some routers keep a trace of closed
  openings). They lead nowhere; restarting the router clears them.
- Joining at your own public address from inside your home may fail even
  when it works for friends outside (many routers don't loop back); ask a
  friend to try.

**If the lobby says "Internet: not available"**, tap the **?** next to it
to see why:

- *No router answered the automatic setup*: UPnP is off in your router (or
  it has none). Either turn **UPnP** on in the router's settings and create
  the room again, or [open the port by hand](#3-open-the-port-by-hand).
- *Your router refused to open the port*: [open it by hand](#3-open-the-port-by-hand).
- *Your router has no public address of its own*: see
  [When internet play isn't available](#4-when-internet-play-isnt-available).

### Friends without the app (in a browser)

A host on Windows also serves the browser version of the game, so friends
can play in Chrome, Edge, Firefox or Safari without installing anything
(on a computer, a tablet or a phone).

1. Press **Invite**, then **Copy browser link**, and send it. It is an
   address like `http://192.168.1.20:47474/?code=K7M2Q` (your PC on the
   Wi-Fi), or, once the lobby says **Internet: ready** (or **set by
   hand**), one with your public address, like
   `http://203.0.113.7:47474/?code=K7M2Q`, which works from anywhere.
2. Your friend opens the address. The **Play Online** screen opens with the
   room code filled in.
3. They type their name and press **Join Room**.

Good to know:

- **Copy browser link** only appears when your app includes the browser
  version. Windows builds include it once it has been built (see the
  README: `dart run tool/build_web.dart --host`); the phone apps don't
  serve it.
- Some routers don't let a device at home reach the home's own public
  address. If a friend on your Wi-Fi can't open the public browser link,
  give them the Wi-Fi one instead: `http://<your PC's local address>:47474/?code=K7M2Q`
  (the lobby's **?** next to Internet shows the local address).
- Use the address from the invite, not the PokerFection website: browsers
  don't let a secure (https) website reach a game on someone's PC.
- On that page the **Paste** button may not be allowed to read the
  clipboard: paste with **Ctrl+V** (or a long press on a phone) in the box
  instead.
- If the page reloads (phones do this to tabs in the background), the
  button reads **Rejoin Room**: it takes your friend back to their seat
  (kept for 2 minutes).
- A browser can't host a room, only join one.
- In Chinese, the browser version downloads its Chinese font from the
  internet: on a network without internet access, use English or Spanish
  there. The chat's emoji come from the internet the same way (without
  it they show as empty boxes; **GG!** always works).

## 3. Open the port by hand

Do this once if the automatic setup didn't work. You need your router's
settings page (the address and password are usually on a sticker on the
router).

1. In the lobby, tap the **?** next to **Internet**. Note the **port**
   (normally 47474) and your PC's **local address** (like `192.168.1.20`).
2. Open your router's settings: type its address in a browser (often
   `192.168.1.1` or `192.168.0.1`; also printed on the router) and log in.
3. Find **Port forwarding**. Routers call it different names: Virtual
   servers, NAT, Applications & gaming, Port mapping.
4. Add a rule:
   - Protocol: **TCP**;
   - External (or public) port: **47474**;
   - Internal (or private) port: **47474**;
   - Device or internal IP address: your PC's local address from step 1.

   Save it.
5. Find your **public address**: the router's app or status page shows it
   (as WAN, Internet or public IP address), or search the web for "what is
   my IP". Say it is `203.0.113.7`.
6. Back in the lobby, type it in the **Public address** box under
   **Internet** (the box shows while the lobby doesn't say **Internet:
   ready**; its **?** repeats these steps with your port and local
   address). If the rule's external port isn't the room's port, add it:
   `203.0.113.7:47500`. The lobby then says **Internet: set by hand**, and
   the invite (after your local addresses) and **Copy browser link** carry
   your public address. The app remembers it for your next rooms; empty the
   box to stop using it.
7. Check it from outside: the app can't. A friend opens
   `http://203.0.113.7:47474/health` in a browser. It should show
   "PokerFection server, …". If the page doesn't load, the rule or the
   firewall isn't right yet.

Without the box (a server of your own, say), friends can still join at
your public address: an app link they click or paste,
`pokerfection://join?code=K7M2Q&server=203.0.113.7:47474`; the **Server**
line under the code box on Play Online, `ws://203.0.113.7:47474/ws`, then
the room code; or for browser friends, `http://203.0.113.7:47474/?code=K7M2Q`.

Keep the rule working next time:

- Your PC's local address can change when it reconnects to the Wi-Fi. In
  the router, give it a fixed one (called "address reservation", "static
  lease" or "DHCP reservation").
- If 47474 was busy and the room used another port (the **?** says which),
  the rule must use that port instead.
- Most home internet connections change their public address from time to
  time: look it up again before you play, and correct the **Public
  address** box.

## 4. When internet play isn't available

Some internet providers share one public address between many homes. This
is called **CGNAT**, and **mobile data** almost always works this way. Then
nobody outside can reach your device: not with the automatic setup, not by
hand. The lobby's **?** says so ("Your router has no public address of its
own"); you can also tell when the public address on the router's status
page starts with `100.64` to `100.127`, `10.`, `172.16` to `172.31` or
`192.168.`, or doesn't match what "what is my IP" shows.

The same happens when a second router sits in front of yours (for example
the internet provider's box in front of your own Wi-Fi router). Then you can
open the port in both, or set the provider's box to "bridge mode".

What you can do, without any outside service:

1. **Play on the same Wi-Fi.** It always works: friends who come over, or
   family on the home network.
2. **Let a friend host.** Their connection may allow it: if their lobby
   says **Internet: ready**, everyone joins their room instead.
3. **Ask your internet provider for a public IPv4 address.** Many give one
   on request (sometimes for a small fee); then the automatic setup or the
   port rule works.
4. Don't host on mobile data: connect the host to Wi-Fi or a cable.

## 5. Host from a phone

Android phones and tablets, iPhones and iPads can host too, the same way:
**Play > Multiplayer**, your name, an empty code box, **Create Room**.

- **Keep the app open on screen** while you host. The screen stays on by
  itself while you host; plug the phone in. If the app goes to the
  background or the phone locks, the room stops: players see
  "Reconnecting…" and, if you don't come back, "The host closed the room".
- Connect the phone to **Wi-Fi**. On mobile data, friends on the internet
  can't join (see [CGNAT](#4-when-internet-play-isnt-available)).
- **iPhone and iPad**: allow **Local Network** when iOS asks, or friends on
  the Wi-Fi can't connect (to fix it later: Settings > Privacy & Security >
  Local Network > PokerFection). The automatic router setup doesn't work
  there (Apple doesn't allow it without a special permission): open the
  port by hand if you need it. Finding the room by its code alone may not
  work either: send the invite.
- Phones don't serve the browser version: friends need the app (or host on
  Windows for browser friends).
- A phone hosting 8 players with GTO help solves a lot: help may come a
  little late. A PC is the better host for big tables.

## 6. If something goes wrong

### "Room not found"

- Check the code (letters and digits, no I, L, O, 0 or 1).
- Are you on the same Wi-Fi as the host? If not, you need the invite.
- Is the host still in the room? The room ends when the host leaves.

### Friends on the same Wi-Fi can't connect

- **Firewall on the host's PC**: Windows Security > Firewall & network
  protection > **Allow an app through firewall** > **Change settings**,
  find PokerFection and tick **Private** (and **Public** if your network is
  public), then OK. Other security software may have its own firewall:
  allow PokerFection there too.
- **Guest network** or "AP isolation" / "client isolation" in the router:
  devices on it can't reach each other. Use the main Wi-Fi.
- A **VPN** on the host's or the friend's device can hide the local
  network: turn it off while playing.
- Try the invite instead of the code alone (the invite has the host's
  address).

### "Internet: not available"

See [Friends on the internet](#friends-on-the-internet),
[Open the port by hand](#3-open-the-port-by-hand) and
[When internet play isn't available](#4-when-internet-play-isnt-available).

### "Reconnecting…"

Wi-Fi hiccups happen. A player whose connection drops keeps their seat for
**2 minutes**:

- The app reconnects by itself and catches up with the hand. A move made
  meanwhile is sent once it is back, if it is still that player's turn.
- The others see **Away** on that seat; the game checks or folds for that
  player after 3 seconds at each turn. Once a whole hand has gone by without
  them, they sit out (the next hands are dealt without them, rather than
  folding for them hand after hand) until they come back: then they are
  dealt in again. If fewer than 2 players can play, the game waits.
- If the app was closed (or the browser page reloaded), **Play > Multiplayer
  > Rejoin Room** takes them back to their seat.
- After 2 minutes the seat is given up: it is empty from the next hand, and
  coming back means joining again ("You were away too long: join again").

If the **host's** connection drops, the bots only check or fold (and the
game waits between hands) until the host is back; if the host isn't back
within 2 minutes, the room closes.

### Other messages

- **"Update the app to play"**: your app and the host's are different
  versions. Update both (or rebuild both from the same code).
- **"Table full"**: every seat is taken (people and bots). The host can
  take a bot away (or, in the lobby, add seats, up to 8).
- **"The host closed the room"**: the host left, closed the room or closed
  the app.
- **"The host removed you from the room"**: the host removed you (see
  [Removing a player](#removing-a-player)); that room won't let you in
  again.
- **"Connection lost"**: the connection couldn't come back in time. Ask
  the host for the invite and join again.
- A room where no hand is dealt for half an hour (in the lobby, or waiting
  for players) closes by itself.

## Checking that hosting works

From the project folder, `dart run tool/host_check.dart` does what Create
Room does on this computer: it starts a room, joins it at every address the
invite would carry (and by the code alone), reports how the router setup
went, checks the browser version is served, deals a hand and closes the
room. `dart run tool/host_check.dart --no-router` does the same without
asking the router to open a port; it checks a public address set by hand
goes in the invite instead. The first time, Windows Firewall may ask about
Dart: allow it.

## Running the server on your own computer

You don't need this to play: Create Room already runs the server. But you
can run the same server on its own, for example on a computer that stays on
at home, so the room doesn't depend on anyone's app staying open.

You need the Dart SDK (the one inside Flutter works: `flutter/bin/dart`).
From the project folder:

```
dart run bin/server.dart
```

It listens on port 47474 on every network of the computer. Settings, as
environment variables:

- `PORT`: another port.
- `WEB`: a folder with the browser version, to serve it to browser players
  (build it with `dart run tool/build_web.dart --host`, into
  `build/web_host`).

For example, on Windows (PowerShell):

```
$env:PORT = "47500"; $env:WEB = "build\web_host"; dart run bin/server.dart
```

To make a single program that runs without the SDK, on the computer it will
run on:

```
dart compile exe bin/server.dart -o pokerfection_server
```

To play on it:

1. Everyone opens Play Online, opens the **Server** line under the code box
   and enters `ws://<the computer's address>:47474/ws` (its local address on
   the same network, or its public address from the internet).
2. One player presses **Create Room**: the room is made on that server, and
   that player is its host (sets up the table, plays the bots).
3. The others join with the room code.

What applies to a host's device applies to that computer too: the firewall
must allow it (on Windows, allow `dart.exe` or your compiled program), and
for friends on the internet the router must forward the port to it (by
hand: this server doesn't ask the router).

Good to know:

- `http://<address>:47474/health` answers with the server's version and the
  number of rooms: handy to check it is reachable.
- Rooms live only in memory: stopping the server (Ctrl+C) ends every room,
  and players are told the server restarted.
- The server and the apps must come from the same version of the code:
  otherwise players are told to update the app.
- Here the room doesn't stop with the host's app: if the host's connection
  drops, the room waits 2 minutes for them, as for anyone else.
