# Playing online with friends

PokerFection needs no game server of its own to play online. Whoever creates
the room **hosts** it: the game runs inside their app, and everyone else
(the host's own app too) connects to it.

- **On the same Wi-Fi**, friends connect straight to the host's device over
  the home network. This works even without internet.
- **From anywhere else**, friends join with the same code or invite. A free
  public meeting service introduces the two devices, and then the game goes
  straight from device to device, encrypted. Nothing to set up: no router
  settings, no accounts.

This guide takes you through it step by step:

1. [Host a room](#1-host-a-room-on-windows) (on Windows)
2. [Invite friends](#2-invite-friends): on the same Wi-Fi, from anywhere,
   or in a browser
3. [When a direct connection isn't possible](#3-when-a-direct-connection-isnt-possible)
4. [What the public helpers see](#4-what-the-public-helpers-see)
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
   - **Internet: connecting…**, then **Internet: ready**: friends anywhere
     can join with the code or the invite. **Internet: not available**
     says why in brackets: *no connection* (no internet, or the meeting
     service can't be reached; the app keeps trying), or *busy* (the
     meeting service couldn't give the room a name: create a new room for
     friends elsewhere). Friends on your Wi-Fi can join either way.
     The **?** next to it explains how it works in a few lines.
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

The room uses port **47474** on your PC for friends on the same Wi-Fi (TCP
for the game, UDP for finding the room by its code). If another program
already uses it, the app takes the next free one (47475, 47476, … up to
47483). Friends from elsewhere don't use this port: they connect directly,
through the meeting service.

## 2. Invite friends

### Friends on the same Wi-Fi (easiest)

This always works, even without internet, with nothing to set up.

1. Your friends open PokerFection, press **Play > Multiplayer** and type
   their name.
2. They type the room code in the **Room code or invite link** box and
   press **Join Room**. The app finds the room on the network by itself.

You can also send them the invite (next part): it carries your PC's local
address, which is tried first.

Friends on a **guest Wi-Fi** network can't reach devices on the main one
(that is what guest networks are for): everyone should use the same
network.

### Friends anywhere else

Once the lobby says **Internet: ready**, friends anywhere can join:

- **With the code alone:** they type it on **Play Online** and press **Join
  Room**. The app first looks for the room on their own network, then asks
  the meeting service for it.
- **With the invite** (next part), which does the same in one click.

Joining from elsewhere takes a second or two with the code. With the
invite it can take a few seconds more: the app first tries your addresses
on your Wi-Fi (a few seconds each), then the meeting service. If a
friend's network can't connect directly to yours, they see "Can't connect
directly to the host from this network": see
[When a direct connection isn't possible](#3-when-a-direct-connection-isnt-possible).

### Sending the invite

1. In the lobby (or **☰ > Edit Table** during the game), press **Invite**.
2. Press **Copy invite link** and paste it into a chat, e-mail or text
   message, with the room code.

The link looks like
`https://williamszc380.github.io/PokerFection/join.html?code=K7M2Q&server=192.168.1.20:47474&server=peer:K7M2Q`.
It opens a small page with the room code and an **Open in the PokerFection
app** button, which opens the app at Play Online with everything filled in;
your friend types their name and presses **Join Room**. If the link doesn't
open the app, they can copy it, press the **Paste** button in the code box,
and press **Join Room**.

The link lists every way to reach you, in order, and the app tries them one
after the other:

1. your PC's addresses on the local network (same Wi-Fi: quickest);
2. `peer:K7M2Q`: the room through the meeting service, from anywhere;
3. sometimes, your router's public address: when your router lets the app
   open the port by itself (UPnP), the app does so quietly, as a second way
   in for friends whose network can't connect directly. You never need to
   set anything up for this.

A guest's own **Invite** works too: it carries the address they joined at,
then the room through the meeting service (when your room can be reached
there; never for a room on a server of your own).

### Friends without the app (in a browser)

Friends can play in Chrome, Edge, Firefox or Safari without installing
anything (on a computer, a tablet or a phone), from anywhere.

1. Press **Invite**, then **Copy invite link**, and send it: the same link
   as for friends with the app. Its page has, besides **Open in the
   PokerFection app**, a **Play in this browser** button.
2. That button opens the website at **Play Online** with the room code
   filled in. The website connects straight to your device through the
   meeting service, like the app does (and like the app, some networks
   can't connect directly: then try another network).
3. Your friend types their name and presses **Join Room**.

When you host in the Windows app (which includes the browser version), the
page also has **Play in this browser (on the same Wi-Fi as the host)**: it
opens your PC's own copy of the game, like
`http://192.168.1.20:47474/?code=K7M2Q`, which needs no internet and no
meeting service. Friends in a browser on your Wi-Fi can use it when the
first button doesn't work. When your router opened the port by itself,
there is also **(from anywhere else)**, your PC's copy at your public
address.

Good to know:

- An invite from an older version of the app (without `peer:` in it)
  shows **Play in this browser (on the same Wi-Fi as the host)** and
  **(from anywhere else)** buttons instead: they open the host's own copy
  of the game, like `http://192.168.1.20:47474/?code=K7M2Q`, which works
  only when that app includes the browser version (see the README:
  `dart run tool/build_web.dart --host`).
- On a host's own copy (http), the **Paste** button may not be allowed to
  read the clipboard: paste with **Ctrl+V** (or a long press on a phone) in
  the box instead.
- If the page reloads (phones do this to tabs in the background), the
  button reads **Rejoin Room**: it takes your friend back to their seat
  (kept for 2 minutes).
- A browser can host too: on the website, **Play > Multiplayer > Create
  Room** (greyed out in a browser without WebRTC, with why). The room runs
  in that tab, and every friend comes in through the meeting service, even
  on the same Wi-Fi (so it needs internet: the lobby shows **Same Wi-Fi:
  app only** greyed out). Keep the tab open: the lobby's **?** says so,
  closing the tab asks first, and then the room closes for everyone. A browser in the background may be slowed down by the browser
  itself; the app is the better host.
- In Chinese, the browser version downloads its Chinese font from the
  internet: on a network without internet access, use English or Spanish
  there. The chat's emoji come from the internet the same way (without
  it they show as empty boxes; **GG!** always works).

## 3. When a direct connection isn't possible

Most home networks let two devices connect directly. Some don't: mobile
data often, and some company, school or hotel networks. PokerFection has no
relay of its own that could carry the game between such networks, so then
your friend sees:

> Can't connect directly to the host from this network. Try another network
> (Wi-Fi instead of mobile data), or play on the same Wi-Fi.

What helps:

The same message ends a game for a player whose connection dropped and
who can't get back in from the network they are on now (a phone that
moved to mobile data, say).

1. **Try another network.** Connect the phone to Wi-Fi instead of mobile
   data (or the other way round), on either side.
2. **Let someone else host.** The connection depends on both networks: a
   friend on a different network may connect to everyone.
3. **Play on the same Wi-Fi.** It always works, even without internet.
4. **Host on Wi-Fi or a cable,** not on mobile data.

When your router opened the port by itself, invites also carry your public
address, so some of those friends still get in that way. This happens
quietly; there is nothing to set up.

## 4. What the public helpers see

Two kinds of free public services help devices on different networks find
each other. Neither carries the game.

- **The meeting service** (PeerJS's public server, `0.peerjs.com`):
  each room's host holds a name there made from the room code
  (`pokerfection-v1-K7M2Q`), and each guest a random one for a moment. They
  pass a few short messages through it to set up the connection: the
  devices' network addresses and the encryption keys' fingerprints. Once
  the devices are connected, nothing else goes through it; guests let go of
  their name after a few seconds, the host when the room closes.
- **STUN servers** (Google's and Cloudflare's): each device asks them once
  which address the internet sees it at.

They see your public IP address and the room code, never your name, the
chat, the cards or the bets: the game itself goes straight between the
devices, encrypted (WebRTC). On the same Wi-Fi none of this is used.

The room code is all it takes to ask your device for a connection, so
share it only with the people you invite. Guarding against someone who
knows it anyway:

- A player coming back to their seat proves it without sending the seat's
  secret over the internet: the proof is good for that one connection
  only. If someone took your room's name at the meeting service while your
  connection there was being made again, they learn nothing that gets
  them a seat, and your app takes the name back once it is free.
- A flood of made-up connection requests can keep new friends from
  joining over the internet for a while, but not players coming back to
  their seats, and never the same Wi-Fi. Connections that don't join a
  room within 15 seconds are closed. If it keeps happening, create a new
  room (it gets a new code).

**If a helper goes away** (these are free services with no guarantee):
the lobby says **Internet: not available (no connection)**, and friends
elsewhere can't join new rooms until it is back. Games already going keep
playing, since they don't go through it, and the same Wi-Fi keeps working
(in a browser too, through the invite page's **on the same Wi-Fi as the
host** button, when the host's app includes the browser version).
The app could switch to another meeting service later without changing how
you play.

## 5. Host from a phone

Android phones and tablets, iPhones and iPads can host too, the same way:
**Play > Multiplayer**, your name, an empty code box, **Create Room**.

- **Keep the app open on screen** while you host. The screen stays on by
  itself while you host; plug the phone in. If the app goes to the
  background or the phone locks, the room stops: players see
  "Reconnecting…" and, if you don't come back, "The host closed the room".
- Connect the phone to **Wi-Fi** if you can. On mobile data, friends
  elsewhere often can't connect directly (see
  [When a direct connection isn't possible](#3-when-a-direct-connection-isnt-possible)),
  and friends nearby can't reach you over the Wi-Fi.
- **iPhone and iPad**: allow **Local Network** when iOS asks, or friends on
  the Wi-Fi can't connect (to fix it later: Settings > Privacy & Security >
  Local Network > PokerFection). Finding the room by its code alone on the
  Wi-Fi may not work there either: the code still works through the meeting
  service, or send the invite.
- Phones don't serve the browser version: browser friends use the
  website's **Play in this browser** from the invite.
- A phone hosting 8 players with GTO help solves a lot: help may come a
  little late. A PC is the better host for big tables.

## 6. If something goes wrong

### "Room not found"

- Check the code (letters and digits, no I, L, O, 0 or 1).
- Is the host still in the room? The room ends when the host leaves.
- Does the host's lobby say **Internet: ready**? If not, only friends on
  the host's Wi-Fi can join.

### "Can't connect directly to the host from this network"

The room is there, but your network and the host's won't let the two
devices connect directly. See
[When a direct connection isn't possible](#3-when-a-direct-connection-isnt-possible).

### "Can't find the room: check the code and your internet"

The room isn't on your Wi-Fi, and the meeting service couldn't be asked:
check your internet connection, or ask the host for the invite.

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

- *(no connection)*: the host has no internet, or the meeting service
  can't be reached right now. The app keeps trying by itself; friends on
  the same Wi-Fi can still join.
- *(busy: create a new room)*: the meeting service couldn't give the room
  a name (someone else holds that code there). Close the room and create a
  new one (it gets another code).

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
within 2 minutes, the room closes. A friend who joined from elsewhere sees
"The host closed the room" only after the room has been missing at the
meeting service for 45 seconds, since the host's connection to it may just
be coming back.

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
invite would carry (and by the code alone), reports whether the router
opened the port, checks the browser version is served, deals a hand and
closes the room. `dart run tool/host_check.dart --no-router` does the same
without asking the router to open a port. The first time, Windows Firewall
may ask about Dart: allow it.

Run with plain Dart, the check can't make direct connections (they need the
app's WebRTC): it reports the meeting service as not available on this
device, and its invite names no room there. To check direct connections
through the real public helpers, run the app's live test:
`flutter test integration_test/peer_live_test.dart -d windows --dart-define=PEER_LIVE=1`.

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
must allow it (on Windows, allow `dart.exe` or your compiled program). This
server takes WebSocket connections only, with no meeting service: for
players on the internet, the computer must be reachable at a public
address (its router forwarding the port to it, which this server doesn't
set up).

Good to know:

- `http://<address>:47474/health` answers with the server's version and the
  number of rooms: handy to check it is reachable.
- Rooms live only in memory: stopping the server (Ctrl+C) ends every room,
  and players are told the server restarted.
- The server and the apps must come from the same version of the code:
  otherwise players are told to update the app.
- Here the room doesn't stop with the host's app: if the host's connection
  drops, the room waits 2 minutes for them, as for anyone else.
